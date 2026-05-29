# Plan 4b — PowerSync Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the self-hosted PowerSync service into the Docker Compose stack — replicating from the source Postgres, storing buckets in a dedicated Postgres, and trusting JWTs minted by the containerized Go API via its JWKS — and validate the integration without a Flutter client.

**Architecture:** Two new compose services join the `workout-tracker` stack from Plan 4a. `powersync-storage` is a dedicated `postgres:16.4-alpine` instance (own volume + creds) holding PowerSync's bucket/sync state, isolated from the application DB. `powersync` (`journeyapps/powersync-service:1.21.0`, unified mode) reads its config from the mounted `powersync/` dir: it connects to the source `postgres` over the in-cluster network as a least-privilege `powersync_role` (logical replication via a `powersync` publication), stores buckets in `powersync-storage`, and validates client JWTs by fetching the Go API's JWKS at `http://server:8080/.well-known/jwks.json`. A goose migration creates the publication + replication role. Validation is client-free: service probes, sync-rules compilation, replication-slot activity, and a JWT from `/auth/powersync-token` being accepted by the sync endpoint with a seeded template row visible.

**Tech Stack:** `journeyapps/powersync-service:1.21.0`, Postgres logical replication (publication `powersync`, `powersync_role`), Postgres bucket storage, goose migration `00004`, Docker Compose v2, the `!env` config tag, `curl` for validation.

**Spec sections covered:** Architecture → PowerSync sync layer (Postgres↔SQLite, sync rules by `request.user_id()`, JWKS trust); Deployment → homelab compose stack; the spec's PowerSync self-host requirement. Completes the Plan-4 split begun by Plan 4a (containerized API). The true Flutter local-write→upload→Postgres round-trip is **deferred to the app plan** — Plan 4b validates the download/auth path only.

---

## Decisions locked

| Topic | Decision |
| ----- | -------- |
| PowerSync image | `journeyapps/powersync-service:1.21.0`, unified mode (`command: ["start","-r","unified"]`). |
| Bucket storage | **Dedicated `powersync-storage` Postgres service** (own volume `powersync_storage_data`, own creds/db). `storage.type: postgresql`. (Your choice; not MongoDB, not co-located.) |
| Source connection | `postgres:5432` (in-cluster) as `powersync_role` (least-privilege). |
| Publication | `CREATE PUBLICATION powersync FOR TABLE exercises;` — name **must** be exactly `powersync`. Scoped to `exercises` (matches the sync rule); **never** `refresh_tokens` (token hashes must not enter the WAL stream). Add `users` only when a rule references it. |
| Replication role | `powersync_role` created `NOLOGIN REPLICATION BYPASSRLS` in the migration (no secret in git); `LOGIN` + `PASSWORD` set out-of-band from `PS_REPLICATION_PASSWORD`. |
| `allow_local_jwks` | **Dropped entirely** — not a real key in 1.21; local/plain-HTTP JWKS is allowed by default. Do NOT set `block_local_jwks`. |
| `jwks_uri` | `http://server:8080/.well-known/jwks.json` (in-cluster service DNS). |
| Sync-rules edition | Keep the existing legacy `bucket_definitions` form (fully supported on 1.21; also sidesteps the edition-3 sync-filter CVE class). |
| Migrations | Host-only via `make -C server migrate-up` (no compose one-shot migrate service). |
| Ports | `powersync` listens on `8080` internally (`PS_PORT=8080`); published on host **8090** in dev. `powersync-storage` is internal-only. |
| `POWERSYNC_URL` | Stays env-configurable; dev `http://localhost:8090` (set in Plan 4a). **No prod TLS/Tailscale-Serve task** — the real endpoint becomes an in-app server-config setting handled in the app/web plans. |

## Conventions in effect (from memory)

- Commands run from the **repo root**; `make -C server <target>` / explicit paths, no `cd`.
- Conventional Commits, standard types only, subject-line-only.
- No "Plan N" / "4b" literals in committed files; descriptive language.

