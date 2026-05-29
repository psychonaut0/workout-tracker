# Plan 5a — Backend Write Path & Logging Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend half of workout logging — the `sessions`/`sets`/`bodyweight_logs` tables, a seeded exercise catalog with user-created custom exercises, the single `POST /sync/upload` endpoint that PowerSync's client `uploadData` connector targets, server-computed `is_top_set`/`is_pr`, and sync rules so all of it replicates to the client.

**Architecture:** PowerSync replicates Postgres→client; for writes, the Flutter client (Plan 5b) batches local mutations and POSTs them to our Go backend, which applies them to Postgres, and the existing logical-replication stream carries the canonical rows back down. This plan builds that backend write endpoint plus the tables, seeding, sync rules, and the top-set/PR computation. The endpoint is a single `POST /sync/upload` accepting `{"batch":[{op,table,id,data}]}`, applied in one pgx transaction, authenticated with the API access token, with ownership and the computed flags stamped server-side. The Flutter `uploadData` connector itself is deferred to Plan 5b.

**Tech Stack:** Go 1.26, chi v5, pgx/v5 (+ `pgconn` for error classification), goose migrations, the existing RS256 auth (`RequireAuth`/`UserIDFromContext`), PowerSync 1.21 (publication + sync rules), OpenAPI 3.1 (vacuum-linted).

**Spec sections covered:** Data model → `sessions`/`sets`/`bodyweight_logs`; "is_top_set/is_pr computed server-side"; "exercises seeded from the README split"; Architecture → the write path (uploadData → Go API → Postgres → sync back). Resolves the spec's "model the split vs free-form" open question (flat catalog now; structured day-templates in the follow-on plan).

---

## Decisions locked (research-verified + your answers)

