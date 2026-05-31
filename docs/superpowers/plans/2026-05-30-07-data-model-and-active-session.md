# Data Model + Active-Session Logging Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the backend/data model to the full design ("data model" is the design's most important section), build the Flutter design-system foundation + typed data layer, and ship the **active-session logging flow** (the core gym loop: build a session from a day template, log sets with steppers/RIR, rest timer, live top-set/PR, finish → persist → summary) end-to-end on Linux desktop.

**Architecture:** Backend gets full-fidelity (one migration round): exercise traits, `sessions.duration_min`, `day_templates.focus`/`scheduled_weekday`, a `muscle_targets` table, and a trait seed for the 24-exercise catalog. The Flutter client gets a `WorkoutTokens` theme (dark/light + 4 accents, 3 Google fonts), reactive `UnitService`, core primitives, typed repositories over the 6 synced tables, and an in-memory+local-draft active-session controller. The active session keeps all edits in client state, persists to PowerSync **only at Finish** (one session row + N set rows via the existing CRUD-queue → `/sync/upload`); the server stamps `user_id` and recomputes `is_top_set`/`is_pr` — the client shows those optimistically and trusts the synced flags.

**Tech Stack:** Go + pgx + goose (backend), PowerSync 2.2.0 + Flutter 3.44 (pinned via fvm; run via `make -C app <target>`), `provider` (state), `google_fonts`. Dev Postgres on host port **5433**; dev login `me@example.com` / `devpassword`; the full stack runs via `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d`.

**Scope note:** This plan delivers the data model + active-session milestone. The remaining screens (Today/nav, Progress, Bodyweight, History, Plan editors, Profile/Settings) are **later plans**; their backend columns (focus/weekday/muscle_targets) are added now so there is no second migration round. The design `.jsx` files under `docs/design_handoff_workout_tracker/design/` are the **authoritative visual + interaction spec** — every UI task names the exact file to port; this plan supplies the Flutter architecture, the data contracts, and the load-bearing logic.

**Conventions:** Conventional Commits, subject line only. Run all Flutter via `make -C app <target>` (never bare `flutter`). All migrations are goose (`-- +goose Up` / `-- +goose Down`), applied with `make -C server migrate-up`. Branch off `main` first.

---

## File Structure

**Backend (Go + SQL):**
- `server/db/migrations/00015_exercise_traits.sql` — exercise trait columns
- `server/db/migrations/00016_session_duration.sql` — `sessions.duration_min`
- `server/db/migrations/00017_day_template_schedule.sql` — `day_templates.focus` + `scheduled_weekday`
- `server/db/migrations/00018_muscle_targets.sql` — new `muscle_targets` table + publish + grant
- `server/db/migrations/00019_seed_exercise_traits.sql` — UPDATE the 24 seeded exercises with traits
- `server/internal/api/sync_upload.go` — extend `applyExercise`, `applySession`, `applyDayTemplate`; add `applyMuscleTarget` + switch case
- `powersync/sync-rules.yaml` — add `muscle_targets` to the `by_user` bucket (verify other tables use `SELECT *`)

**Flutter — theme/design system (`app/lib/theme/`, `app/lib/widgets/`):**
- `app/lib/theme/tokens.dart` — `WorkoutTokens` ThemeExtension (colors), `AppRadius`/`AppSpacing`
- `app/lib/theme/app_theme.dart` — `buildTheme(brightness, accent)` → ThemeData
- `app/lib/theme/typography.dart` — Space Grotesk / Hanken Grotesk / JetBrains Mono text styles
- `app/lib/theme/icons.dart` — icon glyph map
- `app/lib/units/unit_service.dart` — `UnitService` (ChangeNotifier) + `fmtWt`/`toKg`/`fromKg`/`uLabel`
- `app/lib/widgets/{card,tag,pr_badge,stepper,rir_picker,section_label}.dart`

**Flutter — data layer (`app/lib/data/`):**
- `app/lib/data/models.dart` — `Exercise`, `DayTemplate`, `Slot`, `ResolvedSlot`, `SessionSummaryRow`, `ExerciseBlockData`, `LoggedSet`, `MuscleTarget`, `rirToString`/`rirParse`
- `app/lib/data/exercise_repository.dart`
- `app/lib/data/day_template_repository.dart`
- `app/lib/data/session_repository.dart`
- `app/lib/data/session_writer.dart` — Finish persistence (session + sets)
- `app/lib/data/active_session_draft.dart` — local-only draft persistence

**Flutter — active session (`app/lib/session/`, `app/lib/sync/schema.dart`):**
- `app/lib/sync/schema.dart` — add new columns + `muscle_targets` table (MODIFY)
- `app/lib/session/active_session_controller.dart` — `SessionDraft`, `BlockState`, `SetState`, `ActiveSessionController` (ChangeNotifier)
- `app/lib/session/active_session_screen.dart` — overlay scaffold (header/body/finish)
- `app/lib/session/exercise_block.dart` — accordion block widget
- `app/lib/session/set_row.dart` — set row widget
- `app/lib/session/rest_timer.dart` — floating rest-timer card
- `app/lib/session/exercise_picker_sheet.dart` — add-exercise bottom sheet
- `app/lib/session/session_summary_screen.dart` — post-finish summary overlay
- `app/lib/main.dart` — minimal launcher wiring (MODIFY)

---

## Phase A — Backend & schema extension (full-fidelity, one round)

### Task A1: Migration — exercise trait columns

**Files:**
- Create: `server/db/migrations/00015_exercise_traits.sql`

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- Exercise identity traits + default prescription (design "data model" section).
-- compound drives rest duration + warm-up suggestion; plate_step_kg drives the
-- weight stepper increment; base_weight_kg seeds the first session; default_*
-- pre-fill a new day-template slot (resolveSlot fallback). All nullable except
-- the two with sensible defaults so existing rows stay valid.
ALTER TABLE exercises
    ADD COLUMN equip               TEXT,
    ADD COLUMN compound            BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN base_weight_kg      NUMERIC(6,2),
    ADD COLUMN plate_step_kg       NUMERIC(5,2) NOT NULL DEFAULT 2.5,
    ADD COLUMN default_rep_low     INTEGER,
    ADD COLUMN default_rep_high    INTEGER,
    ADD COLUMN default_warmup_sets INTEGER,
    ADD COLUMN default_working_sets INTEGER,
    ADD COLUMN default_rir_low     INTEGER,
    ADD COLUMN default_rir_high    INTEGER;

-- +goose Down
ALTER TABLE exercises
    DROP COLUMN equip,
    DROP COLUMN compound,
    DROP COLUMN base_weight_kg,
    DROP COLUMN plate_step_kg,
    DROP COLUMN default_rep_low,
    DROP COLUMN default_rep_high,
    DROP COLUMN default_warmup_sets,
    DROP COLUMN default_working_sets,
    DROP COLUMN default_rir_low,
    DROP COLUMN default_rir_high;
```

- [ ] **Step 2: Commit** — `git add server/db/migrations/00015_exercise_traits.sql && git commit -m "feat(db): add exercise trait + default-prescription columns"`

### Task A2: Migration — session duration

**Files:**
- Create: `server/db/migrations/00016_session_duration.sql`

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- Wall-clock workout length, written by the client at Finish (elapsed/60).
ALTER TABLE sessions ADD COLUMN duration_min INTEGER;

-- +goose Down
ALTER TABLE sessions DROP COLUMN duration_min;
```

- [ ] **Step 2: Commit** — `git commit -am "feat(db): add sessions.duration_min"`

### Task A3: Migration — day template schedule fields

**Files:**
- Create: `server/db/migrations/00017_day_template_schedule.sql`

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- focus = labeled training emphasis (e.g. "Push"); scheduled_weekday = 0..6
-- (Mon..Sun) for the week strip / day chip. Both nullable (custom days may omit).
ALTER TABLE day_templates
    ADD COLUMN focus            TEXT,
    ADD COLUMN scheduled_weekday SMALLINT;

