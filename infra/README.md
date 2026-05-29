# infra/

Local-development and homelab deployment for the workout-tracker stack:
Postgres (application data), the Go API (`server`), PowerSync (sync service),
and a dedicated Postgres for PowerSync's bucket storage.

All commands below run from the **repo root**.

## Prerequisites

- Docker Engine 24+ with the `compose` subcommand (Docker Compose v2)
- Go 1.26+ (for migrations and the host dev server) and `psql` on the host

## First-time setup

1. Copy the env template and fill in values:

       cp infra/.env.example infra/.env
       # edit infra/.env — set local passwords; SERVER_UID/SERVER_GID to `id -u`/`id -g`

2. Generate the JWT signing key (used by the `server` container as a secret):

       make -C server gen-jwt-key

3. Start Postgres, apply migrations, create your user:

       docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d postgres
       make -C server migrate-up
       make -C server create-user EMAIL=me@example.com PASSWORD=yourpassword

4. Grant the PowerSync replication role LOGIN + password (one-time; see
   `server/README.md` → "PowerSync replication role"):

       set -a && . infra/.env && set +a
       PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
         --no-psqlrc -v ON_ERROR_STOP=1 \
         -c "ALTER ROLE powersync_role LOGIN PASSWORD '${PS_REPLICATION_PASSWORD}';"

5. Bring up the full stack:

       docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d

   Services: `postgres` (host 5433), `server` (host 8080), `powersync`
   (host 8090), `powersync-storage` (internal). The host `make -C server run`
   is an alternative to the `server` container for fast iteration — don't run
   both (they share port 8080).

## Validating the sync integration (no client needed)

       # Service healthy + probes (separate calls — curl applies -w once per URL)
       docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1
       curl -sS -o /dev/null -w "startup=%{http_code}\n" http://localhost:8090/probes/startup
       curl -sS -o /dev/null -w "liveness=%{http_code}\n" http://localhost:8090/probes/liveness

       # Replication slot active + publication present
       set -a && . infra/.env && set +a
       PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
         -c "SELECT slot_name, active FROM pg_replication_slots; SELECT pubname FROM pg_publication;"

       # JWT accepted + data syncs: mint a token via POST /auth/powersync-token,
       # then POST it to http://localhost:8090/sync/stream with header
       # 'Authorization: Token <jwt>' — a non-401 streaming response proves the
       # JWKS trust + token acceptance.

## Ports

| Service | Host | Container | Notes |
| ------- | ---- | --------- | ----- |
| postgres | 5433 | 5432 | 5433 to coexist with another local Postgres on 5432 |
| server | 8080 | 8080 | the Go API |
| powersync | 8090 | 8080 | the sync service |
| powersync-storage | — | 5432 | internal only |

## Notes

- `wal_level=logical` and replication slots are configured on `postgres` from
  the start, so no restart was needed when PowerSync joined.
- The endpoint the phone/web client uses to reach PowerSync is configurable
  (`POWERSYNC_URL`); the real value becomes an in-app server setting in the
  client apps. Over Tailscale the wire is already encrypted, so plain HTTP to
  the host's Tailscale address/port is acceptable.
- Secrets (`infra/.env`, `server/.secrets/`) are gitignored — never commit them.

## Troubleshooting

- **`powersync` unhealthy on first boot.** Check `docker compose … logs powersync`
  — a config-schema error names the exact key; a sync-rules error names the
  offending query; a replication error usually means the `powersync_role`
  password (step 4) doesn't match `PS_REPLICATION_PASSWORD`.
- **Sync stream returns 401.** The JWKS trust or token audience is off: confirm
  `powersync` can fetch `http://server:8080/.well-known/jwks.json` and that the
  token `aud` matches `client_auth.audience` (`workout-tracker-powersync`).
- **`psql: could not connect`.** Ensure `compose.dev.yml` is in the `-f` chain
  (it publishes Postgres on host 5433).