| Topic | Decision |
| ----- | -------- |
| Write endpoint | Single `POST /sync/upload`, body `{"batch":[{op,table,id,data}]}`, applied in **one** pgx tx. Mounted inside the existing `RequireAuth(Verifier, APIAudience)` group (API access token, NOT the PowerSync JWT). |
| **No 4xx** | Validation/ownership/bad-data → **log + skip the op, still return 2xx** (a 4xx permanently blocks the client's upload queue). `5xx` only for transient DB errors (serialization 40001, deadlock 40P01, conn loss) so the SDK retries the identical batch. |
| Idempotency | PUT = `INSERT … ON CONFLICT (id) DO UPDATE`; PATCH = `UPDATE … WHERE id`; DELETE = `DELETE … WHERE id` (no-op if absent). Ops are re-sent on retry. |
| Writable tables | `exercises` (custom user exercises — `created_by` stamped server-side, `is_template` forced false), `sessions`, `sets`, `bodyweight_logs`. Server stamps owner columns from the token subject; client-supplied owner fields are ignored. |
| `sets.user_id` | **Denormalized** `user_id` on `sets` (PowerSync classic sync rules can't JOIN), stamped from the parent session on write; sync rule filters `sets WHERE user_id = bucket.user_id`. |
| Replica identity | Default (PK) on all new tables — UUID PKs suffice; no `REPLICA IDENTITY FULL`. |
| `is_top_set` | Per `(session_id, exercise_id)`: the single heaviest **non-warmup** set by `weight_kg DESC, reps DESC, set_number ASC, id ASC`; recomputed for the whole touched group after the batch applies. |
| `is_pr` | **Heaviest weight ever** (your choice): a set is `is_pr` iff it's its session's top set AND its `weight_kg` strictly exceeds the max non-warmup `weight_kg` in strictly-earlier-dated sessions for that user+exercise. Not retroactively re-walked on historical edits (YAGNI; ~24h edit window). |
| Numeric precision | Decode the body with `json.Decoder.UseNumber()` and pass `weight_kg` as a string to Postgres `NUMERIC` (no float64 rounding). |
| Decoder robustness | Accept the table name from either `table` or `type` (Dart `CrudEntry.toJson` emits `type`; the demo connectors send `table`) so the endpoint can't drift from the Plan-5b connector. |
| Split modeling | Flat seeded catalog + user custom exercises **now**; structured day-templates in the follow-on plan. `sessions.split_label` is free-text. |

**Deferred:** the Flutter `uploadData` connector (Plan 5b); `day_templates`/`day_template_items` (the follow-on backend plan); server-side 24h-edit enforcement; a `muscle_group` CHECK constraint; retroactive PR recompute.

## Conventions

Repo-root commands (`make -C server …`); Conventional Commits subject-only; goose 5-digit migrations; no "Plan N" literals in committed files; OpenAPI at `api/openapi.yaml` (vacuum-linted). The dev stack runs on Postgres host 5433.

## File structure

```
server/db/migrations/00005_seed_template_exercises.sql      # NEW: 24 README exercises (is_template)
server/db/migrations/00006_create_sessions.sql              # NEW
server/db/migrations/00007_create_sets.sql                  # NEW (incl. denormalized user_id)
server/db/migrations/00008_create_bodyweight_logs.sql       # NEW
server/db/migrations/00009_powersync_publish_workout_tables.sql  # NEW: ALTER PUBLICATION
powersync/sync-rules.yaml                                   # MODIFY: sync sessions/sets/bodyweight
server/internal/api/sync_upload.go                          # NEW: Upload handler + apply + recompute
server/internal/api/sync_upload_test.go                     # NEW
server/internal/api/router.go                               # MODIFY: register /sync/upload, Deps.Upload
server/cmd/server/main.go                                   # MODIFY: construct UploadHandler
api/openapi.yaml                                            # MODIFY: document POST /sync/upload
```

---

### Task 1: Migrations — sessions, sets (with user_id), bodyweight_logs, publication, seed

**Files:**
- Create: `server/db/migrations/00005_seed_template_exercises.sql`
- Create: `server/db/migrations/00006_create_sessions.sql`
- Create: `server/db/migrations/00007_create_sets.sql`
- Create: `server/db/migrations/00008_create_bodyweight_logs.sql`
- Create: `server/db/migrations/00009_powersync_publish_workout_tables.sql`

- [ ] **Step 1: Write `00005_seed_template_exercises.sql`**

```sql
-- +goose Up
-- Seed the flat list of template exercises from the README training split.
-- Templates have created_by = NULL and is_template = TRUE, so the `templates`
-- sync-rules bucket replicates them to every user as a read-only catalog.
-- Idempotent via ON CONFLICT (slug) DO NOTHING.
INSERT INTO exercises (name, slug, muscle_group, is_template, created_by) VALUES
    ('Incline bench press',       'incline-bench-press',       'chest',     TRUE, NULL),
    ('Chest press',               'chest-press',               'chest',     TRUE, NULL),
    ('Seated DB shoulder press',  'seated-db-shoulder-press',  'shoulders', TRUE, NULL),
    ('DB lateral raise',          'db-lateral-raise',          'shoulders', TRUE, NULL),
    ('Reverse pec deck',          'reverse-pec-deck',          'shoulders', TRUE, NULL),
    ('Rope triceps pushdown',     'rope-triceps-pushdown',     'triceps',   TRUE, NULL),
    ('Overhead rope extension',   'overhead-rope-extension',   'triceps',   TRUE, NULL),
    ('Hack squat',                'hack-squat',                'quads',     TRUE, NULL),
    ('Leg press',                 'leg-press',                 'quads',     TRUE, NULL),
    ('Leg extension',             'leg-extension',             'quads',     TRUE, NULL),
    ('Seated leg curl',           'seated-leg-curl',           'hamstrings',TRUE, NULL),
    ('Standing calf raise',       'standing-calf-raise',       'calves',    TRUE, NULL),
    ('Lat pulldown',              'lat-pulldown',              'back',      TRUE, NULL),
    ('Row',                       'row',                       'back',      TRUE, NULL),
    ('Iliac pulldown',            'iliac-pulldown',            'back',      TRUE, NULL),
    ('Cable row',                 'cable-row',                 'back',      TRUE, NULL),
    ('Preacher curl',             'preacher-curl',             'biceps',    TRUE, NULL),
    ('Cable hammer curl',         'cable-hammer-curl',         'biceps',    TRUE, NULL),
    ('Cable curl',                'cable-curl',                'biceps',    TRUE, NULL),
    ('Romanian deadlift',         'romanian-deadlift',         'hamstrings',TRUE, NULL),
    ('Hack squat (depth focus)',  'hack-squat-depth-focus',    'quads',     TRUE, NULL),
    ('Lying leg curl',            'lying-leg-curl',            'hamstrings',TRUE, NULL),
    ('Unilateral leg extension',  'unilateral-leg-extension',  'quads',     TRUE, NULL),
    ('Seated calf raise',         'seated-calf-raise',         'calves',    TRUE, NULL)
ON CONFLICT (slug) DO NOTHING;

-- +goose Down
DELETE FROM exercises WHERE slug IN (
    'incline-bench-press', 'chest-press', 'seated-db-shoulder-press',
    'db-lateral-raise', 'reverse-pec-deck', 'rope-triceps-pushdown',
    'overhead-rope-extension', 'hack-squat', 'leg-press', 'leg-extension',
    'seated-leg-curl', 'standing-calf-raise', 'lat-pulldown', 'row',
    'iliac-pulldown', 'cable-row', 'preacher-curl', 'cable-hammer-curl',
    'cable-curl', 'romanian-deadlift', 'hack-squat-depth-focus',
    'lying-leg-curl', 'unilateral-leg-extension', 'seated-calf-raise'
) AND is_template = TRUE AND created_by IS NULL;
```

- [ ] **Step 2: Write `00006_create_sessions.sql`**

```sql
-- +goose Up
-- A training session: one workout on one date. split_label names the rotation
-- slot (e.g. "Upper A"); notes is freeform. UUID PK → default REPLICA IDENTITY
-- is enough for PowerSync to replicate UPDATE/DELETE.
CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date            DATE NOT NULL,
    split_label     TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX sessions_user_date_idx ON sessions (user_id, date DESC);

-- +goose Down
DROP TABLE sessions;
```

- [ ] **Step 3: Write `00007_create_sets.sql`** (note the denormalized `user_id` — load-bearing for the sync rule)

```sql
-- +goose Up
-- A single working/warmup set within a session. weight_kg is NUMERIC for exact
-- decimal loads. rir = reps-in-reserve. is_warmup is client intent; is_top_set
-- and is_pr are computed server-side on write (never trusted from the client).
-- user_id is DENORMALIZED from the parent session and stamped server-side on
-- write: PowerSync classic sync rules cannot JOIN, so the per-user sync rule
-- filters sets directly on this column. updated_at supports the editable window.
CREATE TABLE sets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    exercise_id     UUID NOT NULL REFERENCES exercises(id),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    set_number      INTEGER NOT NULL,
    weight_kg       NUMERIC(6, 2) NOT NULL,
    reps            INTEGER NOT NULL,
    rir             INTEGER,
    is_warmup       BOOLEAN NOT NULL DEFAULT FALSE,
    is_top_set      BOOLEAN NOT NULL DEFAULT FALSE,
    is_pr           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX sets_session_idx ON sets (session_id, set_number);
CREATE INDEX sets_exercise_idx ON sets (exercise_id, created_at);
CREATE INDEX sets_user_id_idx ON sets (user_id);

-- +goose Down
DROP TABLE sets;
```

- [ ] **Step 4: Write `00008_create_bodyweight_logs.sql`**

```sql
-- +goose Up
-- A bodyweight entry on a date. weight_kg is NUMERIC for exact decimal weights.
CREATE TABLE bodyweight_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date            DATE NOT NULL,
    weight_kg       NUMERIC(5, 2) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX bodyweight_logs_user_date_idx ON bodyweight_logs (user_id, date DESC);

-- +goose Down
DROP TABLE bodyweight_logs;
```

- [ ] **Step 5: Write `00009_powersync_publish_workout_tables.sql`**

```sql
-- +goose Up
-- Add the workout tables to the "powersync" publication so their row changes
-- enter the logical-replication stream. Publication name is fixed as "powersync"
-- (00004). refresh_tokens stays EXCLUDED — token hashes must never replicate.
ALTER PUBLICATION powersync ADD TABLE sessions;
ALTER PUBLICATION powersync ADD TABLE sets;
ALTER PUBLICATION powersync ADD TABLE bodyweight_logs;

-- +goose Down
ALTER PUBLICATION powersync DROP TABLE bodyweight_logs;
ALTER PUBLICATION powersync DROP TABLE sets;
ALTER PUBLICATION powersync DROP TABLE sessions;
```

- [ ] **Step 6: Apply and verify**

Run from repo root (Postgres up on 5433):

```bash
make -C server migrate-up
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d sessions' -c '\d sets' -c '\d bodyweight_logs'
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT tablename FROM pg_publication_tables WHERE pubname='powersync' ORDER BY tablename;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT count(*) FROM exercises WHERE is_template = true;"
```

Expected: all three `\d` descriptions show the columns (`sets` includes `user_id`); `pg_publication_tables` lists `bodyweight_logs, exercises, sessions, sets`; the template count is `>= 24`.

- [ ] **Step 7: Verify rollback then re-apply**

```bash
make -C server migrate-down   # drops bodyweight_logs (00008)
make -C server migrate-up
make -C server migrate-status
```

Expected: down/up cycle clean; status shows migrations 00001–00009 all `Applied`.

- [ ] **Step 8: Commit**

```bash
git add server/db/migrations/0000{5,6,7,8,9}_*.sql
git commit -m "feat(server): sessions/sets/bodyweight tables, exercise seed, publication"
```

---

### Task 2: Sync rules for the new tables

**Files:**
- Modify: `powersync/sync-rules.yaml`

- [ ] **Step 1: Replace `powersync/sync-rules.yaml`** with EXACTLY:

```yaml
# PowerSync sync rules. A client receives, scoped to the authenticated user
# (request.user_id() = the JWT sub): their own exercises, sessions, sets, and
# bodyweight logs — plus all template exercises via the global `templates`
# bucket. Each data query is a single-table SELECT (PowerSync classic sync rules
# do not support JOINs); `sets` is filtered on its denormalized user_id column.
bucket_definitions:
  by_user:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM exercises WHERE created_by = bucket.user_id
      - SELECT * FROM sessions WHERE user_id = bucket.user_id
      - SELECT * FROM sets WHERE user_id = bucket.user_id
      - SELECT * FROM bodyweight_logs WHERE user_id = bucket.user_id
  templates:
    data:
      - SELECT * FROM exercises WHERE is_template = true
```

- [ ] **Step 2: Validate YAML + restart PowerSync to reload the rules**

Run from repo root:

```bash
python3 -c "import yaml; d=yaml.safe_load(open('powersync/sync-rules.yaml')); assert 'by_user' in d['bucket_definitions'] and 'templates' in d['bucket_definitions']; print('yaml OK')"
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env restart powersync
for i in $(seq 1 24); do hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1 2>/dev/null || echo none); [ "$hc" = "healthy" ] && break; sleep 5; done
echo "powersync: $(docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1)"
```

Expected: `yaml OK`; powersync returns to `healthy`.

- [ ] **Step 3: Confirm the rules compiled with no error**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env logs powersync --since 60s 2>&1 \
  | grep -iE 'Replicating "public"\.\("sessions"|"sets"|"bodyweight_logs"\)|fatal|Failed to update sync config' | tail -20
```

Expected: lines showing the new tables being replicated; NO `fatal` / `Failed to update sync config` errors. (If a sync-rules error appears, it names the offending query — fix and restart.)

- [ ] **Step 4: Commit**

```bash
git add powersync/sync-rules.yaml
git commit -m "feat(powersync): sync sessions, sets, and bodyweight to each user"
```

---

### Task 3: Upload handler — decode, transaction, dispatch (TDD)

**Files:**
- Create: `server/internal/api/sync_upload.go`
- Create: `server/internal/api/sync_upload_test.go`

- [ ] **Step 1: Write the failing tests** (handler shape + the no-4xx contract, using fakes where possible; DB-touching cases are integration tests gated on the dev DB via the existing `testPool` pattern — but `testPool` lives in the `auth` package, so these tests use a local pool helper)

File `server/internal/api/sync_upload_test.go`:

```go
package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func uploadTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping DB integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seedUploadUser inserts a throwaway user and returns its id; cleaned up after.
func seedUploadUser(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	ctx := context.Background()
	var id string
	email := "upl-" + randomHex(t) + "@example.com"
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1,'x') RETURNING id::text`, email).Scan(&id); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE id=$1::uuid`, id) })
	return id
}