-- +goose Down
ALTER TABLE day_templates
    DROP COLUMN focus,
    DROP COLUMN scheduled_weekday;
```

- [ ] **Step 2: Commit** — `git commit -am "feat(db): add day_templates.focus + scheduled_weekday"`

### Task A4: Migration — muscle_targets table (+ publish + grant)

**Files:**
- Create: `server/db/migrations/00018_muscle_targets.sql`

Reference the publication/grant pattern from `server/db/migrations/00009_powersync_publish_workout_tables.sql` and `00013_powersync_publish_day_templates.sql` (the publication is named `powersync`; the read role is `powersync_role`).

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- Per-user weekly set target per muscle group (Today / Progress volume bars).
-- One row per (user, muscle). Synced per-user via the by_user bucket.
CREATE TABLE muscle_targets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    muscle      TEXT NOT NULL,
    target_sets INTEGER NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, muscle)
);

CREATE INDEX muscle_targets_user_idx ON muscle_targets (user_id);

ALTER PUBLICATION powersync ADD TABLE muscle_targets;
GRANT SELECT ON muscle_targets TO powersync_role;

-- +goose Down
ALTER PUBLICATION powersync DROP TABLE muscle_targets;
DROP TABLE muscle_targets;
```

- [ ] **Step 2: Verify** the publication name + role name match the existing publish migrations (open `00009`/`00013`; if the role grant there uses a different role name, match it).

- [ ] **Step 3: Commit** — `git add server/db/migrations/00018_muscle_targets.sql && git commit -m "feat(db): add muscle_targets table with per-user sync"`

### Task A5: Migration — seed exercise traits

**Files:**
- Create: `server/db/migrations/00019_seed_exercise_traits.sql`
- Read first: `server/db/migrations/00005_seed_template_exercises.sql` (existing slugs/names), `docs/design_handoff_workout_tracker/design/app/data.jsx` (the `EXERCISES` array, lines ~28–57)

The design `EXERCISES` array carries per-exercise traits. **The design `id` does NOT equal the existing `slug` for 16 of 24 rows** (verified against `00005`), and a name fallback is unsafe (seeded names are sentence-case so `=` matching fails, and two rows are both named "Hack Squat"). **Key every UPDATE strictly on the real slug** — the full verified mapping is in Step 1; never match by name. A `WHERE slug=` that matches no row is a silent no-op (goose still reports success), which would leave the catalog at defaults and make the active-session build-model run on hardcoded fallbacks. (RIR string → low/high int pair: `'1–0'`/`'0–1'` → 0,1; `'1'` → 1,1.)

- [ ] **Step 1: Write all 24 idempotent UPDATEs**, keyed on the real slugs (verified against `00005` + `data.jsx`; trait numbers cross-checked). Paste verbatim:

```sql
-- +goose Up
UPDATE exercises SET equip='Panatta', compound=TRUE, base_weight_kg=72.5, plate_step_kg=2.5, default_rep_low=6, default_rep_high=8, default_warmup_sets=2, default_working_sets=4, default_rir_low=0, default_rir_high=1 WHERE slug='incline-bench-press';
UPDATE exercises SET equip='Horizontal', compound=FALSE, base_weight_kg=64, plate_step_kg=2.0, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='chest-press';
UPDATE exercises SET equip='Dumbbell', compound=FALSE, base_weight_kg=24, plate_step_kg=2.0, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='seated-db-shoulder-press';
UPDATE exercises SET equip='Dumbbell', compound=FALSE, base_weight_kg=11, plate_step_kg=1.0, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='db-lateral-raise';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=40, plate_step_kg=2.5, default_rep_low=12, default_rep_high=15, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='reverse-pec-deck';
UPDATE exercises SET equip='Cable', compound=FALSE, base_weight_kg=32, plate_step_kg=2.5, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='rope-triceps-pushdown';
UPDATE exercises SET equip='Cable', compound=FALSE, base_weight_kg=27, plate_step_kg=2.5, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='overhead-rope-extension';
UPDATE exercises SET equip='Machine', compound=TRUE, base_weight_kg=120, plate_step_kg=5.0, default_rep_low=6, default_rep_high=8, default_warmup_sets=2, default_working_sets=4, default_rir_low=0, default_rir_high=1 WHERE slug='hack-squat';
UPDATE exercises SET equip='Feet high/wide', compound=FALSE, base_weight_kg=200, plate_step_kg=5.0, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='leg-press';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=60, plate_step_kg=5.0, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='leg-extension';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=55, plate_step_kg=5.0, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='seated-leg-curl';
UPDATE exercises SET equip='Weighted', compound=FALSE, base_weight_kg=90, plate_step_kg=5.0, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=4, default_rir_low=0, default_rir_high=1 WHERE slug='standing-calf-raise';
UPDATE exercises SET equip='Wide pronated', compound=TRUE, base_weight_kg=75, plate_step_kg=2.5, default_rep_low=6, default_rep_high=8, default_warmup_sets=2, default_working_sets=4, default_rir_low=0, default_rir_high=1 WHERE slug='lat-pulldown';
UPDATE exercises SET equip='Panatta, wide', compound=FALSE, base_weight_kg=80, plate_step_kg=5.0, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=4, default_rir_low=1, default_rir_high=1 WHERE slug='row';
UPDATE exercises SET equip='Close neutral', compound=FALSE, base_weight_kg=60, plate_step_kg=2.5, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='iliac-pulldown';
UPDATE exercises SET equip='Close neutral', compound=FALSE, base_weight_kg=65, plate_step_kg=2.5, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='cable-row';
UPDATE exercises SET equip='Barbell', compound=FALSE, base_weight_kg=32, plate_step_kg=2.5, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='preacher-curl';
UPDATE exercises SET equip='Cable', compound=FALSE, base_weight_kg=27, plate_step_kg=2.5, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='cable-hammer-curl';
UPDATE exercises SET equip='Cable', compound=FALSE, base_weight_kg=22, plate_step_kg=2.5, default_rep_low=12, default_rep_high=15, default_warmup_sets=0, default_working_sets=3, default_rir_low=0, default_rir_high=1 WHERE slug='cable-curl';
UPDATE exercises SET equip='Barbell', compound=TRUE, base_weight_kg=100, plate_step_kg=2.5, default_rep_low=6, default_rep_high=8, default_warmup_sets=2, default_working_sets=4, default_rir_low=1, default_rir_high=1 WHERE slug='romanian-deadlift';
UPDATE exercises SET equip='Depth focus', compound=FALSE, base_weight_kg=90, plate_step_kg=5.0, default_rep_low=10, default_rep_high=12, default_warmup_sets=0, default_working_sets=3, default_rir_low=1, default_rir_high=1 WHERE slug='hack-squat-depth-focus';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=50, plate_step_kg=5.0, default_rep_low=8, default_rep_high=10, default_warmup_sets=0, default_working_sets=4, default_rir_low=1, default_rir_high=1 WHERE slug='lying-leg-curl';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=30, plate_step_kg=2.5, default_rep_low=12, default_rep_high=15, default_warmup_sets=0, default_working_sets=3, default_rir_low=0, default_rir_high=1 WHERE slug='unilateral-leg-extension';
UPDATE exercises SET equip='Machine', compound=FALSE, base_weight_kg=45, plate_step_kg=5.0, default_rep_low=12, default_rep_high=15, default_warmup_sets=0, default_working_sets=4, default_rir_low=0, default_rir_high=1 WHERE slug='seated-calf-raise';

-- +goose Down
-- Reset traits to defaults (idempotent rollback).
UPDATE exercises SET equip=NULL, compound=FALSE, base_weight_kg=NULL, plate_step_kg=2.5,
  default_rep_low=NULL, default_rep_high=NULL, default_warmup_sets=NULL,
  default_working_sets=NULL, default_rir_low=NULL, default_rir_high=NULL
  WHERE is_template=TRUE;
```