## Schema-exactness note

The `powersync.yaml` below follows the verified PowerSync 1.21 config schema (top-level keys `replication`, `storage`, `port`, `sync_config`, `client_auth`, `api`, `telemetry`, `system`; `!env` tag for env injection). PowerSync validates its config and sync rules **on boot and logs errors**; Task 7's validation surfaces any schema mismatch immediately. If the service logs a config-schema error on first boot, adjust the offending key per the logged message (the service error names the exact path) and re-run — this is expected integration tuning, not a plan failure.

## File structure

```
server/db/migrations/00004_powersync_replication.sql   # NEW: publication + powersync_role
powersync/powersync.yaml                               # REWRITE: full 1.21 service config
powersync/sync-rules.yaml                              # unchanged (referenced by config)
infra/compose.yml                                      # MODIFY: + powersync-storage, + powersync, + volume
infra/compose.dev.yml                                  # MODIFY: publish powersync 8090
infra/.env.example                                     # MODIFY: + PS_* / storage creds (documented)
infra/README.md                                        # REWRITE: full-stack bring-up + validation runbook
server/README.md                                       # MODIFY: note the powersync_role one-time password step
```

---

### Task 1: Migration 0004 — publication + replication role

**Files:**
- Create: `server/db/migrations/00004_powersync_replication.sql`

- [ ] **Step 1: Write the migration**

File `server/db/migrations/00004_powersync_replication.sql`:

```sql
-- +goose Up
-- PowerSync logical-replication prerequisites. The publication name MUST be
-- exactly "powersync" (not configurable). Scoped to the tables PowerSync syncs
-- (currently only exercises); never publish refresh_tokens (token hashes must
-- not enter the WAL/replication stream). Add `users` here only when a sync rule
-- references it: ALTER PUBLICATION powersync ADD TABLE users;
CREATE PUBLICATION powersync FOR TABLE exercises;

-- Least-privilege role PowerSync connects as. Created NOLOGIN with no password
-- here (no secret in git); a one-time out-of-band step grants LOGIN + PASSWORD
-- from PS_REPLICATION_PASSWORD. REPLICATION is required for logical replication;
-- BYPASSRLS so row-level security never hides rows from the initial snapshot.
CREATE ROLE powersync_role WITH NOLOGIN REPLICATION BYPASSRLS;
GRANT CONNECT ON DATABASE workout_tracker TO powersync_role;
GRANT USAGE ON SCHEMA public TO powersync_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_role;

-- +goose Down
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM powersync_role;
REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM powersync_role;
REVOKE USAGE ON SCHEMA public FROM powersync_role;
REVOKE CONNECT ON DATABASE workout_tracker FROM powersync_role;
DROP ROLE IF EXISTS powersync_role;
DROP PUBLICATION IF EXISTS powersync;
```

Note: `GRANT CONNECT ON DATABASE workout_tracker` hardcodes the DB name. The dev DB is `workout_tracker` (from `infra/.env`); this matches.

- [ ] **Step 2: Apply and verify**

Run from repo root (Postgres up on 5433):

```bash
make -C server migrate-up
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT pubname FROM pg_publication; SELECT rolname, rolreplication, rolcanlogin FROM pg_roles WHERE rolname='powersync_role'; SELECT tablename FROM pg_publication_tables WHERE pubname='powersync';"
```

Expected: `migrate-up` prints `OK   00004_powersync_replication.sql`; the query shows publication `powersync`, role `powersync_role` with `rolreplication=t` and `rolcanlogin=f` (NOLOGIN until the out-of-band step), and `pg_publication_tables` lists exactly `exercises` (NOT `refresh_tokens`, NOT `users`).

- [ ] **Step 3: Verify rollback then re-apply**

```bash
make -C server migrate-down
make -C server migrate-up
make -C server migrate-status
```

Expected: down removes the publication + role; up recreates them; status shows all four migrations `Applied`.

- [ ] **Step 4: Commit**