// postUpload runs the handler with userID injected into context (as RequireAuth would).
func postUpload(t *testing.T, h *UploadHandler, userID, body string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/sync/upload", strings.NewReader(body))
	if userID != "" {
		req = req.WithContext(context.WithValue(req.Context(), userIDKey, userID))
	}
	h.Upload(rec, req)
	return rec
}

func TestUpload_RequiresAuth(t *testing.T) {
	h := NewUploadHandler(uploadTestPool(t))
	rec := postUpload(t, h, "", `{"batch":[]}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestUpload_MalformedBodyIsNot4xx(t *testing.T) {
	h := NewUploadHandler(uploadTestPool(t))
	rec := postUpload(t, h, "00000000-0000-0000-0000-000000000000", `not json`)
	if rec.Code >= 400 && rec.Code < 500 {
		t.Fatalf("malformed body must NOT be 4xx (blocks upload queue); got %d", rec.Code)
	}
}

func TestUpload_CreatesSessionAndSets(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()

	var exID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID); err != nil {
		t.Fatalf("need a seeded template exercise: %v", err)
	}
	sessionID := "11111111-1111-1111-1111-111111111111"
	body := `{"batch":[
      {"op":"PUT","table":"sessions","id":"` + sessionID + `","data":{"id":"` + sessionID + `","date":"2026-05-29","split_label":"Upper A"}},
      {"op":"PUT","table":"sets","id":"22222222-2222-2222-2222-222222222222","data":{"id":"22222222-2222-2222-2222-222222222222","session_id":"` + sessionID + `","exercise_id":"` + exID + `","set_number":1,"weight_kg":"60.00","reps":8,"is_warmup":false}},
      {"op":"PUT","table":"sets","id":"33333333-3333-3333-3333-333333333333","data":{"id":"33333333-3333-3333-3333-333333333333","session_id":"` + sessionID + `","exercise_id":"` + exID + `","set_number":2,"weight_kg":"80.00","reps":6,"is_warmup":false}}
    ]}`
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid`, sessionID) })

	rec := postUpload(t, h, user, body)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d body=%s", rec.Code, rec.Body.String())
	}

	// The session and both sets exist, scoped to the user; sets carry user_id.
	var nSets int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM sets WHERE session_id=$1::uuid AND user_id=$2::uuid`, sessionID, user).Scan(&nSets); err != nil {
		t.Fatalf("count sets: %v", err)
	}
	if nSets != 2 {
		t.Fatalf("sets: got %d, want 2", nSets)
	}
	// The 80kg set is the top set; the 60kg is not.
	var topWeight string
	if err := pool.QueryRow(ctx, `SELECT weight_kg::text FROM sets WHERE session_id=$1::uuid AND is_top_set=true`, sessionID).Scan(&topWeight); err != nil {
		t.Fatalf("top set: %v", err)
	}
	if topWeight != "80.00" {
		t.Errorf("top set weight: got %s, want 80.00", topWeight)
	}
}

func TestUpload_PutIsIdempotent(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	sessionID := "44444444-4444-4444-4444-444444444444"
	body := `{"batch":[{"op":"PUT","table":"sessions","id":"` + sessionID + `","data":{"id":"` + sessionID + `","date":"2026-05-29","split_label":"A"}}]}`
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid`, sessionID) })

	if rec := postUpload(t, h, user, body); rec.Code != http.StatusOK {
		t.Fatalf("first: %d", rec.Code)
	}
	if rec := postUpload(t, h, user, body); rec.Code != http.StatusOK {
		t.Fatalf("retry must be 2xx (idempotent): %d %s", rec.Code, rec.Body.String())
	}
	var n int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM sessions WHERE id=$1::uuid`, sessionID).Scan(&n)
	if n != 1 {
		t.Errorf("idempotent PUT should yield 1 row, got %d", n)
	}
}

func TestUpload_RejectsCrossUserSessionButStays2xx(t *testing.T) {
	pool := uploadTestPool(t)
	owner := seedUploadUser(t, pool)
	attacker := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	sessionID := "55555555-5555-5555-5555-555555555555"
	// owner creates a session
	postUpload(t, h, owner, `{"batch":[{"op":"PUT","table":"sessions","id":"`+sessionID+`","data":{"id":"`+sessionID+`","date":"2026-05-29"}}]}`)
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid`, sessionID) })

	// attacker tries to write a set into the owner's session — must be skipped, still 2xx
	var exID string
	_ = pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID)
	rec := postUpload(t, h, attacker, `{"batch":[{"op":"PUT","table":"sets","id":"66666666-6666-6666-6666-666666666666","data":{"id":"66666666-6666-6666-6666-666666666666","session_id":"`+sessionID+`","exercise_id":"`+exID+`","set_number":1,"weight_kg":"50.00","reps":5}}]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("cross-user write must stay 2xx, got %d", rec.Code)
	}
	var n int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM sets WHERE id='66666666-6666-6666-6666-666666666666'`).Scan(&n)
	if n != 0 {
		t.Errorf("cross-user set must NOT be written, got %d rows", n)
	}
}
```

File `server/internal/api/uploadhelpers_test.go` (test-only random hex; `randomSuffix` lives in the `auth` package, not here):

```go
package api