- [ ] **Step 2: HARD coverage gate** — after `make -C server migrate-up` (Task A8), assert every seeded catalog row got traits (a no-op UPDATE returns success on 0 rows, so existence-only checks are insufficient). The live dev DB also has a non-catalog template row `validation-squat` (not in `00005`/`data.jsx`) that legitimately stays NULL — scope it out:

```bash
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -tAc \
 "SELECT count(*) FROM exercises WHERE is_template AND created_by IS NULL AND slug <> 'validation-squat' AND base_weight_kg IS NOT NULL;"
```
Expected: **24**. If it is not 24, a slug is wrong — diff the migration's 24 `WHERE slug=` values against `SELECT slug FROM exercises WHERE is_template AND created_by IS NULL AND slug <> 'validation-squat' ORDER BY slug;` and fix. Do NOT proceed until this is 24.

- [ ] **Step 3: Commit** — `git add server/db/migrations/00019_seed_exercise_traits.sql && git commit -m "feat(db): seed trait values onto the template exercise catalog"`

### Task A6: Sync rules — expose muscle_targets

**Files:**
- Modify: `powersync/sync-rules.yaml`

- [ ] **Step 1: Confirmed** — every `by_user` and `templates` data query uses `SELECT *`, so the new exercises/sessions/day_templates columns auto-sync with zero edits here. (Re-confirm by skimming the file; if any query lists explicit columns, add the new ones — but the review verified `SELECT *` throughout.)

- [ ] **Step 2: Add** a `muscle_targets` data query to the `by_user` bucket, mirroring the existing per-user table entries:

```yaml
      - SELECT * FROM muscle_targets WHERE user_id = bucket.user_id
```

(Match the exact indentation/style of the sibling `sessions`/`sets` queries in the file. If the file lists explicit columns elsewhere, list `id, user_id, muscle, target_sets, created_at` instead of `*`.)

- [ ] **Step 3: Commit** — `git add powersync/sync-rules.yaml && git commit -m "feat(sync): sync muscle_targets per user"`

### Task A7: Upload handler — accept the new writable columns

**Files:**
- Modify: `server/internal/api/sync_upload.go` (`applyExercise` ~242, `applySession` ~172, `applyDayTemplate` ~380, `applyOp` switch ~127)

