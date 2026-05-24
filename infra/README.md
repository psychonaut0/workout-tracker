# infra/

Local-development and homelab deployment for the workout-tracker stack.
Today this contains only Postgres; PowerSync and the Go API are added in
Plans 2–4.

## Prerequisites

- Docker Engine 24+ with the `compose` subcommand (Docker Compose v2)
- `psql` client on the host (for verification and manual queries)

## First-time setup

1. Copy the env template and edit values:

       cp infra/.env.example infra/.env
       # edit infra/.env — at minimum, set POSTGRES_PASSWORD to something local

2. Start the stack:

       cd infra
       docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d

3. Verify it's healthy:

       docker inspect --format='{{.State.Health.Status}}' workout-tracker-postgres-1

   Output should be `healthy` within ~10 seconds of `up`.

4. Connect with psql:

       set -a && . .env && set +a
       PGPASSWORD="$POSTGRES_PASSWORD" \
         psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB"

## Useful commands

| Command | What it does |
| ------- | ------------ |
| `docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d`        | Start in background |
| `docker compose -f compose.yml -f compose.dev.yml --env-file .env down`         | Stop (data preserved in named volume) |
| `docker compose -f compose.yml -f compose.dev.yml --env-file .env down -v`      | Stop AND delete the volume (destructive) |
| `docker compose -f compose.yml -f compose.dev.yml --env-file .env logs -f postgres` | Tail Postgres logs |

## Files

- `compose.yml` — production-shaped base; no host ports exposed.
- `compose.dev.yml` — local-only override; exposes Postgres on `localhost:5432`.
- `.env.example` — copy to `.env` and fill in. **`.env` is gitignored — never commit real credentials.**

## Why `wal_level=logical`?

PowerSync (added in Plan 4) replicates Postgres → SQLite via logical
replication. Setting `wal_level=logical` and reserving replication slots
from day one means Plan 4 doesn't need to restart Postgres with a
different config or rebuild the named volume.

## Troubleshooting

- **Container restarts in a loop on first boot.** Usually a stale named
  volume mismatched with the image version. `docker compose ... down -v`
  to wipe (destructive — drops local data) and retry.
- **`psql: could not connect`.** Check that `compose.dev.yml` is included
  in the `-f` chain. Without it, the host port is not published.
- **Healthcheck never goes healthy.** Check `docker compose ... logs postgres`
  for permission errors on the data volume — common with rootless Docker.