import (
	"crypto/rand"
	"encoding/hex"
	"testing"
)

func randomHex(t *testing.T) string {
	t.Helper()
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		t.Fatalf("rand: %v", err)
	}
	return hex.EncodeToString(b)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make -C server test`
Expected: build failure — `undefined: UploadHandler` / `NewUploadHandler`.

- [ ] **Step 3: Write `server/internal/api/sync_upload.go`** — decode + tx orchestration + dispatch only. The per-table apply functions and the recompute functions are appended in Tasks 4 and 5; **the package does not compile until Task 5**. Tasks 3–5 build this one file together and produce a single commit at the end of Task 5 (this is a deliberate build-up; Tasks 3 and 4 are checkpoints with no commit).

```go
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
```

- [ ] **Step 4: Run tests** — they still fail (the apply/recompute funcs `applySession`/`applySet`/`applyExercise`/`applyBodyweight`/`recomputeTopSet`/`recomputePR` are undefined). That's expected; they're implemented in Tasks 4–5.

Run: `make -C server test`
Expected: build failure — `undefined: applySession` etc. (Do NOT commit yet; the package doesn't compile until Task 5.)

This task is a checkpoint, not a commit. Proceed directly to Task 4.

---

### Task 4: Per-table apply functions

**Files:**
- Modify: `server/internal/api/sync_upload.go` (add the apply functions)

- [ ] **Step 1: Append the apply functions to `sync_upload.go`**

```go

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