Follow the **existing patterns in this file**: PUT upserts with explicit columns; PATCH uses `COALESCE(NULLIF($n,'')::cast, col)` preserve-on-omit (model the multi-column shape on `applyDayTemplateItem`'s PATCH ~429, NOT the thin 2-column `applyExercise` PATCH ~255); `created_by`/`user_id` are server-stamped; `is_template` forced FALSE for custom rows. **Critical:** PowerSync sends omitted/NULL values as JSON null, which `str()` maps to `""`; a bare `''::numeric`/`''::bool` throws → the op is logged-and-skipped (never-4xx) → the write silently vanishes. Always wrap with `NULLIF($n,'')`. The current `applyExercise` PUT has only text columns, so there is NO existing numeric/bool pattern to copy — write the casts explicitly. Read each function before editing.

- [ ] **Step 1: Extend `applyExercise`** PUT + PATCH to also read/write `equip` (text), `compound` (bool), `base_weight_kg`, `plate_step_kg` (numeric), `default_rep_low`, `default_rep_high`, `default_warmup_sets`, `default_working_sets`, `default_rir_low`, `default_rir_high` (ints).
  - **PUT:** nullable numerics/ints → `NULLIF($n,'')::numeric` / `NULLIF($n,'')::numeric::int`. The two NOT-NULL-DEFAULT columns must default when omitted (an explicit NULL violates NOT NULL — the column DEFAULT only fires when omitted from the INSERT, which we are NOT doing): `compound = COALESCE(NULLIF($n,'')::bool, false)`, `plate_step_kg = COALESCE(NULLIF($n,'')::numeric, 2.5)`. Keep `is_template=FALSE` + `created_by` stamped.
  - **PATCH:** per-column `COALESCE(NULLIF($n,'')::numeric::int, col)` (and `COALESCE(NULLIF($n,'')::bool, compound)` for compound) to preserve omitted traits; keep the `WHERE id=$1 AND created_by=$2` owner guard.

- [ ] **Step 2: Extend `applySession`** PUT + PATCH to read/write `duration_min` (int, `NULLIF($n,'')::numeric::int`, COALESCE-preserve on PATCH).

- [ ] **Step 3: Extend `applyDayTemplate`** PUT + PATCH to read/write `focus` (text) and `scheduled_weekday` (`NULLIF($n,'')::numeric::int`).

- [ ] **Step 4: Add `applyMuscleTarget`** (signature `(ctx, tx, userID, op)`; do NOT touch `topGroups`/`prExercises`). The table has a UUID PK **and** `UNIQUE(user_id, muscle)`, so a naive `ON CONFLICT (id)` (like `applyBodyweight`) would NOT resolve the realistic "set my Chest target" conflict (fresh uuid each write → unique violation → silently skipped). Upsert on the composite key:

```go
// PUT
_, err := tx.Exec(ctx,
  `INSERT INTO muscle_targets (id, user_id, muscle, target_sets)
   VALUES ($1::uuid, $2::uuid, $3, NULLIF($4,'')::numeric::int)
   ON CONFLICT (user_id, muscle) DO UPDATE SET target_sets = EXCLUDED.target_sets`,
  op.ID, userID, muscle, targetSetsStr)
```
  - PATCH: `UPDATE muscle_targets SET target_sets = COALESCE(NULLIF($n,'')::numeric::int, target_sets) WHERE id=$1 AND user_id=$2`. DELETE: `WHERE id=$1 AND user_id=$2`. `created_at` is never client-settable. Add `case "muscle_targets": return applyMuscleTarget(ctx, tx, userID, op)` to the `applyOp` switch.

- [ ] **Step 5: Add handler tests** — extend `server/internal/api/sync_upload_test.go` (mirror an existing `TestUpload_*`): (a) PUT a `muscle_targets` row twice for the same `(user_id, muscle)` with different `target_sets` → assert exactly ONE row, latest value (catches the conflict-target bug); (b) PUT a custom `exercises` row with all trait fields OMITTED → response is 2xx AND the row exists with `compound=false`, `plate_step_kg=2.5` (catches the NULL-cast skip / NOT-NULL violation); (c) PATCH a `sessions` row's `duration_min` and a `day_templates` row's `focus` → assert the other columns are preserved. These runtime DB errors are swallowed by the never-4xx contract, so `build`/`vet` cannot catch them — the tests are the gate. Run `make -C server test`.

- [ ] **Step 6: Build + vet** — `make -C server build && make -C server vet`. Expected: no errors.

- [ ] **Step 7: Commit** — `git commit -am "feat(api): accept exercise traits, duration, day focus/weekday, muscle_targets in /sync/upload"`

### Task A8: Apply migrations + rebuild server + validate replication (INLINE)

**Files:** none (ops)

- [ ] **Step 1: Apply migrations** to the dev DB — `make -C server migrate-up` then `make -C server migrate-status` (expect 00015–00019 applied).

- [ ] **Step 2: Rebuild + restart the server container** so the new handler ships:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d --build server
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env ps
```

- [ ] **Step 3: Verify the seed + columns** —
`docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -c "SELECT slug, compound, base_weight_kg, plate_step_kg, default_working_sets FROM exercises WHERE is_template ORDER BY slug LIMIT 5;"`
Expected: trait values populated (not all defaults).

- [ ] **Step 4: Verify replication** — new columns on already-published tables need no re-publish; confirm `muscle_targets` actually joined the publication and the slot is active:
```bash
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -tAc \
 "SELECT tablename FROM pg_publication_tables WHERE pubname='powersync' ORDER BY tablename;"   # expect muscle_targets listed
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -tAc \
 "SELECT slot_name, active FROM pg_replication_slots;"   # expect active=t
```
No code change here; the Flutter schema (Task A9) defines the client view. (`muscle_targets`' UUID PK gives sufficient default REPLICA IDENTITY for UPDATE/DELETE.)

### Task A9: Client schema — add the new columns + muscle_targets table

**Files:**
- Modify: `app/lib/sync/schema.dart`

Reference the existing column-type rules in this file (NUMERIC→`Column.text`, bool→`Column.integer`, dates→`Column.text`, never declare `id`).

- [ ] **Step 1: Add to the `exercises` Table:** `Column.text('equip')`, `Column.integer('compound')`, `Column.text('base_weight_kg')`, `Column.text('plate_step_kg')`, `Column.integer('default_rep_low')`, `Column.integer('default_rep_high')`, `Column.integer('default_warmup_sets')`, `Column.integer('default_working_sets')`, `Column.integer('default_rir_low')`, `Column.integer('default_rir_high')`.

- [ ] **Step 2: Add to the `sessions` Table:** `Column.integer('duration_min')`.

- [ ] **Step 3: Add to the `day_templates` Table:** `Column.text('focus')`, `Column.integer('scheduled_weekday')`.

- [ ] **Step 4: Add a new `muscle_targets` Table:** `Table('muscle_targets', [Column.text('user_id'), Column.text('muscle'), Column.integer('target_sets'), Column.text('created_at')])`.

- [ ] **Step 5: Verify** — `make -C app analyze` (expect no issues).

- [ ] **Step 6: Commit** — `git add app/lib/sync/schema.dart && git commit -m "feat(app): extend local schema with traits, duration, focus/weekday, muscle_targets"`

---

## Phase B — Design-system foundation

> Port tokens/typography from `docs/design_handoff_workout_tracker/README.md` ("Design Tokens" section) and `design/app/ui.jsx`. Active-session needs: tokens, fonts, formatters, icons, `Card`, `Tag`, `PRBadge`, `Stepper`, `RirPicker`, `SectionLabel`. Charts/Sparkline are deferred to later (Progress/Today) plans.

### Task B1: Dependencies

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add** under `dependencies`: `google_fonts: ^6.2.1`, `provider: ^6.1.2`. (Keep existing deps.)
- [ ] **Step 2:** `make -C app get` (expect resolve OK).
- [ ] **Step 3: Commit** — `git commit -am "build(app): add google_fonts + provider"`

### Task B2: Color tokens + theme

**Files:**
- Create: `app/lib/theme/tokens.dart`, `app/lib/theme/app_theme.dart`
- Test: `app/test/theme/tokens_test.dart`

- [ ] **Step 1: Write a test** asserting both brightnesses resolve and an accent swaps:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

void main() {
  test('dark + light tokens resolve; accent applies', () {
    final dark = buildTheme(Brightness.dark, const Color(0xFFc2f53a));
    final light = buildTheme(Brightness.light, const Color(0xFF5ce6a4));
    final d = dark.extension<WorkoutTokens>()!;
    final l = light.extension<WorkoutTokens>()!;
    expect(d.bg, const Color(0xFF0b0b0c));
    expect(l.bg, const Color(0xFFf3f2ec));
    expect(d.accent, const Color(0xFFc2f53a));
    expect(l.accent, const Color(0xFF5ce6a4));
    expect(d.accentInk, const Color(0xFF0b0c08)); // constant in both modes
  });
}
```

- [ ] **Step 2: Run** `make -C app test` — expect FAIL (no WorkoutTokens).

- [ ] **Step 3: Implement `tokens.dart`** — a `WorkoutTokens extends ThemeExtension<WorkoutTokens>` with fields `bg, surface, surface2, surface3, line, lineStrong, text, dim, faint, accent, accentInk, danger` (all `Color`), plus `copyWith`/`lerp`. Use the exact hex/alpha from README "Design Tokens": dark `bg #0b0b0c, surface #131316, surface2 #191920, surface3 #262630, line white@.07, lineStrong white@.14, text #f3f3f1, dim white@.62, faint white@.38, danger #ff6b5e`; light `bg #f3f2ec, surface #ffffff, surface2 #f6f5ef, surface3 #e9e8e0, line black@.08, lineStrong black@.15, text #15150f, dim black@.6, faint black@.4`; `accentInk` constant `#0b0c08` both modes. Add `const accents = [Color(0xFFc2f53a), Color(0xFF5ce6a4), Color(0xFFffc24b), Color(0xFF5cc8ff)];` and a radius/spacing const set (`radius=15`, `pill=99`, `pad=16`, `gutter=16`).

- [ ] **Step 4: Implement `app_theme.dart`** — `ThemeData buildTheme(Brightness b, Color accent)` building the WorkoutTokens for `b` (with `accent`), wiring `scaffoldBackgroundColor=bg`, `extensions:[tokens]`, and the text theme from Task B3. Provide a `BuildContext` extension `WorkoutTokens get tokens => Theme.of(this).extension<WorkoutTokens>()!`.

- [ ] **Step 5: Run** `make -C app test` — expect PASS.

- [ ] **Step 6: Commit** — `git add app/lib/theme app/test/theme && git commit -m "feat(app): WorkoutTokens theme (dark/light + accents)"`

### Task B3: Typography

**Files:**
- Create: `app/lib/theme/typography.dart`

- [ ] **Step 1: Implement** a `WorkoutType` helper exposing `display(...)` (Space Grotesk, weights 400–700, negative letter-spacing −0.02–−0.03), `body(...)` (Hanken Grotesk 400–800, 13–16), `mono(...)` (JetBrains Mono 400–700, 9–13, uppercase labels letter-spacing 0.06–0.12) via `google_fonts` (`GoogleFonts.spaceGrotesk`, `GoogleFonts.hankenGrotesk`, `GoogleFonts.jetBrainsMono`). Each takes `{double size, FontWeight weight, Color color, double? letterSpacing}`.

- [ ] **Step 2:** Wire a default `TextTheme` (body = Hanken) into `buildTheme` (Task B2 step 4).
- [ ] **Step 3:** `make -C app analyze` (expect clean).
- [ ] **Step 4: Commit** — `git commit -am "feat(app): typography (Space Grotesk / Hanken / JetBrains Mono)"`

### Task B4: UnitService + formatters

**Files:**
- Create: `app/lib/units/unit_service.dart`
- Test: `app/test/units/unit_service_test.dart`

- [ ] **Step 1: Write tests** (port the `ui.jsx` formatter semantics):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/units/unit_service.dart';

void main() {
  test('kg formatting strips trailing .0; lb converts + rounds whole', () {
    final u = UnitService()..setUnit(Unit.kg);
    expect(u.fmtWt(72.5), '72.5');
    expect(u.fmtWt(80.0), '80');
    expect(u.uLabel, 'kg');
    u.setUnit(Unit.lb);
    expect(u.uLabel, 'lb');
    expect(u.fmtWt(100.0), '220'); // 100 * 2.2046226 -> 220 (whole)
  });
  test('toKg/fromKg round-trip via factor 2.2046226', () {
    expect(UnitService.fromKg(10, Unit.lb), closeTo(22.046226, 1e-6));
    expect(UnitService.toKg(22.046226, Unit.lb), closeTo(10, 1e-6));
  });
}
```

- [ ] **Step 2: Run** — expect FAIL.

- [ ] **Step 3: Implement** `UnitService extends ChangeNotifier` with `enum Unit { kg, lb }`, `Unit unit`, `setUnit(u){ if changed notifyListeners() }`, static `const lbFactor = 2.2046226`, static `toKg`/`fromKg`, instance `fmtWt(double kg)` (lb → rounded whole; kg → integer bare else 1dp with trailing `.0` stripped), getter `uLabel`. (Persistence to shared_preferences is deferred to the Profile plan; default kg.)

- [ ] **Step 4: Run** — expect PASS.
- [ ] **Step 5: Commit** — `git add app/lib/units app/test/units && git commit -m "feat(app): reactive UnitService + weight formatters"`

### Task B5: Icon set

**Files:**
- Create: `app/lib/theme/icons.dart`

- [ ] **Step 1: Implement** a `WIcons` map from glyph name → `IconData`, mapping the ~26 design glyphs (`ui.jsx` `Icons`) to the closest Material icons, preserving meaning: `back`→`Icons.arrow_back_ios_new`, `check`→`Icons.check`, `plus`→`Icons.add`, `minus`→`Icons.remove`, `timer`→`Icons.timer_outlined`, `trophy`→`Icons.emoji_events_outlined`, `bolt`→`Icons.bolt` (filled), `dumbbell`→`Icons.fitness_center`, `chart`→`Icons.show_chart`, `history`→`Icons.history`, `home`→`Icons.home_outlined`, `scale`→`Icons.monitor_weight_outlined`, `gear`/`plan`→`Icons.tune`, `trash`→`Icons.delete_outline`, `chevron`→`Icons.chevron_right`, `search`→`Icons.search`, `user`→`Icons.person_outline`, `edit`→`Icons.edit_outlined`, `target`→`Icons.my_location`, `logout`→`Icons.logout`, `cloud`→`Icons.cloud_outlined`, `more`→`Icons.more_horiz`, `grip`→`Icons.drag_indicator`, `arrowUp`→`Icons.north`, `flame`→`Icons.local_fire_department_outlined`. (Glyph meaning matters, not pixel match.)
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): icon glyph map"`

### Task B6: Core primitives

**Files:**
- Create: `app/lib/widgets/card.dart`, `tag.dart`, `pr_badge.dart`, `stepper.dart`, `rir_picker.dart`, `section_label.dart`
- Test: `app/test/widgets/stepper_test.dart`

> Visual spec: `design/app/ui.jsx` (`Card`, `Tag`, `PRBadge`) + `design/app/screen-log.jsx` (`Stepper`, `RirPicker`). All read colors via `context.tokens`.

- [ ] **Step 1: `WCard`** — `surface` bg, `line` border, `radius` 15, padding param (default 16), optional `onTap`.
- [ ] **Step 2: `Tag`** — small uppercase mono label with tone `accent | mute | solid` (solid = accent bg + accentInk text; mute = surface3 bg + dim text).
- [ ] **Step 3: `PRBadge`** — filled `bolt` icon + "PR" in accent; `small` variant.
- [ ] **Step 4: `SectionLabel`** — mono uppercase label (`faint`) + optional right-aligned action child.
- [ ] **Step 5: Write a `WStepper` test** for the increment/clamp contract:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/stepper.dart';

void main() {
  testWidgets('WStepper increments by step, clamps at >= 0', (tester) async {
    double value = 2.0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (c, setState) => WStepper(
        value: value, step: 2.5, format: (v) => v.toStringAsFixed(1),
        onChanged: (v) => setState(() => value = v),
      ),
    ))));
    await tester.tap(find.byKey(const Key('stepper-inc'))); await tester.pump();
    expect(value, 4.5);
    await tester.tap(find.byKey(const Key('stepper-dec'))); // 4.5 -> 2.0
    await tester.tap(find.byKey(const Key('stepper-dec'))); // 2.0 -> 0 (clamp, not -0.5)
    await tester.pump();
    expect(value, 0.0);
  });
}
```

- [ ] **Step 6: Run** — expect FAIL.
- [ ] **Step 7: Implement `WStepper`** — `−`/`+` buttons (keys `stepper-dec`/`stepper-inc`, ~30–34px, generous hit area) flanking a `format(value)` label; `onChanged(max(0, round2(value ± step)))`; buttons must NOT bubble taps to an enclosing accordion (wrap `onTap` so it does not propagate). Generic over `double`.
- [ ] **Step 8: Implement `RirPicker`** — segmented 0–3 selector (key `rir-<n>`); selected = solid accent; `onChanged(int)`; supports a disabled/empty state (warm-ups render an empty same-width spacer).
- [ ] **Step 9: Run** `make -C app test` — expect PASS.
- [ ] **Step 10: Commit** — `git add app/lib/widgets app/test/widgets && git commit -m "feat(app): core UI primitives (card, tag, PR badge, stepper, RIR picker, section label)"`

---

## Phase C — Data layer / repositories

### Task C1: Domain models + RIR adapter

**Files:**
- Create: `app/lib/data/models.dart`
- Test: `app/test/data/models_test.dart`

PowerSync rows arrive as `Map<String, dynamic>` (text/int). Models parse at the edge: NUMERIC text → `double` via `double.parse`, int 0/1 → `bool`.

- [ ] **Step 1: Write tests** for the RIR adapter + a fromRow:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';

void main() {
  test('rir low/high <-> display string', () {
    expect(rirToString(1, 1), '1');
    expect(rirToString(0, 1), '0–1');
    expect(rirParse('1–0'), (low: 0, high: 1)); // normalize order
    expect(rirParse('2'), (low: 2, high: 2));
  });
  test('Exercise.fromRow parses traits', () {
    final ex = Exercise.fromRow({
      'id': 'x', 'name': 'Incline', 'slug': 'incline-bench', 'muscle_group': 'chest',
      'compound': 1, 'plate_step_kg': '2.5', 'base_weight_kg': '72.5',
      'default_working_sets': 4, 'default_rep_low': 6, 'default_rep_high': 8,
    });
    expect(ex.compound, true);
    expect(ex.plateStepKg, 2.5);
    expect(ex.baseWeightKg, 72.5);
  });
}
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `models.dart`:
  - `({int low, int high}) rirParse(String s)` — split on `-`/`–`; single → low=high; normalize so `low<=high`.
  - `String rirToString(int low, int high)` — `low==high ? '$low' : '$low–$high'` (en-dash).
  - `class Exercise` — `id, name, slug, muscleGroup, equip?, compound(bool), baseWeightKg?(double), plateStepKg(double, default 2.5), defaultRepLow?, defaultRepHigh?, defaultWarmupSets?, defaultWorkingSets?, defaultRirLow?, defaultRirHigh?, isTemplate(bool)` + `Exercise.fromRow(Map)`.
  - `class Slot` — `{exerciseId, position, workSets?, warmupSets?, repLow?, repHigh?, rirLow?, rirHigh?}` + `fromRow` (from `day_template_items`).
  - `class ResolvedSlot` — fully-resolved `{exercise, workSets, warmupSets, repLow, repHigh, rirLow, rirHigh}` (no nulls).
  - `class DayTemplate` — `{id, slug?, name, focus?, scheduledWeekday?, position, slots: List<Slot>}`.
  - `class LoggedSet` — `{id, exerciseId, setNumber, weightKg(double), reps, rir?, isWarmup(bool), isTopSet(bool), isPr(bool)}` + `fromRow`.
  - `class ExerciseBlockData` — `{exerciseId, sets: List<LoggedSet>, topWeight(double), topReps, isPr}` (computed from a group).
  - `class SessionSummaryRow` — `{id, date, splitLabel?, dayTemplateId?, durationMin?}` + `fromRow`.
  - `class MuscleTarget` — `{id, muscle, targetSets}`.
- [ ] **Step 4: Run** — expect PASS. **Commit** — `git add app/lib/data/models.dart app/test/data && git commit -m "feat(app): domain models + RIR adapter"`

### Task C2: Exercise repository

**Files:**
- Create: `app/lib/data/exercise_repository.dart`

- [ ] **Step 1: Implement** `ExerciseRepository(this.db)` (db = the app `PowerSyncDatabase` from `sync/db.dart`):
  - `Stream<List<Exercise>> watchCatalog()` → `db.watch('SELECT * FROM exercises ORDER BY name').map((rs) => rs.map(Exercise.fromRow).toList())`.
  - `Future<Exercise?> byId(String id)` → `db.getOptional('SELECT * FROM exercises WHERE id = ?', [id])`.
  - `Future<List<Exercise>> all()` (one-shot for pickers).
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): exercise repository"`

