# Plan 5a-templates — Day Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable **day templates** — the seeded README split days (Upper A / Lower A / Upper B / Lower B) plus user-created custom days for any gym — each carrying an ordered list of exercises with target warmup/working sets, rep range, and RIR range; link a logged session to the template it came from.

**Architecture:** Two new tables, `day_templates` and `day_template_items`, mirror the `exercises` shared-vs-custom pattern (`is_template` + `created_by`). Shared seeded days replicate to everyone via the `templates` bucket; user-created days replicate to their owner via the `by_user` bucket. Because PowerSync classic sync rules can't JOIN, `day_template_items` carries the parent's `is_template`/`created_by` denormalized (stamped server-side on write) so it filters as a single-table query. `sessions` gains a nullable `day_template_id` FK. Writes flow through the existing `POST /sync/upload` endpoint — this plan extends its table whitelist with `day_templates`/`day_template_items` and teaches `applySession` the new column. No new HTTP route.

**Tech Stack:** Go 1.26 (the existing `internal/api` upload handler), pgx/v5, goose migrations, PowerSync 1.21 (publication + sync rules), OpenAPI 3.1.

**Spec sections covered:** Resolves the spec's "model the split structure vs free-form" open question (now: structured day templates layered on the flat catalog). Delivers the user's day-template requirement (seeded split + custom days per gym) with the full per-exercise prescription and a session→template link.

---

## Decisions locked (your answers + the proven 5a pattern)