```bash
git add server/db/migrations/00004_powersync_replication.sql
git commit -m "feat(server): migration 0004 — powersync publication and replication role"
```

(Em-dash `—` is U+2014.)

---

### Task 2: Env wiring + one-time replication-role password

**Files:**
- Modify: `infra/.env.example`
- Modify: `infra/.env` (local, gitignored)
- Modify: `server/README.md` (document the one-time step)

- [ ] **Step 1: Append the PowerSync env block to `infra/.env.example`**

```bash

# --- PowerSync (sync service) ---
# Password for the powersync_role replication user (set on the role via the
# one-time step in server/README.md; also used in the source connection URI).
PS_REPLICATION_PASSWORD=change-me-locally
# Dedicated bucket-storage Postgres credentials (its own container/db).
POWERSYNC_STORAGE_USER=powersync
POWERSYNC_STORAGE_PASSWORD=change-me-locally
POWERSYNC_STORAGE_DB=powersync_storage
# Admin API token for the PowerSync service's admin routes (any long random string).
PS_ADMIN_API_TOKEN=change-me-to-a-long-random-string
```

- [ ] **Step 2: Add the same keys to the local `infra/.env`**

Run from repo root (generates a real admin token; uses local dev passwords):

```bash
{
  echo ""
  echo "PS_REPLICATION_PASSWORD=ps-replication-local"
  echo "POWERSYNC_STORAGE_USER=powersync"
  echo "POWERSYNC_STORAGE_PASSWORD=ps-storage-local"
  echo "POWERSYNC_STORAGE_DB=powersync_storage"
  echo "PS_ADMIN_API_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 43)"
} >> infra/.env
echo "appended PowerSync env to infra/.env"
grep -c 'PS_REPLICATION_PASSWORD\|POWERSYNC_STORAGE_USER\|PS_ADMIN_API_TOKEN' infra/.env
```

Expected: prints `appended …` and `3`.

- [ ] **Step 3: Set the replication-role LOGIN + PASSWORD out-of-band**

Run from repo root (reads the password from the local `.env`; the password never lands in git):

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --no-psqlrc -v ON_ERROR_STOP=1 \
  -c "ALTER ROLE powersync_role LOGIN PASSWORD '${PS_REPLICATION_PASSWORD}';"
# Verify the role can now log in:
PGPASSWORD="$PS_REPLICATION_PASSWORD" psql -h localhost -p 5433 -U powersync_role -d "$POSTGRES_DB" -tAc "SELECT 'powersync_role can log in';"
```

Expected: `ALTER ROLE` succeeds; the second psql connects as `powersync_role` and prints `powersync_role can log in`.

- [ ] **Step 4: Document the one-time step in `server/README.md`**

Also bump the prerequisites line in `server/README.md` from `Go 1.24+` to `Go 1.26+` (it currently disagrees with `go.mod`'s `go 1.26.3` and the infra runbook). Then add a subsection under the migrations area (after the existing `## Migrations` section):

```markdown
## PowerSync replication role (one-time)

Migration `00004` creates the `powersync_role` as `NOLOGIN` with no password (no
secret in git). Grant it `LOGIN` + a password out-of-band, reading the value from
`infra/.env` so it never enters version control or shell history beyond this run:

    set -a && . infra/.env && set +a
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --no-psqlrc -v ON_ERROR_STOP=1 \
      -c "ALTER ROLE powersync_role LOGIN PASSWORD '${PS_REPLICATION_PASSWORD}';"

The PowerSync service connects to the source database as this role; its password
must match `PS_REPLICATION_PASSWORD` in `infra/.env`.
```

- [ ] **Step 5: Commit (NOT infra/.env)**

```bash
git add infra/.env.example server/README.md
git commit -m "docs(infra): PowerSync env vars and one-time replication-role password step"
```

Confirm `infra/.env` is not staged: `git status --short | grep -q 'infra/.env$' && echo "STAGED(BAD)" || echo "ok"`.

---

### Task 3: Rewrite `powersync/powersync.yaml` for the 1.21 service