### Task C3: Day-template repository + resolveSlot

**Files:**
- Create: `app/lib/data/day_template_repository.dart`
- Test: `app/test/data/resolve_slot_test.dart`

- [ ] **Step 1: Write a test** for `resolveSlot` fallback (slot value wins; null falls back to exercise default; then hardcoded fallback):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/day_template_repository.dart';

void main() {
  test('resolveSlot merges slot over exercise defaults over hardcoded', () {
    final ex = Exercise.fromRow({'id':'e','name':'X','slug':'x','muscle_group':'chest',
      'compound':1,'plate_step_kg':'2.5','default_working_sets':4,'default_rep_low':6,
      'default_rep_high':8,'default_rir_low':0,'default_rir_high':1,'default_warmup_sets':2});
    final slot = Slot(exerciseId:'e', position:1, repLow:10); // overrides only repLow
    final r = resolveSlot(slot, ex);
    expect(r.repLow, 10);        // from slot
    expect(r.repHigh, 8);        // from exercise default
    expect(r.workSets, 4);       // from exercise default
    expect(r.warmupSets, 2);
    expect(r.rirLow, 0);
  });
}
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `resolveSlot(Slot, Exercise) -> ResolvedSlot` (slot ?? exercise.default ?? hardcoded: workSets 3, warmupSets 0, repLow 8, repHigh 12, rirLow 1, rirHigh 1) **and** `DayTemplateRepository(this.db)`:
  - `Stream<List<DayTemplate>> watchDays()` — `db.watch` over `day_templates ORDER BY position`, plus a second `watch`/read of `day_template_items ORDER BY day_template_id, position` joined in Dart (PowerSync sync-rule queries can't JOIN, but local SQLite CAN — use one `db.watch('SELECT ... FROM day_templates dt')` and a grouped item query, assembling `slots` in Dart).
  - `Future<DayTemplate?> byId(String id)`.
- [ ] **Step 4: Run** — expect PASS. **Commit** — `git add app/lib/data/day_template_repository.dart app/test/data/resolve_slot_test.dart && git commit -m "feat(app): day-template repo + resolveSlot"`

### Task C4: Session repository (history reads + last/best)

**Files:**
- Create: `app/lib/data/session_repository.dart`

> Local SQLite CAN JOIN (only the PowerSync sync-rules can't). Use joins freely here.

- [ ] **Step 1: Implement** `SessionRepository(this.db)`:
  - `Future<({double weight, int reps, String date})?> lastTopSet(String exerciseId, {String? beforeDate})` — most recent prior session's top set for an exercise: `SELECT s.weight_kg, s.reps, se.date FROM sets s JOIN sessions se ON se.id=s.session_id WHERE s.exercise_id=? AND s.is_top_set=1 AND s.is_warmup=0 [AND se.date < ?] ORDER BY se.date DESC, se.created_at DESC LIMIT 1` (the `created_at` tie-break makes same-date results deterministic).
  - `Future<double?> bestTopSet(String exerciseId)` — `SELECT MAX(CAST(weight_kg AS REAL)) FROM sets WHERE exercise_id=? AND is_top_set=1 AND is_warmup=0`.
  - `Stream<List<SessionSummaryRow>> watchRecentSessions({int limit=30})`.
  - `Future<List<LoggedSet>> setsForSession(String sessionId)` + a helper `groupIntoBlocks(List<LoggedSet>) -> List<ExerciseBlockData>`.
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): session repository (history, last/best top set)"`

### Task C5: Session writer (Finish persistence)

**Files:**
- Create: `app/lib/data/session_writer.dart`
- Test: `app/test/data/session_writer_test.dart`

Writes go to the **local PowerSync DB** (`db.execute`), which queues CRUD → uploads at the connector. The server stamps `user_id` and computes `is_top_set`/`is_pr`; **do not** write those.

- [ ] **Step 1: Write a test** that the writer issues one session INSERT + one INSERT per set with the right columns, using a fake executor:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_writer.dart';

class FakeExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  test('persistSession writes 1 session + N sets, omits computed flags', () async {
    final exec = FakeExec();
    await persistSession(exec, SessionWrite(
      id: 'sess1', dateIso: '2026-05-30', dayTemplateId: 'day1',
      splitLabel: 'Upper A - Push', durationMin: 42,
      sets: [
        SetWrite(id:'s1', exerciseId:'e1', setNumber:1, weightKg:'60.00', reps:8, rir:1, isWarmup:false),
        SetWrite(id:'s2', exerciseId:'e1', setNumber:2, weightKg:'80.00', reps:6, rir:1, isWarmup:false),
      ],
    ));
    expect(exec.calls.length, 3); // 1 session + 2 sets
    expect(exec.calls.first.$1, contains('INSERT INTO sessions'));
    expect(exec.calls.where((c) => c.$1.contains('INSERT INTO sets')).length, 2);
    // computed flags never written:
    for (final c in exec.calls) {
      expect(c.$1.contains('is_top_set'), isFalse);
      expect(c.$1.contains('is_pr'), isFalse);
    }
  });
}
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `session_writer.dart`: an `abstract class SqlExecutor { Future<void> execute(String, [List<Object?>]); }` (the real one wraps `db`), records `SessionWrite`/`SetWrite`, and `Future<void> persistSession(SqlExecutor, SessionWrite)` that:
  - INSERTs `sessions (id, date, day_template_id, split_label, duration_min)` — `weight_kg` as TEXT, bools as 0/1.
  - For each set, INSERTs `sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup)` (warm-up RIR → null). No `user_id`/`is_top_set`/`is_pr`.
  - **Atomicity:** the production `SqlExecutor` must be the transaction from `db.writeTransaction`, NOT a bare `db` — i.e. the caller (D7) runs `await db.writeTransaction((tx) async => persistSession(PowerSyncTxExecutor(tx), write))` so the session row + all set rows commit as ONE local transaction (and upload as one CRUD transaction). A per-`execute` executor would leave a partial session on a mid-finish crash. Provide a `PowerSyncTxExecutor` wrapping the tx; the `FakeExec` test stays unchanged.