| Topic | Decision |
| ----- | -------- |
| Prescription detail | **Full** — each `day_template_items` row stores `position`, `exercise_id`, `target_warmup_sets`, `target_working_sets`, `target_rep_low`/`target_rep_high`, `target_rir_low`/`target_rir_high` (all nullable except position). |
| Session link | **`sessions.day_template_id`** nullable FK → `day_templates(id)`. Ad-hoc sessions leave it null; `split_label` (free-text) stays. |
| Shared vs custom | Mirror `exercises`: `is_template=TRUE, created_by=NULL` for seeded days; `is_template=FALSE, created_by=<user>` for custom. |
| Items sync filter | `day_template_items` carries **denormalized** `is_template`/`created_by` (stamped from the parent template on write) — PowerSync can't JOIN. |
| Writes | Through the existing `POST /sync/upload`; add `day_templates`/`day_template_items` to the handler whitelist + `applySession` learns `day_template_id`. Server stamps `created_by`/`is_template`; client values ignored. |
| Seeding | A goose migration seeds the 4 README split days + their items, idempotent (`ON CONFLICT (slug)` / `WHERE NOT EXISTS`). |
| Grip rotation / day-of-week | **Not modeled** (the README's weekly grip alternation and Mon/Tue/Thu/Fri schedule are coaching notes — YAGNI). `day_templates.position` orders the rotation. |

**Deferred:** the Flutter UI for browsing/applying/building templates (UX-design phase); "compare actual vs planned" analytics (the `day_template_id` link enables it later); cloning a shared template into a custom one (a client-side convenience over the existing writes).

## Conventions

Repo-root commands (`make -C server …`); Conventional Commits subject-only; goose 5-digit migrations (next is 00010); no "Plan N" literals in committed files; OpenAPI at `api/openapi.yaml` (vacuum-linted). Dev Postgres on host 5433.

## File structure

```
server/db/migrations/00010_create_day_templates.sql            # NEW
server/db/migrations/00011_create_day_template_items.sql       # NEW (denormalized is_template/created_by)
server/db/migrations/00012_session_day_template_fk.sql         # NEW (ALTER sessions ADD day_template_id)
server/db/migrations/00013_powersync_publish_day_templates.sql # NEW (ALTER PUBLICATION)
server/db/migrations/00014_seed_day_templates.sql              # NEW (README 4 days + items)
powersync/sync-rules.yaml                                      # MODIFY: sync day_templates + items
server/internal/api/sync_upload.go                             # MODIFY: applyDayTemplate/applyDayTemplateItem + applySession day_template_id
server/internal/api/sync_upload_test.go                        # MODIFY: tests for the new tables
api/openapi.yaml                                               # MODIFY: extend CrudOp.table enum
```

---

### Task 1: Migrations — day_templates, items, session FK, publication, seed

**Files:**
- Create: `server/db/migrations/00010_create_day_templates.sql`
- Create: `server/db/migrations/00011_create_day_template_items.sql`
- Create: `server/db/migrations/00012_session_day_template_fk.sql`
- Create: `server/db/migrations/00013_powersync_publish_day_templates.sql`
- Create: `server/db/migrations/00014_seed_day_templates.sql`

- [ ] **Step 1: Write `00010_create_day_templates.sql`**

```sql
-- +goose Up
-- A reusable workout day (e.g. "Upper A"). Shared seeded days have
-- is_template=TRUE, created_by=NULL; user-created custom days have
-- is_template=FALSE, created_by=<user>. slug is set only for seeded days
-- (idempotent seeding); custom days leave it NULL (multiple NULLs allowed).
CREATE TABLE day_templates (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         TEXT UNIQUE,
    name         TEXT NOT NULL,
    notes        TEXT,
    position     INTEGER NOT NULL DEFAULT 0,
    is_template  BOOLEAN NOT NULL DEFAULT FALSE,
    created_by   UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX day_templates_created_by_idx ON day_templates (created_by);

-- +goose Down
DROP TABLE day_templates;
```

- [ ] **Step 2: Write `00011_create_day_template_items.sql`**

```sql
-- +goose Up
-- One planned exercise within a day template, with its target prescription.
-- is_template/created_by are DENORMALIZED from the parent day_templates row and
-- stamped server-side on write: PowerSync classic sync rules cannot JOIN, so the
-- per-user / templates buckets filter items directly on these columns. Target
-- columns are nullable (a custom day may omit them).
CREATE TABLE day_template_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    day_template_id     UUID NOT NULL REFERENCES day_templates(id) ON DELETE CASCADE,
    exercise_id         UUID NOT NULL REFERENCES exercises(id),
    position            INTEGER NOT NULL,
    target_warmup_sets  INTEGER,
    target_working_sets INTEGER,
    target_rep_low      INTEGER,
    target_rep_high     INTEGER,
    target_rir_low      INTEGER,
    target_rir_high     INTEGER,
    is_template         BOOLEAN NOT NULL DEFAULT FALSE,
    created_by          UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX day_template_items_template_idx ON day_template_items (day_template_id, position);
CREATE INDEX day_template_items_created_by_idx ON day_template_items (created_by);

-- +goose Down
DROP TABLE day_template_items;
```

- [ ] **Step 3: Write `00012_session_day_template_fk.sql`**

```sql
-- +goose Up
-- Optionally record which day template a session was started from. Nullable:
-- ad-hoc sessions leave it NULL. ON DELETE SET NULL so deleting a template does
-- not delete the historical sessions that used it.
ALTER TABLE sessions ADD COLUMN day_template_id UUID REFERENCES day_templates(id) ON DELETE SET NULL;

-- +goose Down
ALTER TABLE sessions DROP COLUMN day_template_id;
```

- [ ] **Step 4: Write `00013_powersync_publish_day_templates.sql`**

```sql
-- +goose Up
-- Publish the new tables so their changes enter the replication stream. sessions
-- is already published (00009); adding a column to it needs no re-publish.
ALTER PUBLICATION powersync ADD TABLE day_templates;
ALTER PUBLICATION powersync ADD TABLE day_template_items;

-- +goose Down
ALTER PUBLICATION powersync DROP TABLE day_template_items;
ALTER PUBLICATION powersync DROP TABLE day_templates;
```

- [ ] **Step 5: Write `00014_seed_day_templates.sql`** (the README split as shared templates)

```sql
-- +goose Up
-- Seed the 4 README split days as shared templates (is_template=TRUE,
-- created_by=NULL). Idempotent via ON CONFLICT (slug) DO NOTHING. RIR ranges are
-- stored low..high (e.g. README "1-0" -> rir_low 0, rir_high 1).
INSERT INTO day_templates (slug, name, notes, position, is_template, created_by) VALUES
    ('upper-a', 'Upper A', 'Push focus',      1, TRUE, NULL),
    ('lower-a', 'Lower A', 'Quad + calf',     2, TRUE, NULL),
    ('upper-b', 'Upper B', 'Pull focus',      3, TRUE, NULL),
    ('lower-b', 'Lower B', 'Posterior chain', 4, TRUE, NULL)
ON CONFLICT (slug) DO NOTHING;

-- Items: resolve day_template + exercise by slug. Idempotent via NOT EXISTS.
INSERT INTO day_template_items
    (day_template_id, exercise_id, position, target_warmup_sets, target_working_sets,
     target_rep_low, target_rep_high, target_rir_low, target_rir_high, is_template, created_by)
SELECT dt.id, ex.id, v.position, v.warm, v.work, v.rlow, v.rhigh, v.rirlow, v.rirhigh, TRUE, NULL
FROM (VALUES
    -- Upper A (push)
    ('upper-a','incline-bench-press',      1, 2, 4,  6,  8, 0, 1),
    ('upper-a','chest-press',              2, 0, 3,  8, 10, 1, 1),
    ('upper-a','seated-db-shoulder-press', 3, 0, 3,  8, 10, 1, 1),
    ('upper-a','db-lateral-raise',         4, 0, 3, 10, 12, 1, 1),
    ('upper-a','reverse-pec-deck',         5, 0, 3, 12, 15, 1, 1),
    ('upper-a','rope-triceps-pushdown',    6, 0, 3, 10, 12, 1, 1),
    ('upper-a','overhead-rope-extension',  7, 0, 3, 10, 12, 1, 1),
    -- Lower A (quad + calf)
    ('lower-a','hack-squat',               1, 2, 4,  6,  8, 0, 1),
    ('lower-a','leg-press',                2, 0, 3, 10, 12, 1, 1),
    ('lower-a','leg-extension',            3, 0, 3, 10, 12, 1, 1),
    ('lower-a','seated-leg-curl',          4, 0, 3,  8, 10, 1, 1),
    ('lower-a','standing-calf-raise',      5, 0, 4, 10, 12, 0, 1),
    -- Upper B (pull)
    ('upper-b','lat-pulldown',             1, 2, 4,  6,  8, 0, 1),
    ('upper-b','row',                      2, 0, 4,  8, 10, 1, 1),
    ('upper-b','iliac-pulldown',           3, 0, 3, 10, 12, 1, 1),
    ('upper-b','cable-row',                4, 0, 3, 10, 12, 1, 1),
    ('upper-b','preacher-curl',            5, 0, 3,  8, 10, 1, 1),
    ('upper-b','cable-hammer-curl',        6, 0, 3, 10, 12, 1, 1),
    ('upper-b','cable-curl',               7, 0, 3, 12, 15, 0, 1),
    -- Lower B (posterior chain)
    ('lower-b','romanian-deadlift',        1, 2, 4,  6,  8, 1, 1),
    ('lower-b','hack-squat-depth-focus',   2, 0, 3, 10, 12, 1, 1),
    ('lower-b','lying-leg-curl',           3, 0, 4,  8, 10, 1, 1),
    ('lower-b','unilateral-leg-extension', 4, 0, 3, 12, 15, 0, 1),
    ('lower-b','seated-calf-raise',        5, 0, 4, 12, 15, 0, 1)
) AS v(dt_slug, ex_slug, position, warm, work, rlow, rhigh, rirlow, rirhigh)
JOIN day_templates dt ON dt.slug = v.dt_slug
JOIN exercises ex ON ex.slug = v.ex_slug
WHERE NOT EXISTS (
    SELECT 1 FROM day_template_items i WHERE i.day_template_id = dt.id AND i.exercise_id = ex.id
);

-- +goose Down
DELETE FROM day_template_items WHERE is_template = TRUE AND created_by IS NULL;
DELETE FROM day_templates WHERE slug IN ('upper-a','lower-a','upper-b','lower-b')
    AND is_template = TRUE AND created_by IS NULL;
```

- [ ] **Step 6: Apply and verify**

Run from repo root (Postgres up on 5433):

```bash
make -C server migrate-up
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d day_template_items' -c '\d sessions'
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT tablename FROM pg_publication_tables WHERE pubname='powersync' ORDER BY tablename;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT dt.slug, count(i.*) FROM day_templates dt LEFT JOIN day_template_items i ON i.day_template_id=dt.id WHERE dt.is_template GROUP BY dt.slug ORDER BY dt.slug;"
```

Expected: `\d day_template_items` shows the target columns + `is_template`/`created_by`; `\d sessions` shows the new `day_template_id`; publication now also lists `day_template_items, day_templates`; the per-day counts are `lower-a|5, lower-b|5, upper-a|7, upper-b|7`.

- [ ] **Step 7: Verify rollback then re-apply**

```bash
make -C server migrate-down   # rolls back 00014 (seed delete)
make -C server migrate-up
make -C server migrate-status
```

Expected: down/up clean; status shows 00001–00014 all `Applied`.

- [ ] **Step 8: Commit**

```bash
git add server/db/migrations/0001{0,1,2,3,4}_*.sql
git commit -m "feat(server): day_templates and day_template_items with README seed"
```

---

### Task 2: Sync rules for day templates

**Files:**
- Modify: `powersync/sync-rules.yaml`

- [ ] **Step 1: Replace `powersync/sync-rules.yaml`** with EXACTLY:

```yaml
# PowerSync sync rules. Scoped to the authenticated user (request.user_id() =
# the JWT sub): their own exercises, sessions, sets, bodyweight logs, and custom
# day templates/items — plus all shared template exercises and day templates via
# the global `templates` bucket. Each data query is a single-table SELECT
# (PowerSync classic sync rules do not support JOINs); child tables (sets,
# day_template_items) are filtered on their denormalized owner columns.
bucket_definitions:
  by_user:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM exercises WHERE created_by = bucket.user_id
      - SELECT * FROM sessions WHERE user_id = bucket.user_id
      - SELECT * FROM sets WHERE user_id = bucket.user_id
      - SELECT * FROM bodyweight_logs WHERE user_id = bucket.user_id
      - SELECT * FROM day_templates WHERE created_by = bucket.user_id
      - SELECT * FROM day_template_items WHERE created_by = bucket.user_id
  templates:
    data:
      - SELECT * FROM exercises WHERE is_template = true
      - SELECT * FROM day_templates WHERE is_template = true
      - SELECT * FROM day_template_items WHERE is_template = true
```

- [ ] **Step 2: Validate YAML + restart PowerSync to reload the rules**

Run from repo root:

```bash
python3 -c "import yaml; d=yaml.safe_load(open('powersync/sync-rules.yaml')); assert len(d['bucket_definitions']['by_user']['data'])==6 and len(d['bucket_definitions']['templates']['data'])==3; print('yaml OK')"
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env restart powersync
for i in $(seq 1 24); do hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1 2>/dev/null || echo none); [ "$hc" = "healthy" ] && break; sleep 5; done
echo "powersync: $(docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1)"
```

Expected: `yaml OK`; powersync returns to `healthy`.

- [ ] **Step 3: Confirm the rules compiled + the new tables replicate**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env logs powersync --since 90s 2>&1 \
  | grep -iE 'Replicating "public"\.\"(day_templates|day_template_items)\"|fatal|Failed to update sync config' | tail -20
```

Expected: lines showing `day_templates` and `day_template_items` replicating; NO `fatal` / `Failed to update sync config`. (A sync-rules error names the offending query — fix and restart.)

- [ ] **Step 4: Commit**

```bash
git add powersync/sync-rules.yaml
git commit -m "feat(powersync): sync day templates (shared + per-user)"
```

---

### Task 3: Upload handler — day-template writes + session link (TDD)

**Files:**
- Modify: `server/internal/api/sync_upload.go`
- Modify: `server/internal/api/sync_upload_test.go`

- [ ] **Step 1: Add the failing tests** — append to `server/internal/api/sync_upload_test.go`:

```go

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
	_ = pool.QueryRow(ctx, `SELECT id::text FROM day_templates WHERE slug='upper-a'`).Scan(&tmpl)

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make -C server test`
Expected: the three new tests FAIL — `day_templates`/`day_template_items` are unknown tables (the handler skips them → the template/item are never written → assertions fail), and `applySession` ignores `day_template_id` (the link assertion fails).

- [ ] **Step 3: Add the new table handlers to `sync_upload.go`** — append these two functions:

```go

// applyDayTemplate handles user-created CUSTOM day templates only. created_by is
// stamped from the token and is_template is forced false; seeded shared templates
// (created_by NULL) can never be written/edited/deleted by a client. slug is not
// client-settable (NULL for custom days).
func applyDayTemplate(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "PUT":
		name, _ := str(op.Data, "name")
		notes, _ := str(op.Data, "notes")
		pos, _ := str(op.Data, "position")
		_, err := tx.Exec(ctx,
			`INSERT INTO day_templates (id, name, notes, position, is_template, created_by)
			 VALUES ($1::uuid, $2, NULLIF($3,''), COALESCE(NULLIF($4,'')::numeric::int, 0), false, $5::uuid)
			 ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, notes=EXCLUDED.notes, position=EXCLUDED.position
			 WHERE day_templates.created_by = $5::uuid`,
			op.ID, name, notes, pos, userID)
		return err
	case "PATCH":
		name, _ := str(op.Data, "name")
		notes, _ := str(op.Data, "notes")
		pos, _ := str(op.Data, "position")
		_, err := tx.Exec(ctx,
			`UPDATE day_templates SET
			   name = COALESCE(NULLIF($3,''), name),
			   notes = COALESCE(NULLIF($4,''), notes),
			   position = COALESCE(NULLIF($5,'')::numeric::int, position)
			 WHERE id=$1::uuid AND created_by=$2::uuid`,
			op.ID, userID, name, notes, pos)
		return err
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM day_templates WHERE id=$1::uuid AND created_by=$2::uuid`, op.ID, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}

// applyDayTemplateItem writes an item into a day template the user OWNS (verified
// against the parent's created_by), stamping created_by + is_template=false from
// the parent. DELETE/PATCH operate by id constrained to the owner.
func applyDayTemplateItem(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM day_template_items WHERE id=$1::uuid AND created_by=$2::uuid`, op.ID, userID)
		return err
	case "PATCH":
		pos, _ := str(op.Data, "position")
		warm, _ := str(op.Data, "target_warmup_sets")
		work, _ := str(op.Data, "target_working_sets")
		rlow, _ := str(op.Data, "target_rep_low")
		rhigh, _ := str(op.Data, "target_rep_high")
		rirlow, _ := str(op.Data, "target_rir_low")
		rirhigh, _ := str(op.Data, "target_rir_high")
		_, err := tx.Exec(ctx,
			`UPDATE day_template_items SET
			   position            = COALESCE(NULLIF($3,'')::numeric::int, position),
			   target_warmup_sets  = COALESCE(NULLIF($4,'')::numeric::int, target_warmup_sets),
			   target_working_sets = COALESCE(NULLIF($5,'')::numeric::int, target_working_sets),
			   target_rep_low      = COALESCE(NULLIF($6,'')::numeric::int, target_rep_low),
			   target_rep_high     = COALESCE(NULLIF($7,'')::numeric::int, target_rep_high),
			   target_rir_low      = COALESCE(NULLIF($8,'')::numeric::int, target_rir_low),
			   target_rir_high     = COALESCE(NULLIF($9,'')::numeric::int, target_rir_high)
			 WHERE id=$1::uuid AND created_by=$2::uuid`,
			op.ID, userID, pos, warm, work, rlow, rhigh, rirlow, rirhigh)
		return err
	case "PUT":
		tmplID, _ := str(op.Data, "day_template_id")
		exID, _ := str(op.Data, "exercise_id")
		if tmplID == "" || exID == "" {
			return fmt.Errorf("item PUT missing day_template_id/exercise_id")
		}
		// The parent template must be owned by this user (created_by = userID).
		var owner *string
		err := tx.QueryRow(ctx, `SELECT created_by::text FROM day_templates WHERE id=$1::uuid`, tmplID).Scan(&owner)
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("item references unknown template %s", tmplID)
		}
		if err != nil {
			return err
		}
		if owner == nil || *owner != userID {
			return fmt.Errorf("item references template not owned by user")
		}
		pos, _ := str(op.Data, "position")
		warm, _ := str(op.Data, "target_warmup_sets")
		work, _ := str(op.Data, "target_working_sets")
		rlow, _ := str(op.Data, "target_rep_low")
		rhigh, _ := str(op.Data, "target_rep_high")
		rirlow, _ := str(op.Data, "target_rir_low")
		rirhigh, _ := str(op.Data, "target_rir_high")
		_, err = tx.Exec(ctx,
			`INSERT INTO day_template_items
			   (id, day_template_id, exercise_id, position, target_warmup_sets, target_working_sets,
			    target_rep_low, target_rep_high, target_rir_low, target_rir_high, is_template, created_by)
			 VALUES ($1::uuid, $2::uuid, $3::uuid, COALESCE(NULLIF($4,'')::numeric::int,0),
			    NULLIF($5,'')::numeric::int, NULLIF($6,'')::numeric::int,
			    NULLIF($7,'')::numeric::int, NULLIF($8,'')::numeric::int,
			    NULLIF($9,'')::numeric::int, NULLIF($10,'')::numeric::int, false, $11::uuid)
			 ON CONFLICT (id) DO UPDATE SET
			   exercise_id=EXCLUDED.exercise_id, position=EXCLUDED.position,
			   target_warmup_sets=EXCLUDED.target_warmup_sets, target_working_sets=EXCLUDED.target_working_sets,
			   target_rep_low=EXCLUDED.target_rep_low, target_rep_high=EXCLUDED.target_rep_high,
			   target_rir_low=EXCLUDED.target_rir_low, target_rir_high=EXCLUDED.target_rir_high
			 WHERE day_template_items.created_by = $11::uuid`,
			op.ID, tmplID, exID, pos, warm, work, rlow, rhigh, rirlow, rirhigh, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}
