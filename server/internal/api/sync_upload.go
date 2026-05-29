package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// UploadHandler applies PowerSync client write batches to Postgres. It is the
// target of the Flutter client's uploadData connector (Plan 5b).
type UploadHandler struct {
	pool *pgxpool.Pool
}

func NewUploadHandler(pool *pgxpool.Pool) *UploadHandler { return &UploadHandler{pool: pool} }

type crudOp struct {
	Op    string         `json:"op"`
	Table string         `json:"table"`
	Type  string         `json:"type"` // Dart CrudEntry emits "type" for the table name
	ID    string         `json:"id"`
	Data  map[string]any `json:"data"`
}

func (o crudOp) tableName() string {
	if o.Table != "" {
		return o.Table
	}
	return o.Type
}

type uploadRequest struct {
	Batch []crudOp `json:"batch"`
}

// Upload applies the whole batch in one transaction. CONTRACT (PowerSync):
// never return 4xx for validation/ownership/bad-data (it permanently blocks the
// client's upload queue) — log + skip and still return 2xx. Return 5xx only for
// transient DB errors so the SDK retries the identical batch.
func (h *UploadHandler) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := UserIDFromContext(r.Context())
	if !ok || userID == "" {
		writeJSONError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	dec := json.NewDecoder(r.Body)
	dec.UseNumber() // keep weight_kg exact (json.Number, not float64)
	var req uploadRequest
	if err := dec.Decode(&req); err != nil {
		slog.Warn("upload: malformed body, accepting as no-op", "err", err)
		writeJSON(w, http.StatusOK, map[string]int{"applied": 0})
		return
	}

	ctx := r.Context()
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		writeJSONError(w, http.StatusServiceUnavailable, "db unavailable")
		return
	}
	defer func() { _ = tx.Rollback(ctx) }()

	applied := 0
	topGroups := map[[2]string]struct{}{} // {sessionID, exerciseID}
	prExercises := map[string]struct{}{}

	for _, op := range req.Batch {
		err := applyOp(ctx, tx, userID, op, topGroups, prExercises)
		if err == nil {
			applied++
			continue
		}
		if isTransient(err) {
			writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
			return // defer rolls back; client retries the same batch
		}
		slog.Warn("upload: skipping op", "table", op.tableName(), "op", op.Op, "id", op.ID, "err", err)
	}

	for g := range topGroups {
		if err := recomputeTopSet(ctx, tx, g[0], g[1]); err != nil {
			if isTransient(err) {
				writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
				return
			}
			slog.Warn("upload: top-set recompute failed", "err", err)
		}
	}
	for ex := range prExercises {
		if err := recomputePR(ctx, tx, userID, ex); err != nil {
			if isTransient(err) {
				writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
				return
			}
			slog.Warn("upload: pr recompute failed", "err", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		writeJSONError(w, http.StatusServiceUnavailable, "commit failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"applied": applied})
}

// isTransient reports whether err is a retryable DB error (serialization,
// deadlock, or connection-level). Everything else is treated as permanent.
func isTransient(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "40001" || pgErr.Code == "40P01"
	}
	return errors.Is(err, context.DeadlineExceeded) || pgconn.SafeToRetry(err)
}

// applyOp dispatches one CRUD op to its table handler. Unknown tables/ops are a
// permanent (skip) error. Ops that touch sets register their group/exercise for
// recompute. Tx (pgx.Tx) is the active batch transaction.
func applyOp(ctx context.Context, tx pgx.Tx, userID string, op crudOp, topGroups map[[2]string]struct{}, prExercises map[string]struct{}) error {
	switch op.tableName() {
	case "sessions":
		return applySession(ctx, tx, userID, op)
	case "bodyweight_logs":
		return applyBodyweight(ctx, tx, userID, op)
	case "exercises":
		return applyExercise(ctx, tx, userID, op)
	case "sets":
		return applySet(ctx, tx, userID, op, topGroups, prExercises)
	default:
		return fmt.Errorf("unknown table %q", op.tableName())
	}
}

// --- per-table apply helpers ---
// Owner columns (sessions.user_id, bodyweight_logs.user_id, exercises.created_by,
// sets.user_id) are stamped server-side from userID; any client-supplied value is
// ignored. PUT = upsert by id; PATCH = update; DELETE = delete (no-op if absent).
// All updates/deletes are constrained to rows the user owns.

func str(data map[string]any, key string) (string, bool) {
	v, ok := data[key]
	if !ok || v == nil {
		return "", false
	}
	switch t := v.(type) {
	case string:
		return t, true
	case json.Number:
		return t.String(), true
	case bool:
		if t {
			return "true", true
		}
		return "false", true
	default:
		return fmt.Sprintf("%v", t), true
	}
}

func applySession(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "PUT":
		date, _ := str(op.Data, "date")
		label, _ := str(op.Data, "split_label")
		notes, _ := str(op.Data, "notes")
		_, err := tx.Exec(ctx,
			`INSERT INTO sessions (id, user_id, date, split_label, notes)
			 VALUES ($1::uuid, $2::uuid, $3::date, NULLIF($4,''), NULLIF($5,''))
			 ON CONFLICT (id) DO UPDATE SET date=EXCLUDED.date, split_label=EXCLUDED.split_label, notes=EXCLUDED.notes
			 WHERE sessions.user_id = $2::uuid`,
			op.ID, userID, date, label, notes)
		return err
	case "PATCH":
		date, _ := str(op.Data, "date")
		label, _ := str(op.Data, "split_label")
		notes, _ := str(op.Data, "notes")
		_, err := tx.Exec(ctx,
			`UPDATE sessions SET
			   date = COALESCE(NULLIF($3,'')::date, date),
			   split_label = COALESCE(NULLIF($4,''), split_label),
			   notes = COALESCE(NULLIF($5,''), notes)
			 WHERE id = $1::uuid AND user_id = $2::uuid`,
			op.ID, userID, date, label, notes)
		return err
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid AND user_id=$2::uuid`, op.ID, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

func applyBodyweight(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "PUT":
		date, _ := str(op.Data, "date")
		weight, _ := str(op.Data, "weight_kg")
		_, err := tx.Exec(ctx,
			`INSERT INTO bodyweight_logs (id, user_id, date, weight_kg)
			 VALUES ($1::uuid, $2::uuid, $3::date, $4::numeric)
			 ON CONFLICT (id) DO UPDATE SET date=EXCLUDED.date, weight_kg=EXCLUDED.weight_kg
			 WHERE bodyweight_logs.user_id = $2::uuid`,
			op.ID, userID, date, weight)
		return err
	case "PATCH":
		date, _ := str(op.Data, "date")
		weight, _ := str(op.Data, "weight_kg")
		_, err := tx.Exec(ctx,
			`UPDATE bodyweight_logs SET
			   date = COALESCE(NULLIF($3,'')::date, date),
			   weight_kg = COALESCE(NULLIF($4,'')::numeric, weight_kg)
			 WHERE id=$1::uuid AND user_id=$2::uuid`,
			op.ID, userID, date, weight)
		return err
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM bodyweight_logs WHERE id=$1::uuid AND user_id=$2::uuid`, op.ID, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

// applyExercise handles user-created CUSTOM exercises only. created_by is stamped
// from the token and is_template is forced false; template rows (created_by NULL)
// can never be written or modified by a client.
func applyExercise(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "PUT":
		name, _ := str(op.Data, "name")
		slug, _ := str(op.Data, "slug")
		muscle, _ := str(op.Data, "muscle_group")
		_, err := tx.Exec(ctx,
			`INSERT INTO exercises (id, name, slug, muscle_group, is_template, created_by)
			 VALUES ($1::uuid, $2, $3, $4, false, $5::uuid)
			 ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, slug=EXCLUDED.slug, muscle_group=EXCLUDED.muscle_group
			 WHERE exercises.created_by = $5::uuid`,
			op.ID, name, slug, muscle, userID)
		return err
	case "PATCH":
		name, _ := str(op.Data, "name")
		muscle, _ := str(op.Data, "muscle_group")
		_, err := tx.Exec(ctx,
			`UPDATE exercises SET
			   name = COALESCE(NULLIF($3,''), name),
			   muscle_group = COALESCE(NULLIF($4,''), muscle_group)
			 WHERE id=$1::uuid AND created_by=$2::uuid`,
			op.ID, userID, name, muscle)
		return err
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM exercises WHERE id=$1::uuid AND created_by=$2::uuid`, op.ID, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

// applySet writes a set. PowerSync PATCH opData carries ONLY the changed columns,
// so PATCH/DELETE operate by id (constrained to the owner) and read the stored
// (session_id, exercise_id) back via RETURNING for recompute — never assume those
// columns are present, and never default omitted columns (that would clobber, e.g.
// flip is_warmup). PUT requires session_id, used to stamp user_id from the parent
// session and reject cross-user writes. Touched groups/exercises drive recompute.
func applySet(ctx context.Context, tx pgx.Tx, userID string, op crudOp, topGroups map[[2]string]struct{}, prExercises map[string]struct{}) error {
	switch op.Op {
	case "DELETE":
		var sessionID, exerciseID string
		err := tx.QueryRow(ctx,
			`DELETE FROM sets WHERE id=$1::uuid AND user_id=$2::uuid
			 RETURNING session_id::text, exercise_id::text`,
			op.ID, userID).Scan(&sessionID, &exerciseID)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil // already gone / not owned — no-op
		}
		if err != nil {
			return err
		}
		topGroups[[2]string{sessionID, exerciseID}] = struct{}{}
		prExercises[exerciseID] = struct{}{}
		return nil

	case "PATCH":
		// Omitted columns arrive as "" so NULLIF→NULL and COALESCE preserves the
		// stored value. Do NOT default is_warmup here. Read the group back so
		// recompute targets the actual persisted row, not client-sent values.
		weight, _ := str(op.Data, "weight_kg")
		reps, _ := str(op.Data, "reps")
		setNum, _ := str(op.Data, "set_number")
		warm, _ := str(op.Data, "is_warmup")
		var sessionID, exerciseID string
		err := tx.QueryRow(ctx,
			`UPDATE sets SET
			   weight_kg  = COALESCE(NULLIF($3,'')::numeric, weight_kg),
			   reps       = COALESCE(NULLIF($4,'')::numeric::int, reps),
			   set_number = COALESCE(NULLIF($5,'')::numeric::int, set_number),
			   is_warmup  = COALESCE(NULLIF($6,'')::bool, is_warmup),
			   updated_at = NOW()
			 WHERE id=$1::uuid AND user_id=$2::uuid
			 RETURNING session_id::text, exercise_id::text`,
			op.ID, userID, weight, reps, setNum, warm).Scan(&sessionID, &exerciseID)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil // not found / not owned — no-op
		}
		if err != nil {
			return err
		}
		topGroups[[2]string{sessionID, exerciseID}] = struct{}{}
		prExercises[exerciseID] = struct{}{}
		return nil

	case "PUT":
		sessionID, _ := str(op.Data, "session_id")
		exerciseID, _ := str(op.Data, "exercise_id")
		if sessionID == "" || exerciseID == "" {
			return fmt.Errorf("set PUT missing session_id/exercise_id")
		}
		// Verify the user owns the parent session (the user_id we stamp).
		var ownerID string
		err := tx.QueryRow(ctx, `SELECT user_id::text FROM sessions WHERE id=$1::uuid`, sessionID).Scan(&ownerID)
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("set references unknown session %s", sessionID)
		}
		if err != nil {
			return err
		}
		if ownerID != userID {
			return fmt.Errorf("set references session owned by another user")
		}
		setNum, _ := str(op.Data, "set_number")
		weight, _ := str(op.Data, "weight_kg")
		reps, _ := str(op.Data, "reps")
		rir, hasRir := str(op.Data, "rir")
		warm, _ := str(op.Data, "is_warmup")
		if warm == "" {
			warm = "false" // correct insert default for a new set
		}
		rirArg := any(nil)
		if hasRir && rir != "" {
			rirArg = rir
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO sets (id, session_id, exercise_id, user_id, set_number, weight_kg, reps, rir, is_warmup, updated_at)
			 VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::numeric::int, $6::numeric, $7::numeric::int, $8::numeric::int, $9::bool, NOW())
			 ON CONFLICT (id) DO UPDATE SET
			   exercise_id=EXCLUDED.exercise_id, set_number=EXCLUDED.set_number, weight_kg=EXCLUDED.weight_kg,
			   reps=EXCLUDED.reps, rir=EXCLUDED.rir, is_warmup=EXCLUDED.is_warmup, updated_at=NOW()
			 WHERE sets.user_id = $4::uuid`,
			op.ID, sessionID, exerciseID, userID, setNum, weight, reps, rirArg, warm)
		if err != nil {
			return err
		}
		topGroups[[2]string{sessionID, exerciseID}] = struct{}{}
		prExercises[exerciseID] = struct{}{}
		return nil

	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

// recomputeTopSet sets is_top_set=true on the single heaviest non-warmup set in
// the (session, exercise) group and false on the rest. Deterministic tie-break.
func recomputeTopSet(ctx context.Context, tx pgx.Tx, sessionID, exerciseID string) error {
	if _, err := tx.Exec(ctx,
		`UPDATE sets SET is_top_set = false WHERE session_id=$1::uuid AND exercise_id=$2::uuid`,
		sessionID, exerciseID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx,
		`UPDATE sets SET is_top_set = true WHERE id = (
		   SELECT id FROM sets
		   WHERE session_id=$1::uuid AND exercise_id=$2::uuid AND is_warmup = false
		   ORDER BY weight_kg DESC, reps DESC, set_number ASC, id ASC
		   LIMIT 1
		 )`,
		sessionID, exerciseID)
	return err
}

// recomputePR recomputes is_pr for all of the user's non-warmup sets for an
// exercise. is_pr = the set is its session's top set AND its weight strictly
// exceeds the max non-warmup weight in strictly-earlier-dated sessions.
func recomputePR(ctx context.Context, tx pgx.Tx, userID, exerciseID string) error {
	if _, err := tx.Exec(ctx,
		`UPDATE sets SET is_pr = false WHERE user_id=$1::uuid AND exercise_id=$2::uuid`,
		userID, exerciseID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx,
		`WITH ns AS (
		   SELECT st.id, st.weight_kg, st.is_top_set, se.date AS sdate
		   FROM sets st JOIN sessions se ON se.id = st.session_id
		   WHERE st.user_id=$1::uuid AND st.exercise_id=$2::uuid AND st.is_warmup = false
		 )
		 UPDATE sets t SET is_pr = true
		 FROM ns a
		 WHERE t.id = a.id
		   AND a.is_top_set
		   AND a.weight_kg > COALESCE((SELECT MAX(b.weight_kg) FROM ns b WHERE b.sdate < a.sdate), -1)`,
		userID, exerciseID)
	return err
}