// applySet stamps user_id from the PARENT session (verifying the user owns it);
// a set referencing a session the user does not own is rejected (skip). Touched
// (session, exercise) groups and exercises are registered for recompute.
func applySet(ctx context.Context, tx pgx.Tx, userID string, op crudOp, topGroups map[[2]string]struct{}, prExercises map[string]struct{}) error {
	if op.Op == "DELETE" {
		// Capture the group before deleting so we can recompute it.
		var sessionID, exerciseID string
		err := tx.QueryRow(ctx, `SELECT session_id::text, exercise_id::text FROM sets WHERE id=$1::uuid AND user_id=$2::uuid`, op.ID, userID).Scan(&sessionID, &exerciseID)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil // already gone / not owned — no-op
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM sets WHERE id=$1::uuid AND user_id=$2::uuid`, op.ID, userID); err != nil {
			return err
		}
		topGroups[[2]string{sessionID, exerciseID}] = struct{}{}
		prExercises[exerciseID] = struct{}{}
		return nil
	}

	sessionID, _ := str(op.Data, "session_id")
	exerciseID, _ := str(op.Data, "exercise_id")
	if sessionID == "" || exerciseID == "" {
		return fmt.Errorf("set missing session_id/exercise_id")
	}
	// Verify the user owns the parent session; this also yields the user_id to stamp.
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
		warm = "false"
	}
	rirArg := any(nil)
	if hasRir && rir != "" {
		rirArg = rir
	}

	if op.Op == "PUT" {
		_, err = tx.Exec(ctx,
			`INSERT INTO sets (id, session_id, exercise_id, user_id, set_number, weight_kg, reps, rir, is_warmup, updated_at)
			 VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::int, $6::numeric, $7::int, $8::int, $9::bool, NOW())
			 ON CONFLICT (id) DO UPDATE SET
			   exercise_id=EXCLUDED.exercise_id, set_number=EXCLUDED.set_number, weight_kg=EXCLUDED.weight_kg,
			   reps=EXCLUDED.reps, rir=EXCLUDED.rir, is_warmup=EXCLUDED.is_warmup, updated_at=NOW()
			 WHERE sets.user_id = $4::uuid`,
			op.ID, sessionID, exerciseID, userID, setNum, weight, reps, rirArg, warm)
	} else { // PATCH
		_, err = tx.Exec(ctx,
			`UPDATE sets SET
			   weight_kg = COALESCE(NULLIF($3,'')::numeric, weight_kg),
			   reps = COALESCE(NULLIF($4,'')::int, reps),
			   set_number = COALESCE(NULLIF($5,'')::int, set_number),
			   is_warmup = COALESCE(NULLIF($6,'')::bool, is_warmup),
			   updated_at = NOW()
			 WHERE id=$1::uuid AND user_id=$2::uuid`,
			op.ID, userID, weight, reps, setNum, warm)
	}
	if err != nil {
		return err
	}
	topGroups[[2]string{sessionID, exerciseID}] = struct{}{}
	prExercises[exerciseID] = struct{}{}
	return nil
}
```

- [ ] **Step 2: Run tests** — still failing on `recomputeTopSet`/`recomputePR` (undefined). Expected. Proceed to Task 5.

Run: `make -C server test`
Expected: build failure — `undefined: recomputeTopSet` / `recomputePR`. No commit yet.

---

### Task 5: Top-set + PR recompute (TDD green + commit)

**Files:**
- Modify: `server/internal/api/sync_upload.go` (add recompute functions)
- Modify: `server/internal/api/sync_upload_test.go` (add the PR test)

- [ ] **Step 1: Append the recompute functions to `sync_upload.go`**

```go

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
```

- [ ] **Step 2: Add the PR test** to `sync_upload_test.go`:

```go

func TestUpload_PRFlagsHeaviestAcrossSessions(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	var exID string
	_ = pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID)

	s1, s2 := "77777777-7777-7777-7777-777777777777", "88888888-8888-8888-8888-888888888888"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id IN ($1::uuid,$2::uuid)`, s1, s2) })

	// Session 1 (earlier): top set 100kg → PR (first ever).
	postUpload(t, h, user, `{"batch":[
	  {"op":"PUT","table":"sessions","id":"`+s1+`","data":{"id":"`+s1+`","date":"2026-05-20"}},
	  {"op":"PUT","table":"sets","id":"a1111111-1111-1111-1111-111111111111","data":{"id":"a1111111-1111-1111-1111-111111111111","session_id":"`+s1+`","exercise_id":"`+exID+`","set_number":1,"weight_kg":"100.00","reps":5,"is_warmup":false}}
	]}`)
	// Session 2 (later): 110kg → new PR; a 90kg set → not a PR.
	postUpload(t, h, user, `{"batch":[
	  {"op":"PUT","table":"sessions","id":"`+s2+`","data":{"id":"`+s2+`","date":"2026-05-27"}},
	  {"op":"PUT","table":"sets","id":"a2222222-2222-2222-2222-222222222222","data":{"id":"a2222222-2222-2222-2222-222222222222","session_id":"`+s2+`","exercise_id":"`+exID+`","set_number":1,"weight_kg":"90.00","reps":8,"is_warmup":false}},
	  {"op":"PUT","table":"sets","id":"a3333333-3333-3333-3333-333333333333","data":{"id":"a3333333-3333-3333-3333-333333333333","session_id":"`+s2+`","exercise_id":"`+exID+`","set_number":2,"weight_kg":"110.00","reps":3,"is_warmup":false}}
	]}`)

	var prCount int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM sets WHERE exercise_id=$1::uuid AND user_id=$2::uuid AND is_pr=true`, exID, user).Scan(&prCount)
	if prCount != 2 {
		t.Errorf("expected 2 PRs (100kg in s1, 110kg in s2), got %d", prCount)
	}
	var prWeightS2 string
	_ = pool.QueryRow(ctx, `SELECT weight_kg::text FROM sets WHERE session_id=$1::uuid AND is_pr=true`, s2).Scan(&prWeightS2)
	if prWeightS2 != "110.00" {
		t.Errorf("s2 PR should be the 110kg set, got %s", prWeightS2)
	}
}
```

