# server/

Go HTTP API for the workout-tracker. Stack: chi + pgx/v5 + slog + goose
(migrations) + Postgres.

All commands below run from the **repo root**.

## Prerequisites

- Go 1.24+ (`go version`)
- Postgres running locally from the `infra/` stack — see `infra/README.md`

## First-time setup

1. Start Postgres if it's not already up:

       docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d

2. Apply migrations:

       make -C server migrate-up

3. Run the server:

       make -C server run

   Stdout will show a structured JSON log line like
   `{"...","msg":"server starting","addr":":8080"}`.

4. Verify both endpoints from another terminal:

       curl -i http://localhost:8080/healthz
       curl -i http://localhost:8080/readyz

   Both should return HTTP 200 with a JSON body.

## Useful commands

| Command | What it does |
| ------- | ------------ |
| `make -C server help`            | List all Make targets |
| `make -C server build`           | Compile to `server/bin/server` |
| `make -C server run`             | Run the server against the local dev DB |
| `make -C server test`            | Run all Go tests (DB tests use the local dev DB) |
| `make -C server fmt`             | `go fmt ./...` |
| `make -C server vet`             | `go vet ./...` |
| `make -C server migrate-up`      | Apply all pending migrations |
| `make -C server migrate-down`    | Roll back the most recent migration |
| `make -C server migrate-status`  | Show migration status |
| `make -C server migrate-reset`   | Roll back **all** migrations (destructive) |

## File layout

- `cmd/server/main.go` — entry point: load config, open DB, start HTTP server with graceful shutdown.
- `internal/config/` — env-driven config loader (`DATABASE_URL`, `HTTP_ADDR`, `LOG_LEVEL`).
- `internal/db/` — `pgxpool` factory.
- `internal/api/` — chi router and HTTP handlers (`/healthz`, `/readyz`).
- `db/migrations/` — goose-managed `.sql` migrations.

## Endpoints

| Path        | Method | Behavior |
| ----------- | ------ | -------- |
| `/healthz`  | GET    | Liveness — 200 if the process is up. Does not touch the DB. |
| `/readyz`   | GET    | Readiness — 200 if `pool.Ping` succeeds within 2s, 503 otherwise. |

## Configuration

| Env var         | Required | Default     | Notes |
| --------------- | -------- | ----------- | ----- |
| `DATABASE_URL`  | yes      | —           | Standard libpq-style URL (`postgres://user:pass@host:port/db?sslmode=disable`). |
| `HTTP_ADDR`     | no       | `:8080`     | Listen address. |
| `LOG_LEVEL`     | no       | `info`      | Reserved for future slog level wiring. |

## Tests

`make -C server test` runs every test under `./...`. Tests that require a
real Postgres connection (currently `internal/db`) skip when
`TEST_DATABASE_URL` is not set; the `make test` target sets it from
`infra/.env`.

## Migrations

Goose is installed as a Go tool via the `tool` directive in `go.mod`.
There is no separate binary to install — `go tool goose` resolves to the
pinned version. Migrations live in `db/migrations/` and follow goose's
`<seq>_<name>.sql` naming.