**Files:**
- Modify: `powersync/powersync.yaml` (full rewrite — it is currently a config-only fragment)

- [ ] **Step 1: Replace `powersync/powersync.yaml`** with EXACTLY:

```yaml
# PowerSync self-hosted service config (journeyapps/powersync-service:1.21.0).
# Values are injected from the container environment via the !env tag.

# Source database: the application Postgres, reached in-cluster as powersync_role
# over logical replication (publication "powersync"). sslmode disable is fine on
# the private compose/Tailscale network.
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATA_SOURCE_URI
      sslmode: disable

# Bucket storage: the dedicated powersync-storage Postgres (separate from source).
storage:
  type: postgresql
  uri: !env PS_STORAGE_SOURCE_URI
  sslmode: disable

# Sync API HTTP port (container-internal).
port: !env PS_PORT

# Sync rules file, relative to this config's directory (/config).
sync_config:
  path: sync-rules.yaml

# Trust JWTs signed by the Go API. The token audience must be in this list, and
# the public key is fetched from the API's JWKS endpoint (plain-HTTP local URL is
# allowed by default in 1.21 — no allow_local_jwks / block_local_jwks needed).
client_auth:
  jwks_uri: !env PS_JWKS_URL
  audience:
    - workout-tracker-powersync

# Admin API auth (admin routes). Token supplied via env.
api:
  tokens:
    - !env PS_ADMIN_API_TOKEN

telemetry:
  disable_telemetry_sharing: true

system:
  logging:
    level: info
    format: json
```

- [ ] **Step 2: Validate YAML parses**

Run from repo root:

```bash
python3 -c "import yaml,sys
class L(yaml.SafeLoader): pass
L.add_constructor('!env', lambda loader,node: 'ENV:'+str(node.value))
d=yaml.load(open('powersync/powersync.yaml'), Loader=L)
assert set(['replication','storage','port','sync_config','client_auth','api','telemetry','system']) <= set(d.keys()), d.keys()
assert d['client_auth']['audience']==['workout-tracker-powersync']
assert 'allow_local_jwks' not in d['client_auth'] and 'block_local_jwks' not in d['client_auth']
print('powersync.yaml OK')"
```

Expected: prints `powersync.yaml OK` (the custom `!env` tag is handled by the test loader; the real service resolves it from the environment).

- [ ] **Step 3: Commit**

```bash
git add powersync/powersync.yaml
git commit -m "feat(powersync): full 1.21 service config (postgres storage, JWKS trust)"
```

---

### Task 4: Add `powersync-storage` + `powersync` compose services

**Files:**
- Modify: `infra/compose.yml`

- [ ] **Step 1: Add the two services + the storage volume to `infra/compose.yml`**

Add `powersync-storage` and `powersync` under `services:` (after `server`), and add `powersync_storage_data` to the top-level `volumes:`. The relevant additions:

```yaml
  powersync-storage:
    image: postgres:16.4-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POWERSYNC_STORAGE_USER}
      POSTGRES_PASSWORD: ${POWERSYNC_STORAGE_PASSWORD}
      POSTGRES_DB: ${POWERSYNC_STORAGE_DB}
    volumes:
      - powersync_storage_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POWERSYNC_STORAGE_USER} -d ${POWERSYNC_STORAGE_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

  powersync:
    image: journeyapps/powersync-service:1.21.0
    restart: unless-stopped
    command: ["start", "-r", "unified"]
    depends_on:
      postgres:
        condition: service_healthy
      powersync-storage:
        condition: service_healthy
      server:
        condition: service_healthy
    environment:
      POWERSYNC_CONFIG_PATH: /config/powersync.yaml
      PS_PORT: "8080"
      PS_DATA_SOURCE_URI: postgres://powersync_role:${PS_REPLICATION_PASSWORD}@postgres:5432/${POSTGRES_DB}
      PS_STORAGE_SOURCE_URI: postgres://${POWERSYNC_STORAGE_USER}:${POWERSYNC_STORAGE_PASSWORD}@powersync-storage:5432/${POWERSYNC_STORAGE_DB}
      PS_JWKS_URL: http://server:8080/.well-known/jwks.json
      PS_ADMIN_API_TOKEN: ${PS_ADMIN_API_TOKEN}
    volumes:
      - ../powersync:/config:ro
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:8080/probes/liveness').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 30s
```