```

- [ ] **Step 4: Register the new tables in `applyOp`** — in the `switch op.tableName()` add two cases (alongside `sessions`/`sets`/etc.):

```go
	case "day_templates":
		return applyDayTemplate(ctx, tx, userID, op)
	case "day_template_items":
		return applyDayTemplateItem(ctx, tx, userID, op)
```

- [ ] **Step 5: Teach `applySession` the `day_template_id` column** — replace the `applySession` function's PUT and PATCH SQL to include `day_template_id` (a nullable FK; client may send it or omit it). The full replacement `applySession`:

```go
func applySession(ctx context.Context, tx pgx.Tx, userID string, op crudOp) error {
	switch op.Op {
	case "PUT":
		date, _ := str(op.Data, "date")
		label, _ := str(op.Data, "split_label")
		notes, _ := str(op.Data, "notes")
		tmpl, _ := str(op.Data, "day_template_id")
		_, err := tx.Exec(ctx,
			`INSERT INTO sessions (id, user_id, date, split_label, notes, day_template_id)
			 VALUES ($1::uuid, $2::uuid, $3::date, NULLIF($4,''), NULLIF($5,''), NULLIF($6,'')::uuid)
			 ON CONFLICT (id) DO UPDATE SET date=EXCLUDED.date, split_label=EXCLUDED.split_label,
			   notes=EXCLUDED.notes, day_template_id=EXCLUDED.day_template_id
			 WHERE sessions.user_id = $2::uuid`,
			op.ID, userID, date, label, notes, tmpl)
		return err
	case "PATCH":
		date, _ := str(op.Data, "date")
		label, _ := str(op.Data, "split_label")
		notes, _ := str(op.Data, "notes")
		tmpl, _ := str(op.Data, "day_template_id")
		_, err := tx.Exec(ctx,
			`UPDATE sessions SET
			   date = COALESCE(NULLIF($3,'')::date, date),
			   split_label = COALESCE(NULLIF($4,''), split_label),
			   notes = COALESCE(NULLIF($5,''), notes),
			   day_template_id = COALESCE(NULLIF($6,'')::uuid, day_template_id)
			 WHERE id = $1::uuid AND user_id = $2::uuid`,
			op.ID, userID, date, label, notes, tmpl)
		return err
	case "DELETE":
		_, err := tx.Exec(ctx, `DELETE FROM sessions WHERE id=$1::uuid AND user_id=$2::uuid`, op.ID, userID)
		return err
	default:
		return fmt.Errorf("unknown op %q", op.Op)
	}
}
```

(Replace the existing `applySession` from Plan 5a in place; the only changes are the added `day_template_id` column in PUT and PATCH.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `make -C server test`
Expected: the three new tests PASS (custom template + items stamped to the user with is_template=false; cross-user item rejected but 2xx; session links the shared template). All prior tests still green.

- [ ] **Step 7: Commit**

```bash
git add server/internal/api/sync_upload.go server/internal/api/sync_upload_test.go
git commit -m "feat(server): day-template writes and session day_template_id link"
```

---

### Task 4: OpenAPI — extend the upload table enum

**Files:**
- Modify: `api/openapi.yaml`

- [ ] **Step 1: Extend the `CrudOp.table` enum** in `api/openapi.yaml` to include the new tables. Change the enum from:

```yaml
        table:
          type: string
          enum: [exercises, sessions, sets, bodyweight_logs]
