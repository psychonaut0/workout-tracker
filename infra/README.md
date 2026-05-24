# infra/

Local-development and homelab deployment for the workout-tracker stack.
Today this contains only Postgres; PowerSync and the Go API join later.

All commands below run from the **repo root**.

## Prerequisites

- Docker Engine 24+ with the `compose` subcommand (Docker Compose v2)
- `psql` client on the host (for verification and manual queries)

## First-time setup

1. Copy the env template and edit values:

       cp infra/.env.example infra/.env
       # edit infra/.env — at minimum, set POSTGRES_PASSWORD to something local

2. Start the stack:

       docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d

3. Verify it's healthy:

       docker inspect --format='{{.State.Health.Status}}' workout-tracker-postgres-1

   Output should be `healthy` within ~10 seconds of `up`.

4. Connect with psql:

       set -a && . infra/.env && set +a
       PGPASSWORD="$POSTGRES_PASSWORD" \
         psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB"

## Useful commands

| Command | What it does |
| ------- | ------------ |
| `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d`        | Start in background |
| `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env down`         | Stop (data preserved in named volume) |
| `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env down -v`      | Stop AND delete the volume (destructive) |
| `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env logs -f postgres` | Tail Postgres logs |

## Files

- `compose.yml` — production-shaped base; no host ports exposed.
- `compose.dev.yml` — local-only override; exposes Postgres on `localhost:5432`.
- `.env.example` — copy to `.env` and fill in. **`.env` is gitignored — never commit real credentials.**

## Why `wal_level=logical`?

PowerSync replicates Postgres → SQLite via logical replication. Setting
`wal_level=logical` and reserving replication slots from day one means we
don't need to restart Postgres with a different config or rebuild the
named volume when PowerSync is wired in.

## Troubleshooting

- **Container restarts in a loop on first boot.** Usually a stale named
  volume mismatched with the image version. `docker compose ... down -v`
  to wipe (destructive — drops local data) and retry.
- **`psql: could not connect`.** Check that `compose.dev.yml` is included
  in the `-f` chain. Without it, the host port is not published.
- **Healthcheck never goes healthy.** Check `docker compose ... logs postgres`
  for permission errors on the data volume — common with rootless Docker.