- [ ] **Step 3: Run tests to verify they pass** (requires the dev DB; migrations applied)

Run: `make -C server test`
Expected: all `sync_upload` tests PASS (session+sets creation, top-set, idempotency, cross-user rejection stays 2xx, PR flags). Other packages still green.

- [ ] **Step 4: Commit**

```bash
git add server/internal/api/sync_upload.go server/internal/api/sync_upload_test.go server/internal/api/uploadhelpers_test.go
git commit -m "feat(server): /sync/upload batch handler with top-set and PR computation"
```

---

### Task 6: Wire the handler into the router and main

**Files:**
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Add `Upload` to `Deps` and register the route in `router.go`**

In the `Deps` struct add a field:

```go
	Upload      *UploadHandler
```

Inside the `RequireAuth` group in `NewRouter` (where `/auth/powersync-token` is registered), add — guarded so the health-only tests (nil `Upload`) still work:

```go
				if d.Upload != nil {
					pr.Post("/sync/upload", d.Upload.Upload)
				}
```

So that group becomes:

```go
			r.Group(func(pr chi.Router) {
				pr.Use(RequireAuth(d.Verifier, d.APIAudience))
				pr.Post("/auth/powersync-token", d.Auth.PowerSyncToken)
				if d.Upload != nil {
					pr.Post("/sync/upload", d.Upload.Upload)
				}
			})
```

