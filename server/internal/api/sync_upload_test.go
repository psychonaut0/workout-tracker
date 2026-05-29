package api

import (
	"context"
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

// Regression: a PATCH carrying only the changed column (PowerSync sends partial
// opData) must update that column WITHOUT clobbering is_warmup or being dropped
// for missing session_id/exercise_id.
func TestUpload_PatchPreservesWarmupAndUpdatesReps(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	var exID string
	_ = pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID)

	sid := "99999999-9999-9999-9999-999999999999"
	setID := "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid`, sid) })

	// Create a session + a WARMUP set.
	postUpload(t, h, user, `{"batch":[
	  {"op":"PUT","table":"sessions","id":"`+sid+`","data":{"id":"`+sid+`","date":"2026-05-29"}},
	  {"op":"PUT","table":"sets","id":"`+setID+`","data":{"id":"`+setID+`","session_id":"`+sid+`","exercise_id":"`+exID+`","set_number":1,"weight_kg":"40.00","reps":10,"is_warmup":true}}
	]}`)

	// PATCH only reps (no session_id/exercise_id/is_warmup) — the typical edit shape.
	rec := postUpload(t, h, user, `{"batch":[{"op":"PATCH","table":"sets","id":"`+setID+`","data":{"id":"`+setID+`","reps":12}}]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("patch status: got %d %s", rec.Code, rec.Body.String())
	}

	var reps int
	var isWarmup bool
	if err := pool.QueryRow(ctx, `SELECT reps, is_warmup FROM sets WHERE id=$1::uuid`, setID).Scan(&reps, &isWarmup); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if reps != 12 {
		t.Errorf("reps: got %d, want 12 (the PATCH must apply)", reps)
	}
	if !isWarmup {
		t.Errorf("is_warmup: got false, want true (PATCH must NOT clobber the omitted flag)")
	}
}

func TestUpload_CustomDayTemplateAndItems(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	var exID string
	_ = pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID)

	tmpl := "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	item := "cccccccc-cccc-cccc-cccc-cccccccccccc"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM day_templates WHERE id=$1::uuid`, tmpl) })

	rec := postUpload(t, h, user, `{"batch":[
	  {"op":"PUT","table":"day_templates","id":"`+tmpl+`","data":{"id":"`+tmpl+`","name":"My Gym Day","position":1}},
	  {"op":"PUT","table":"day_template_items","id":"`+item+`","data":{"id":"`+item+`","day_template_id":"`+tmpl+`","exercise_id":"`+exID+`","position":1,"target_working_sets":4,"target_rep_low":6,"target_rep_high":8}}
	]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d %s", rec.Code, rec.Body.String())
	}

	// Template + item exist, stamped to the user, is_template=false.
	var tplOwner string
	var tplIsTemplate bool
	if err := pool.QueryRow(ctx, `SELECT created_by::text, is_template FROM day_templates WHERE id=$1::uuid`, tmpl).Scan(&tplOwner, &tplIsTemplate); err != nil {
		t.Fatalf("template: %v", err)
	}
	if tplOwner != user || tplIsTemplate {
		t.Errorf("template owner/is_template: got %s/%v", tplOwner, tplIsTemplate)
	}
	var itemOwner string
	var working int
	if err := pool.QueryRow(ctx, `SELECT created_by::text, target_working_sets FROM day_template_items WHERE id=$1::uuid`, item).Scan(&itemOwner, &working); err != nil {
		t.Fatalf("item: %v", err)
	}
	if itemOwner != user || working != 4 {
		t.Errorf("item owner/working: got %s/%d", itemOwner, working)
	}
}

func TestUpload_ItemRejectedForUnownedTemplate(t *testing.T) {
	pool := uploadTestPool(t)
	owner := seedUploadUser(t, pool)
	attacker := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	var exID string
	_ = pool.QueryRow(ctx, `SELECT id::text FROM exercises WHERE is_template=true LIMIT 1`).Scan(&exID)

	tmpl := "dddddddd-dddd-dddd-dddd-dddddddddddd"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM day_templates WHERE id=$1::uuid`, tmpl) })
	postUpload(t, h, owner, `{"batch":[{"op":"PUT","table":"day_templates","id":"`+tmpl+`","data":{"id":"`+tmpl+`","name":"Owner Day","position":1}}]}`)

	// attacker adds an item to the owner's template — must be skipped, still 2xx
	rec := postUpload(t, h, attacker, `{"batch":[{"op":"PUT","table":"day_template_items","id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","data":{"id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","day_template_id":"`+tmpl+`","exercise_id":"`+exID+`","position":1}}]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("must stay 2xx, got %d", rec.Code)
	}
	var n int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM day_template_items WHERE id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'`).Scan(&n)
	if n != 0 {
		t.Errorf("item must NOT be written, got %d", n)
	}
}

func TestUpload_SessionLinksDayTemplate(t *testing.T) {
	pool := uploadTestPool(t)
	user := seedUploadUser(t, pool)
	h := NewUploadHandler(pool)
	ctx := context.Background()
	// Use a seeded shared template (any user may reference it from a session).
	var tmpl string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM day_templates WHERE slug='upper-a'`).Scan(&tmpl); err != nil {
		t.Skipf("day_templates seed not applied — run migrations first: %v", err)
	}

	sid := "ffffffff-ffff-ffff-ffff-ffffffffffff"
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid`, sid) })

	rec := postUpload(t, h, user, `{"batch":[{"op":"PUT","table":"sessions","id":"`+sid+`","data":{"id":"`+sid+`","date":"2026-05-29","split_label":"Upper A","day_template_id":"`+tmpl+`"}}]}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var linked string
	if err := pool.QueryRow(ctx, `SELECT day_template_id::text FROM sessions WHERE id=$1::uuid`, sid).Scan(&linked); err != nil {
		t.Fatalf("read session: %v", err)
	}
	if linked != tmpl {
		t.Errorf("day_template_id: got %s, want %s", linked, tmpl)
	}
}