And under the top-level `volumes:` block, add `powersync_storage_data:` alongside `postgres_data:`:

```yaml
volumes:
  postgres_data:
  powersync_storage_data:
```

- [ ] **Step 2: Validate the merged config**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env config >/dev/null && echo "compose config OK"
docker compose -f infra/compose.yml --env-file infra/.env config | grep -E 'image: journeyapps/powersync-service|PS_DATA_SOURCE_URI|powersync_storage_data' | head
```

Expected: `compose config OK`; the grep shows the pinned image, the resolved `PS_DATA_SOURCE_URI` (with the powersync_role password expanded), and the storage volume.

- [ ] **Step 3: Commit**

```bash
git add infra/compose.yml
git commit -m "feat(infra): add powersync and powersync-storage services"
```

---

### Task 5: Dev override — publish the PowerSync port

**Files:**
- Modify: `infra/compose.dev.yml`

- [ ] **Step 1: Add the `powersync` port publish to `infra/compose.dev.yml`**

The full file becomes:

```yaml
# Local-development overrides. Apply with:
#   docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d
# Exposes Postgres on the host so `psql` and local tooling can connect.
# Host port 5433 (not 5432) so this coexists with another local Postgres on 5432.

services:
  postgres:
    ports:
      - "5433:5432"

  server:
    ports:
      - "8080:8080"
    environment:
      POWERSYNC_URL: http://localhost:8090

  powersync:
    ports:
      - "8090:8080"
```

(`powersync-storage` stays internal — no host publish. The `server`'s dev `POWERSYNC_URL=http://localhost:8090` already matches the published PowerSync port.)

- [ ] **Step 2: Validate the merged dev config exposes 8090**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env config | grep -B2 'published: "8090"'
```

Expected: shows the `8090` host publish mapping to the powersync service's container port 8080.

- [ ] **Step 3: Commit**

```bash
git add infra/compose.dev.yml
git commit -m "feat(infra): publish PowerSync on host 8090 in dev"
```

---

### Task 6: Seed a verifiable row + bring the stack up

**Files:** none — operational, no commit (the seed row is data, not code).

- [ ] **Step 1: Build and bring up the full stack**

Run from repo root (the `powersync` image is large — the pull may take a few minutes):

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
```

Expected: `postgres`, `powersync-storage`, `server`, and `powersync` all created/started.

- [ ] **Step 2: Wait for powersync to become healthy**

Run from repo root:

```bash
for i in $(seq 1 30); do
  hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-powersync-1 2>/dev/null || echo none)
  echo "attempt $i: $hc"
  [ "$hc" = "healthy" ] && break
  sleep 5
done
```

Expected: reaches `healthy` (may take ~30–60s on first boot). If it stays `unhealthy`, jump to Task 7 Step 1 (logs) — a config-schema error will be named there.

- [ ] **Step 3: Seed a template exercise (visible to every user via the sync rule)**

Run from repo root:

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-psqlrc -v ON_ERROR_STOP=1 -c \
  "INSERT INTO exercises (name, slug, muscle_group, is_template) VALUES ('Validation Squat','validation-squat','quads',true) ON CONFLICT (slug) DO NOTHING;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT name FROM exercises WHERE slug='validation-squat';"
```

Expected: prints `Validation Squat`. (The sync rule `is_template = true` makes it appear for any authenticated user.)

- [ ] **Step 4: No commit (operational).**

---

### Task 7: Client-free validation suite

**Files:** none — verification only, no commit.

This proves the integration's download/auth path. The true Flutter local-write→upload round-trip is deferred to the app plan.

- [ ] **Step 1: Service started cleanly — replication connected + sync rules compiled**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env logs powersync 2>&1 | tail -40
```