- [ ] **Step 2: Construct the handler in `main.go`** and pass it into `Deps`

After `pool` is created and before `srv`, add:

```go
	uploadHandler := api.NewUploadHandler(pool)
```

Add to the `api.Deps{…}` literal passed to `NewRouter`:

```go
			Upload:      uploadHandler,
```

- [ ] **Step 3: Build + full test**

Run: `make -C server build && make -C server test`
Expected: binary builds; all packages pass (the health-only router tests still pass because `Upload` is nil there).

- [ ] **Step 4: Commit**

```bash
git add server/internal/api/router.go server/cmd/server/main.go
git commit -m "feat(server): register /sync/upload behind auth"
```

---

### Task 7: OpenAPI 3.1 — document POST /sync/upload

**Files:**
- Modify: `api/openapi.yaml`

- [ ] **Step 1: Add the `/sync/upload` path** to `api/openapi.yaml` (under `paths:`), plus the schemas under `components/schemas`:

```yaml
  /sync/upload:
    post:
      summary: Apply a batch of PowerSync client write operations
      description: >
        Target of the PowerSync client uploadData connector. Applies the whole
        batch in one transaction. Per the PowerSync contract this endpoint never
        returns 4xx for validation/ownership errors (that would permanently block
        the client's upload queue); such ops are logged and skipped and the
        response is still 200. 5xx indicates a transient error the client should
        retry.
      operationId: postSyncUpload
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/UploadRequest"
      responses:
        "200":
          description: Batch processed (applied count may be less than submitted if ops were skipped)
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/UploadResult"
        "401":
          description: Authentication required
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
        "503":
          description: Transient error; retry the same batch
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
```

And under `components: schemas:`:

```yaml
    UploadRequest:
      type: object
      properties:
        batch:
          type: array
          items:
            $ref: "#/components/schemas/CrudOp"
      required: [batch]
    CrudOp:
      type: object
      properties:
        op:
          type: string
          enum: [PUT, PATCH, DELETE]
        table:
          type: string
          enum: [exercises, sessions, sets, bodyweight_logs]
        id:
          type: string
        data:
          type: object
          additionalProperties: true
      required: [op, table, id]
    UploadResult:
      type: object
      properties:
        applied:
          type: integer
      required: [applied]
```