- [ ] **Step 4: Run** — expect PASS. **Commit** — `git add app/lib/data/session_writer.dart app/test/data/session_writer_test.dart && git commit -m "feat(app): session writer (finish persistence)"`

### Task C6: Local active-session draft store

**Files:**
- Create: `app/lib/data/active_session_draft.dart`

- [ ] **Step 1: Implement** a `DraftStore` that serializes the active `SessionDraft` (Task D1) to JSON in the app-support dir (`path_provider.getApplicationSupportDirectory()` + `workout-draft.json`), with `save(SessionDraft)`, `Future<SessionDraft?> load()`, `clear()`. This is **local-only** (never synced). (Reuse the `path`/`path_provider` deps already present.)
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): local-only active-session draft store"`

---

## Phase D — Active-session flow + summary

> Authoritative visual/interaction spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx` + README "Screens → 2. Active session". Port pixel-faithfully against the primitives + tokens from Phase B; wire to the repos from Phase C. The consolidated behavior spec is in this plan's source synthesis — the load-bearing logic is coded below; layout/styling come from the `.jsx`.

### Task D1: SessionDraft + ActiveSessionController (build-model)

**Files:**
- Create: `app/lib/session/active_session_controller.dart`
- Test: `app/test/session/build_model_test.dart`

- [ ] **Step 1: Write a test** for the suggested-weight + warm-up ramp build:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

void main() {
  test('compound block: suggested = roundTo(lastTop + step, step); isolation repeats', () {
    final ex = Exercise.fromRow({'id':'e','name':'X','slug':'x','muscle_group':'back',
      'compound':1,'plate_step_kg':'2.5','base_weight_kg':'75'});
    // no history -> base seed; compound bumps one plate
    final block = buildBlock(resolved: ResolvedSlot(exercise: ex, workSets: 4, warmupSets: 2,
      repLow: 6, repHigh: 8, rirLow: 0, rirHigh: 1), lastTopKg: null);
    expect(block.workingSets.length, 4);
    expect(block.warmupSets.length, 2);
    expect(block.workingSets.first.weightKg, 77.5); // roundTo(75 + 2.5, 2.5)
    expect(block.warmupSets.first.isWarmup, true);
    // Lock down the warm-up ramp roundTo(suggested*(0.5+0.18*i), step):
    expect(block.warmupSets[0].weightKg, 40.0); // roundTo(77.5*0.50, 2.5)
    expect(block.warmupSets[1].weightKg, 52.5); // roundTo(77.5*0.68, 2.5)
  });
}
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `SessionDraft` (`{templateId?, name, focus, startedAt, blocks: List<BlockState>}`), `BlockState` (`{exercise, resolved, warmupSets, workingSets, expanded}`), `SetState` (`{id, weightKg(double), reps, rir(int?), isWarmup, done}`), and pure helpers:
  - `double roundTo(double v, double step) => (v/step).round()*step;`
  - `BlockState buildBlock({required ResolvedSlot resolved, double? lastTopKg})`: `seed = lastTopKg ?? resolved.exercise.baseWeightKg ?? 20`; `suggested = roundTo(seed + (resolved.exercise.compound ? resolved.exercise.plateStepKg : 0), resolved.exercise.plateStepKg)`; warm-ups `i in 0..warmupSets-1`: `weight=roundTo(suggested*(0.5+0.18*i), step), reps=max(1, 8-2*i), rir=null, isWarmup=true`; working `i in 0..workSets-1`: `weight=suggested, reps=repLow, rir=1, isWarmup=false`. All `done=false`, fresh uuid ids.
  - `ActiveSessionController extends ChangeNotifier` holding a `SessionDraft`, with `Future<void> buildFromTemplate(DayTemplate, {required ExerciseRepository, required DayTemplateRepository, required SessionRepository})` (resolves each slot, queries `lastTopSet`, builds blocks), `elapsed` (derived from `startedAt`, exposed as `Duration get elapsed => now - startedAt`), counters `doneWork`/`totalWork`, `toggleDone(block, set)`, `addSet`, `removeBlock`, `addBlock(Exercise)`, `bool get canFinish => doneWork >= 1`, and `int get prCount` (count blocks whose max done-working weight > that block's `bestKg`) — the header (D2) and per-block PR badges (D3) read this one getter so they never disagree.
- [ ] **Step 4: Run** — expect PASS. **Commit** — `git add app/lib/session/active_session_controller.dart app/test/session && git commit -m "feat(app): active-session controller + build-model"`

### Task D2: Active-session overlay scaffold

**Files:**
- Create: `app/lib/session/active_session_screen.dart`

> Port header/body/finish layout from `screen-log.jsx` (sticky header: 36px back btn, `"{name} · {focus}"` display 18/700 + mono line2 `"{doneWork}/{totalWork} sets[ · N PR]"`, right elapsed mono accent `m:ss`, 3px progress bar = doneWork/totalWork). Body = `ListView` of `ExerciseBlock` (Task D3) + dashed "Add exercise" + "Finish workout" (h52, disabled until `controller.canFinish`).

- [ ] **Step 1: Implement** `ActiveSessionScreen` as a full-bleed `Scaffold`/overlay taking an `ActiveSessionController` (via `ChangeNotifierProvider`/`context.watch`). Elapsed timer ticks via a 1s `Timer.periodic` that calls `setState`/rebuild, but the **displayed value is derived from `controller.elapsed`** (now − startedAt) so it survives jank. Back button: if any set `done`, show a confirm dialog before closing.
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): active-session overlay scaffold (header/timer/progress/finish)"`