Expected: logs show the service connecting to the source Postgres replication and loading/compiling sync rules with NO errors (look for replication-slot creation and a "sync rules" / "Replicating" style line). There must be no config-schema error and no JWKS error. If a config key is rejected, the log names the exact path — fix `powersync/powersync.yaml` and `docker compose ... up -d powersync` again (expected integration tuning).

- [ ] **Step 2: HTTP probes**

Run from repo root:

```bash
curl -sS -o /dev/null -w "startup=%{http_code}\n" http://localhost:8090/probes/startup
curl -sS -o /dev/null -w "liveness=%{http_code}\n" http://localhost:8090/probes/liveness
```

Expected: `startup=200` and `liveness=200`. (Do NOT probe `/probes/readiness` — it does not exist on this service.)

- [ ] **Step 3: Replication objects active on the source DB**

Run from repo root:

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5433 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT slot_name, plugin, active FROM pg_replication_slots; SELECT pubname FROM pg_publication WHERE pubname='powersync';"
```

Expected: at least one replication slot exists and is `active = t` (PowerSync created and is using it); the `powersync` publication is present.

- [ ] **Step 4: JWKS reachable from inside the powersync container**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env exec -T powersync \
  node -e "fetch('http://server:8080/.well-known/jwks.json').then(r=>r.json()).then(d=>{console.log('jwks keys:', d.keys.length, 'kid:', d.keys[0].kid.slice(0,12)); process.exit(0)}).catch(e=>{console.error(e); process.exit(1)})"
```

Expected: prints `jwks keys: 1 kid: …` — proving the in-cluster `server` DNS name resolves and the JWKS is served (the trust path PowerSync uses to validate tokens).

- [ ] **Step 5: KEYSTONE — a real token is accepted and the seeded row syncs**

Mint a PowerSync JWT via the Go API, then open a sync stream with it. A non-401 response proves JWKS trust + token acceptance; the seeded row in the stream proves data flows.

Run from repo root (the dev user `me@example.com`/`devpassword` exists; create it if not):

```bash
make -C server create-user EMAIL=me@example.com PASSWORD=devpassword 2>/dev/null || echo "(user exists)"
ACCESS=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"devpassword"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
PSTOKEN=$(curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
echo "got powersync token (len=${#PSTOKEN})"

# Open the sync stream. PowerSync accepts either "Token <jwt>" or "Bearer <jwt>"
# (parser regex /^(Token|Bearer) (\S+)$/); we use Token to match the official test client.
# A valid token returns a 200 streaming response; an invalid one returns 401.
# curl will hit --max-time on a successful stream (exit 28) after capturing the
# initial checkpoint + data lines, which is the success signal here.
CODE=$(curl -sS -o /tmp/wt-psync-stream.out -w "%{http_code}" --max-time 6 \
  -X POST http://localhost:8090/sync/stream \
  -H "Authorization: Token $PSTOKEN" -H 'Content-Type: application/json' \
  -d '{"raw_data": true, "buckets": []}' || true)
echo "sync/stream http_code=$CODE"
echo "--- stream head ---"; head -c 600 /tmp/wt-psync-stream.out; echo
grep -q 'Validation Squat\|validation-squat' /tmp/wt-psync-stream.out && echo "SEEDED ROW SYNCED OK" || echo "(row not seen in initial window — check diagnostics app)"
```

Expected: `http_code` is `200` (or the curl times out after streaming, which still means auth succeeded — NOT `401`); the stream head shows sync protocol lines (a checkpoint and data operations); and `SEEDED ROW SYNCED OK` prints (the `Validation Squat` template row reached the client stream). A `401` means JWKS trust/token failed — re-check Task 7 Step 4 and the `audience`/`jwks_uri` in `powersync.yaml`.

- [ ] **Step 6: (Optional) visual confirmation via the Diagnostics app**