```

to:

```yaml
        table:
          type: string
          enum: [exercises, sessions, sets, bodyweight_logs, day_templates, day_template_items]
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
git commit -m "docs(api): allow day_templates/day_template_items in /sync/upload"
```

---

### Task 5: End-to-end validation

**Files:** none — verification only, no commit.

- [ ] **Step 1: Rebuild the server container with the new handler + bring the stack up**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d --build server
for i in $(seq 1 20); do hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-server-1 2>/dev/null || echo none); [ "$hc" = "healthy" ] && break; sleep 2; done
echo "server: $(docker inspect --format='{{.State.Health.Status}}' workout-tracker-server-1)"
make -C server migrate-up
```

Expected: server rebuilds and is `healthy`; migrations up-to-date.

- [ ] **Step 2: Confirm the seeded split synced + create a custom day, then a linked session**

Run from repo root:

```bash
set -a && . infra/.env && set +a
ACCESS=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' -d '{"email":"me@example.com","password":"devpassword"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
UA=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT id FROM day_templates WHERE slug='upper-a'")
EX=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT id FROM exercises WHERE slug='chest-press'")
DT=$(python3 -c "import uuid;print(uuid.uuid4())"); IT=$(python3 -c "import uuid;print(uuid.uuid4())"); SID=$(python3 -c "import uuid;print(uuid.uuid4())")
curl -sS -o /dev/null -w "upload=%{http_code}\n" -X POST http://localhost:8080/sync/upload -H "Authorization: Bearer $ACCESS" -H 'Content-Type: application/json' -d "{\"batch\":[
  {\"op\":\"PUT\",\"table\":\"day_templates\",\"id\":\"$DT\",\"data\":{\"id\":\"$DT\",\"name\":\"Travel Gym Push\",\"position\":1}},
  {\"op\":\"PUT\",\"table\":\"day_template_items\",\"id\":\"$IT\",\"data\":{\"id\":\"$IT\",\"day_template_id\":\"$DT\",\"exercise_id\":\"$EX\",\"position\":1,\"target_working_sets\":4,\"target_rep_low\":8,\"target_rep_high\":10,\"target_rir_low\":1,\"target_rir_high\":1}},
  {\"op\":\"PUT\",\"table\":\"sessions\",\"id\":\"$SID\",\"data\":{\"id\":\"$SID\",\"date\":\"2026-05-29\",\"split_label\":\"Upper A\",\"day_template_id\":\"$UA\"}}
]}"
echo "--- custom template + item ---"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT t.name, t.is_template, i.position, i.target_working_sets, i.target_rep_low, i.target_rep_high FROM day_templates t JOIN day_template_items i ON i.day_template_id=t.id WHERE t.id='$DT';"
echo "--- session linked to seeded Upper A ---"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT (day_template_id='$UA') FROM sessions WHERE id='$SID';"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DELETE FROM day_templates WHERE id='$DT'; DELETE FROM sessions WHERE id='$SID';"
```