- [ ] **Step 2: Lint**

Run from repo root:

```bash
make -C server lint-spec
```

Expected: vacuum passes with no error-severity findings (exit 0).

- [ ] **Step 3: Commit**

```bash
git add api/openapi.yaml
git commit -m "docs(api): document POST /sync/upload"
```

---

### Task 8: End-to-end validation

**Files:** none — verification only, no commit.

- [ ] **Step 1: Ensure the stack is up and migrated**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
sleep 5
make -C server migrate-up
```

- [ ] **Step 2: Log in, upload a session + sets, verify in Postgres**

Run from repo root (dev user `me@example.com`/`devpassword`):

```bash
set -a && . infra/.env && set +a
ACCESS=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' -d '{"email":"me@example.com","password":"devpassword"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
EX=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT id FROM exercises WHERE slug='hack-squat'")
SID=$(python3 -c "import uuid;print(uuid.uuid4())")
S1=$(python3 -c "import uuid;print(uuid.uuid4())"); S2=$(python3 -c "import uuid;print(uuid.uuid4())"); S3=$(python3 -c "import uuid;print(uuid.uuid4())")
curl -sS -o /dev/null -w "upload=%{http_code}\n" -X POST http://localhost:8080/sync/upload \
  -H "Authorization: Bearer $ACCESS" -H 'Content-Type: application/json' \
  -d "{\"batch\":[
    {\"op\":\"PUT\",\"table\":\"sessions\",\"id\":\"$SID\",\"data\":{\"id\":\"$SID\",\"date\":\"2026-05-29\",\"split_label\":\"Lower A\"}},
    {\"op\":\"PUT\",\"table\":\"sets\",\"id\":\"$S1\",\"data\":{\"id\":\"$S1\",\"session_id\":\"$SID\",\"exercise_id\":\"$EX\",\"set_number\":1,\"weight_kg\":\"60.00\",\"reps\":8,\"is_warmup\":true}},
    {\"op\":\"PUT\",\"table\":\"sets\",\"id\":\"$S2\",\"data\":{\"id\":\"$S2\",\"session_id\":\"$SID\",\"exercise_id\":\"$EX\",\"set_number\":2,\"weight_kg\":\"140.00\",\"reps\":7,\"is_warmup\":false}},
    {\"op\":\"PUT\",\"table\":\"sets\",\"id\":\"$S3\",\"data\":{\"id\":\"$S3\",\"session_id\":\"$SID\",\"exercise_id\":\"$EX\",\"set_number\":3,\"weight_kg\":\"120.00\",\"reps\":10,\"is_warmup\":false}}
  ]}"
echo "--- rows + flags ---"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT set_number, weight_kg, is_warmup, is_top_set, is_pr FROM sets WHERE session_id='$SID' ORDER BY set_number;"
```

Expected: `upload=200`; the rows show set 2 (140kg) `is_top_set=t`, sets 1+3 `is_top_set=f`, the warmup never flagged; `is_pr=t` on the 140kg top set (first-ever for the dev user on this exercise, assuming a fresh exercise) — if the dev user already has heavier history for hack-squat, `is_pr` may be `f`, which is correct.

- [ ] **Step 3: Confirm the rows sync down via PowerSync**

Run from repo root (mint a PowerSync token and stream — the new session's sets should appear in the `by_user` bucket):

```bash
PSTOKEN=$(curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -sS -o /tmp/wt-5a-stream.out --max-time 8 -X POST http://localhost:8090/sync/stream \
  -H "Authorization: Token $PSTOKEN" -H 'Content-Type: application/json' -d '{"raw_data": true, "buckets": []}' || true
grep -q '"object_type":"sets"' /tmp/wt-5a-stream.out && echo "sets sync down OK" || echo "(sets not in initial window)"
grep -q "140" /tmp/wt-5a-stream.out && echo "uploaded set present in sync OK"
```

Expected: `sets sync down OK` and `uploaded set present in sync OK` — proving the full write→Postgres→replicate-down round-trip works from the backend side.

- [ ] **Step 4: Confirm git state**

Run from repo root:

```bash
git status
git log --oneline main..HEAD
```

Expected: clean tree; the log shows the commits from Tasks 1–7 (migrations, sync-rules, the handler, router wiring, OpenAPI).

- [ ] **Step 5: No commit (verification only)**

Plan 5a is complete. The backend can ingest PowerSync client write batches (sessions/sets/bodyweight + custom exercises), compute top-set/PR, and replicate everything back per user. Next: the **day-templates** backend plan (`day_templates` + `day_template_items`, seeded from the README split, custom-day support), then **Flutter foundations** (the `uploadData` connector targeting this endpoint + the local schema + the bidirectional round-trip in the real client), then the **UX design** brainstorm and the real screens.