For a visual check, run the PowerSync diagnostics app and paste the token + endpoint:

```bash
docker run --rm -p 8100:80 journeyapps/powersync-diagnostics-app:latest
# then open http://localhost:8100, set endpoint http://localhost:8090, paste the PSTOKEN, and confirm the exercises row appears.
```

Expected: the diagnostics UI connects and shows the synced `exercises` data. (Optional — the curl keystone above is the authoritative check.)

- [ ] **Step 7: No commit (verification only).**

---

### Task 8: Runbook update

**Files:**
- Modify: `infra/README.md` (full-stack bring-up + validation; closes the doc gap left after the API was containerized)

- [ ] **Step 1: Rewrite `infra/README.md`**

Replace `infra/README.md` with:

```markdown
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

       # JWT accepted + data syncs (see the plan's validation task for the full keystone curl)

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
  — a config-schema error names the exact key; a replication error usually means
  the `powersync_role` password (step 4) doesn't match `PS_REPLICATION_PASSWORD`.
- **Sync stream returns 401.** The JWKS trust or token audience is off: confirm
  `powersync` can fetch `http://server:8080/.well-known/jwks.json` and that the
  token `aud` matches `client_auth.audience` (`workout-tracker-powersync`).
- **`psql: could not connect`.** Ensure `compose.dev.yml` is in the `-f` chain
  (it publishes Postgres on host 5433).
```

- [ ] **Step 2: Commit**

```bash
git add infra/README.md
git commit -m "docs(infra): full-stack bring-up and sync validation runbook"
```

---

### Task 9: End-state verification

**Files:** none — verification only, no commit.

- [ ] **Step 1: Full stack healthy from a clean `up`**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
for s in postgres powersync-storage server powersync; do
  for i in $(seq 1 30); do
    hc=$(docker inspect --format='{{.State.Health.Status}}' "workout-tracker-$s-1" 2>/dev/null || echo none)
    [ "$hc" = "healthy" ] && break
    sleep 4
  done
  echo "$s: $hc"
done
```

Expected: all four services print `healthy`.

- [ ] **Step 2: Re-run the keystone (token accepted + row syncs)**

Run from repo root:

```bash
ACCESS=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"devpassword"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
PSTOKEN=$(curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
CODE=$(curl -sS -o /tmp/wt-psync-final.out -w "%{http_code}" --max-time 6 -X POST http://localhost:8090/sync/stream \
  -H "Authorization: Token $PSTOKEN" -H 'Content-Type: application/json' -d '{"raw_data": true, "buckets": []}' || true)
echo "sync/stream code=$CODE (200 or timeout = accepted; 401 = rejected)"
grep -q 'Validation Squat\|validation-squat' /tmp/wt-psync-final.out && echo "SEEDED ROW SYNCED OK"
```

Expected: code is not `401`; `SEEDED ROW SYNCED OK` prints.

- [ ] **Step 3: Confirm git state**

Run from repo root:

```bash
git status
git log --oneline main..HEAD
```

Expected: working tree clean; the log shows the commits from this plan:

```
docs(infra): full-stack bring-up and sync validation runbook
feat(infra): publish PowerSync on host 8090 in dev
feat(infra): add powersync and powersync-storage services
feat(powersync): full 1.21 service config (postgres storage, JWKS trust)
docs(infra): PowerSync env vars and one-time replication-role password step
feat(server): migration 0004 — powersync publication and replication role
```

(Six commits — Tasks 1–5 and 8 each produced one; Tasks 6, 7, 9 are operational/verification-only. `infra/.env` is NOT among the changes.)

- [ ] **Step 4: No commit (verification only)**

Plan 4b is complete. PowerSync is live in the stack: replicating `exercises` from the source Postgres, storing buckets in its dedicated Postgres, and accepting JWTs minted by the Go API. The next milestone is the Flutter app (Plan 5), which adds the client SDK, the local SQLite schema, and the true bidirectional sync round-trip (local write → uploadData → Postgres) that this plan deferred.
