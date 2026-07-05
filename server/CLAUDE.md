# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Go backend for Reps: auth (argon2id + RS256 JWT/JWKS), PowerSync token endpoint, and the `/sync/upload` write path. chi + pgx + slog + goose.

## Commands

Run from the repo root. The dev Postgres must be up first (`docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d` — both files or host ports drop; Postgres is on **5433**).

- `make -C server test` — injects `TEST_DATABASE_URL` (the dev DB). Single test: `TEST_DATABASE_URL='postgres://postgres:change-me-locally@localhost:5433/workout_tracker?sslmode=disable' go test ./internal/api -run TestName` (run with `-C server` or full package path).
- `make -C server build` / `run` / `fmt` / `vet`
- `make -C server gen-jwt-key` — RSA signing key → gitignored `server/.secrets/jwt_private_key.pem` (run it FROM a context where `server/go.mod` resolves; a wrong-cwd run once produced a 0-byte key)
- `make -C server create-user EMAIL=me@example.com PASSWORD=devpassword` — dev login (EMAIL/PASSWORD have NO defaults; the bare target fatals). Upserts on email (`ON CONFLICT … DO UPDATE password_hash`), so it doubles as the **password-reset tool**: run with `DATABASE_URL=<prod> EMAIL=… PASSWORD=…`. After a reset, the app's re-login shows a keep/discard prompt — "use account data" wipes local data (`disconnectAndClear`); pick **Keep** whenever local data may be unsynced.
- `make -C server migrate-up|down|status|reset` — manual goose control for dev; NOT needed for deploys
- `make -C server lint-spec` — vacuum-lints `api/openapi.yaml`

## Architecture

- `cmd/server/main.go` — wiring; **migrations are embedded** (`db/migrations/embed.go` + `internal/db/migrate.go`) and run on startup, so a fresh container self-provisions its schema. New migrations: add the `.sql` under `db/migrations/` AND bump the hardcoded `.sql`-file count in `db/migrations/embed_test.go` (it fails the suite otherwise — that's its job).
- `internal/api/` — handlers. `sync_upload.go` is the heart: the PowerSync `uploadData` target.
- `db/migrations/` — goose SQL, numbered; also the source of seed data (template exercises, starter split days).
- Deployment: multi-stage distroless `Dockerfile`; CI pushes to GHCR on main; production = `ct-workout` LXC on the homelab (managed from the separate infra repo).

## The /sync/upload contract (break these and clients brick or diverge)

- Body: `{"batch":[{op: PUT|PATCH|DELETE, table, id, data}]}`, API access token auth.
- **Never return 4xx for bad data** — it permanently blocks the client's upload queue. Each op runs in its own `SAVEPOINT op_sp`: permanent failures (FK violations, ownership misses, garbage) are logged + skipped + 2xx; only transient errors (5xx-worthy) abort for retry.
- Server stamps ownership: `user_id`/`created_by` always come from the token, `is_template` is forced false. Template rows (`created_by NULL`) can never be written by clients — every PATCH/DELETE has an ownership WHERE clause.
- `is_top_set`/`is_pr` are server-computed (recompute hooks after set writes); clients never set them.
- **PATCH handlers apply explicit column allowlists** — columns not read by the handler are silently dropped (e.g. `applySet` PATCH ignores `exercise_id`). When extending a table or expecting a new client-side edit, update the handler's column list or the client must use DELETE+PUT. PATCH opData carries ONLY changed columns — never default omitted fields.
- Reference columns are NOT ownership-validated (`sets.exercise_id`, `day_template_items.exercise_id` accept any id); parent ownership IS validated (set → its session, item → its day template).
- Slug collisions on custom exercises auto-suffix (`<slug>-<id8>`); weights decode via `json.Number` → string (never float).
- Sync rules (`powersync/sync-rules.yaml`): per-user `by_user` bucket + global `templates` bucket. Data queries can't JOIN and can't OR a parameterized condition with a non-parameterized one — denormalize the filter column and use separate buckets instead.