Expected: `upload=200`; the custom template row shows `Travel Gym Push | f | 1 | 4 | 8 | 10` (is_template false, the prescription stored); the session link query prints `t`.

- [ ] **Step 3: Confirm day templates sync down via PowerSync**

Run from repo root:

```bash
PSTOKEN=$(curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -sS -o /tmp/wt-5at-stream.out --max-time 8 -X POST http://localhost:8090/sync/stream \
  -H "Authorization: Token $PSTOKEN" -H 'Content-Type: application/json' -d '{"raw_data": true, "buckets": []}' || true
grep -q '"object_type":"day_templates"' /tmp/wt-5at-stream.out && echo "day_templates sync down OK"
grep -q '"object_type":"day_template_items"' /tmp/wt-5at-stream.out && echo "day_template_items sync down OK"
grep -q 'Upper A' /tmp/wt-5at-stream.out && echo "seeded split synced OK"
```

Expected: `day_templates sync down OK`, `day_template_items sync down OK`, `seeded split synced OK` — the shared seeded split + the user's custom template all reach the client.

- [ ] **Step 4: Confirm git state**

Run from repo root:

```bash
git status
git log --oneline main..HEAD
```

Expected: clean tree; the log shows the commits from Tasks 1–4 (migrations, sync-rules, handler, OpenAPI).

- [ ] **Step 5: No commit (verification only)**

Plan 5a-templates is complete. The backend now has the full logging data model: exercises (seeded + custom), sessions/sets/bodyweight with top-set/PR, and day templates (seeded README split + custom days) with the session→template link — all written through `/sync/upload` and synced per-user. Next: **Flutter foundations** (the PowerSync SDK + `uploadData` connector targeting `/sync/upload`, the local schema mirroring all these tables, and the true local-write→Postgres round-trip), then the **UX design** brainstorm and the real screens.