### Task D3: ExerciseBlock accordion

**Files:**
- Create: `app/lib/session/exercise_block.dart`

> Port from `screen-log.jsx` block markup. Header: 36px completion badge (accent+check when all done, else `surface3` with `done/total`), name 15/600 + mono sub `"{muscle} · {work}×{repLow}–{repHigh} @ RIR {rirStr}"`, live `completedTop` weight (max done working weight) via `unit.fmtWt`, `PRBadge` if `completedTop > bestFor`, chevron rotates 90° when expanded. Expanded: "Last · {daysAgo}" ghost row (from `lastTopSet`), `SET / WEIGHT / REPS / RIR` headers, the `SetRow`s, dashed "Add set", "Remove exercise".

- [ ] **Step 1: Implement** `ExerciseBlock({required BlockState, required bestKg, required lastTop, ...callbacks})`. Pass `bestKg` (from `SessionRepository.bestTopSet`, fetched once when building) so the live PR check is a cheap comparison. Tapping the header toggles `expanded`.
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): active-session exercise block accordion"`

### Task D4: SetRow + live top/PR

**Files:**
- Create: `app/lib/session/set_row.dart`

> Port from `screen-log.jsx` set-row markup. Not-done: index cell (`W` for warm-up, else number) + `WStepper`(weight, step=`exercise.plateStepKg`, formatted via `unit.fmtWt`/`uLabel`) + `WStepper`(reps, step 1) + `RirPicker`(0–3; warm-ups show empty spacer) + 32×34 check button. Done: static `"{fmtWt} {uLabel} × {reps}  RIR {rir}"` + `PRBadge` (if live-PR) or solid `Tag "TOP"` (if live-top & not PR) + check button (toggles back).

- [ ] **Step 1: Implement** `SetRow({required SetState, required Exercise, required bool isLiveTop, required bool isLivePr, required onChanged, required onToggleDone})`. Live flags are passed down (computed by the block: `isLiveTop = done && !isWarmup && weight == maxDoneWorkingWeight`; `isLivePr = isLiveTop && weight > bestKg`) — **optimistic only**; the server's `is_top_set`/`is_pr` win after sync. Steppers must not toggle the accordion (stopPropagation per B6).
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): active-session set row + optimistic top/PR"`

### Task D5: Rest timer

**Files:**
- Create: `app/lib/session/rest_timer.dart`

> Port the floating card from `screen-log.jsx` (`RestTimer`): circular progress ring (fills as rest elapses), "Rest" + `m:ss` (zero-padded ss), `+30s`, `Skip`. Duration = `compound ? 180 : 90`.

- [ ] **Step 1: Implement** `RestTimerCard({required int totalSeconds, required VoidCallback onDismiss})` driven by a stored start timestamp (`remaining = restTotal − (now − restStart)`). With the timestamp model, **`+30s` increments `restTotal` by 30** (extending both the remaining time and the ring denominator) — do NOT mutate "remaining" directly (it would be recomputed away on the next tick). Auto-dismiss at 0; `Skip` calls `onDismiss`. The controller starts it (sets `restTotal` + `restStart`) when a **working** set is toggled to done (not on un-check, not on warm-ups).
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): active-session rest timer"`

### Task D6: Add-exercise picker sheet + add/remove

**Files:**
- Create: `app/lib/session/exercise_picker_sheet.dart`

> Port the picker sheet from `screen-progress.jsx`/`screen-log.jsx` (`ExerciseSheet`, `showBodyweight=false`): search field + exercises grouped by muscle, compound dot, tap to select.

- [ ] **Step 1: Implement** `showExercisePicker(BuildContext, {required List<Exercise>}) -> Future<Exercise?>` as a `showModalBottomSheet`. Wire "Add exercise" in the screen → append a block via `controller.addBlock(ex)` (resolves a default slot from the exercise's own defaults); "Remove exercise" removes the block (confirm if it has done sets).
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): exercise picker sheet + add/remove block"`

### Task D7: Finish → persist

**Files:**
- Modify: `app/lib/session/active_session_controller.dart`

- [ ] **Step 1: Implement** `Future<String> finish(SqlExecutor)` on the controller: build a `SessionWrite` (new uuid; `dateIso = today`; `dayTemplateId = draft.templateId`; `splitLabel = "{name} · {focus}"` (middot, matching the in-app header/summary; History/Summary surface this stored value verbatim, so keep one separator everywhere); `durationMin = (elapsed.inSeconds/60).round()`; sets = all blocks' warm-ups (is_warmup=true) + working sets, in order, with running `set_number` per exercise, `weightKg` as 2dp string, warm-up `rir=null`), call `persistSession`, clear the draft store, return the session id. Do not write computed flags.
- [ ] **Step 2: Add a controller test** asserting `finish` produces the expected `SessionWrite` (counts, splitLabel, warm-ups included, no computed flags) using the `FakeExec`. Run `make -C app test` (expect PASS).
- [ ] **Step 3: Commit** — `git commit -am "feat(app): finish workout -> persist session + sets"`

### Task D8: Session summary overlay

**Files:**
- Create: `app/lib/session/session_summary_screen.dart`

> Port from README "Screens → 3. Session summary": success check, `"{name} · {focus}"`, stat tiles (Duration, Sets, Volume in t/k, PRs), Top sets list with PR badges, "Done".

- [ ] **Step 1: Implement** `SessionSummaryScreen({required String sessionId})` reading the just-written session via `SessionRepository` (it shows the synced/server-computed values once they round-trip; immediately after finish it may briefly show optimistic local rows — acceptable). "Done" pops back to the launcher.
- [ ] **Step 2:** `make -C app analyze` (clean). **Commit** — `git commit -am "feat(app): session summary overlay"`

### Task D9: Minimal launcher wiring + end-to-end validation (INLINE)

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Wire** the app entry: wrap in `MultiProvider` (UnitService, the active `ActiveSessionController`), apply `buildTheme(Brightness.dark, accents[0])`. **Keep the existing login gate** — `main.dart` currently renders `LoginScreen` until `_loggedIn`, then `connectSync`. Replace ONLY the `_loggedIn ? HomeScreen : LoginScreen` true-branch (the throwaway `HomeScreen`) with the launcher; preserve `LoginScreen` + the `_onLoggedIn → connectSync` path. Day templates only appear after login + PowerSync sync of the `templates`/`by_user` buckets, so the launcher must sit behind the gate. The launcher: a `StreamBuilder` over `DayTemplateRepository.watchDays()` + a "Start" button per day and a "Start empty" option, each building the controller from the template and pushing `ActiveSessionScreen`. (Full Today/nav is a later plan; this is the validation entry.)
- [ ] **Step 2: GATE — analyze + test** — `make -C app analyze` (zero issues) and `make -C app test` (all pass).
- [ ] **Step 3: GATE — live round-trip on Linux desktop.** Ensure the stack is up; `make -C app run`. Log in (`me@example.com`/`devpassword`). Pick a seeded day (e.g. "Upper A") → active session builds with suggested weights/warm-ups from the seeded traits. Log a couple of working sets (steppers + RIR + check), observe the rest timer + live TOP/PR badges, tap "Finish workout" → summary.
- [ ] **Step 4: Verify persistence** —
```bash
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -c \
 "SELECT se.split_label, se.duration_min, s.set_number, s.weight_kg, s.reps, s.is_warmup, s.is_top_set, s.is_pr
    FROM sets s JOIN sessions se ON se.id=s.session_id
   WHERE se.user_id=(SELECT id FROM users WHERE email='me@example.com')
     AND se.created_at=(SELECT max(created_at) FROM sessions WHERE user_id=(SELECT id FROM users WHERE email='me@example.com'))
   ORDER BY s.exercise_id, s.set_number;"
```
Expected: the session has `duration_min` and `split_label "{day} · {focus}"` (middot); sets exist with entered weights/reps; warm-ups have `is_warmup=t`; the heaviest working set per exercise has `is_top_set=t`, PRs flagged. Confirm the synced flags then appear in the app's summary/home.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): minimal launcher wiring for the active-session flow"`

---

## Deferred to later plans (not this milestone)
- Today dashboard + 5-tab nav shell + center FAB (consumes `scheduled_weekday`, "next in rotation", weekly-volume bars vs `muscle_targets`).
- Progress (Lift metric tabs + LineChart) + Bodyweight view (Sparkline, log sheet).
- History (week grouping, summary tiles).
- Plan editors (Split day/slot editor; Exercise library editor — write the new exercise trait columns).
- Profile & Settings + `SettingsService` (client-local unit/theme/accent + configurable server URL) + real sync status.
- Charts (`LineChart`, `Sparkline`), `muscle_targets` editing UI.

## Open decisions already settled (recorded here for executors)
- Backend extension = **full-fidelity now** (all migrations this round); settings = **client-local** (later plan); active-session draft = **local-only, persist at Finish**; warm-ups **persisted** (`is_warmup=true`); steppers increment in **kg-space**; live top/PR is **optimistic**, server flags authoritative; RIR string ↔ low/high int pair via the adapter (warm-up logged RIR = null).

## Reviewer clarifications (apply during build — not bugs)
- **Optimistic vs synced top/PR:** the live session may flag multiple equal-weight sets as TOP and show a PR that the server later collapses (server `recomputeTopSet` keeps exactly one row; `recomputePR` is strict-greater vs earlier-dated sessions). After sync-down the summary/home may show **fewer** TOP/PR badges than the live session — expected, not a bug.
- **RIR ranges are normalized** to `low–high` (so `'1–0'` displays as `'0–1'`). Intentional.
- **`google_fonts`** fetches font files over HTTP on first use and falls back to system fonts offline; `GoogleFonts.xxx()` returns a `TextStyle` synchronously, so there is no test/analyze impact and fonts are not bundled. Don't chase a non-bug here.
- **A4 grant:** `00004` already runs `ALTER DEFAULT PRIVILEGES … GRANT SELECT … TO powersync_role`, so new public tables auto-grant; the explicit `GRANT` in `00018` is belt-and-suspenders (keep it). The publish *pattern* (`ALTER PUBLICATION powersync ADD TABLE`) is in `00009`/`00013`; the grant pattern is in `00004`.
- **A9 ↔ A7 coupling:** every column made writable in A7 (`duration_min`, `focus`, `scheduled_weekday`, all 10 exercise traits) MUST have a matching `schema.dart` declaration in A9, or PowerSync silently strips it from `opData` before upload (no test failure). Both tasks precede D7 — keep that order.
- **D1 seed fallback:** `seed = lastTopKg ?? baseWeightKg ?? 20` — the `?? 20` only fires for a *custom* exercise with no base; the seeded catalog always has `base_weight_kg` after A5, so add a comment marking `20` as the custom-only floor, not the normal path.
- **A5 muscle taxonomy (later-plan note):** `data.jsx` uses `'hams'`/`'glutes'`; the DB uses `'hamstrings'` and has no glutes exercise. A5 does NOT touch `muscle_group`, so it's unaffected; when Today/Progress volume bars are built, normalize `'hams'→'hamstrings'` and treat the DB value as authoritative.
