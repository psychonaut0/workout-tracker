# Plan 1 — Project Scaffold & Local Postgres Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the monorepo directory structure and a Dockerised Postgres 16 instance configured for PowerSync logical replication. End state: from a clean clone, `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d` brings up a healthy Postgres that the host can reach via `psql`, with `wal_level=logical` active so later plans can add PowerSync without rebuilding the volume.

**Architecture:** Polyglot monorepo (Dart/Go/TS) with per-language subdirectories under the repo root. Infrastructure (Docker Compose, env files, runbook) lives in `infra/`. Postgres runs as a single Compose service with a named volume for persistence, a healthcheck so future dependents can `depends_on: condition: service_healthy`, environment from a `.env` file, and `wal_level=logical` set from day one. A dev-only override file exposes Postgres on `localhost:5432` so the host can connect with `psql`.

**Tech Stack:** Docker, Docker Compose v2 (`compose` subcommand), Postgres 16.4 (Alpine image), `psql` client on the host.

**Spec sections covered:** Repo layout, Deployment → Local dev, Stack → Infra row, the "Postgres with `wal_level=logical`" requirement.

---

### Task 1: Monorepo directory skeleton

**Files:**
- Create: `app/README.md`
- Create: `web/README.md`
- Create: `server/README.md`
- Create: `api/README.md`
- Create: `powersync/README.md`
- Create: `infra/README.md` (placeholder; expanded in Task 5)
- Create: `docs/adr/.gitkeep`

- [ ] **Step 1: Create `app/README.md`**

Contents:

```markdown
# app/

Flutter (Dart) phone application. See `docs/superpowers/specs/2026-05-24-workout-tracker-stack-design.md` for the stack rationale and architecture.
```

- [ ] **Step 2: Create `web/README.md`**

Contents:

```markdown
# web/

Next.js (App Router) desktop review app. Stack: Next.js + Tailwind v4 + shadcn/ui + Recharts.
```

- [ ] **Step 3: Create `server/README.md`**

Contents:

```markdown
# server/

Go API (chi + sqlc). Handles auth, write endpoints, validation, and server-computed flags (top-set, PR).
```

- [ ] **Step 4: Create `api/README.md`**

Contents:

```markdown
# api/

OpenAPI 3.1 contract for the write API. Source of truth for Dart and TypeScript client codegen.
```

- [ ] **Step 5: Create `powersync/README.md`**

Contents:

```markdown
# powersync/

PowerSync self-hosted service configuration: sync rules and JWT trust settings. Added in Plan 4.
```

- [ ] **Step 6: Create `infra/README.md` placeholder**

Contents (this file is replaced in Task 5):

```markdown
# infra/

Docker Compose stack and local-dev tooling. Full runbook is added in Task 5 of Plan 1.
```

- [ ] **Step 7: Create `docs/adr/.gitkeep`**

Run:

```bash
mkdir -p docs/adr && touch docs/adr/.gitkeep
```

Expected: file exists, no output.

- [ ] **Step 8: Commit**

```bash
git add app/ web/ server/ api/ powersync/ infra/README.md docs/adr/
git commit -m "chore: monorepo directory skeleton"
```

Expected: one commit created, six new READMEs + one `.gitkeep`.

---

### Task 2: Postgres base compose service

**Files:**
- Create: `infra/compose.yml`
- Create: `infra/.env.example`

- [ ] **Step 1: Write `infra/.env.example`**

```bash
# Copy to infra/.env and fill in values for local development.
# .env is gitignored; never commit real credentials.

POSTGRES_USER=postgres
POSTGRES_PASSWORD=change-me-locally
POSTGRES_DB=workout_tracker
```

- [ ] **Step 2: Write `infra/compose.yml`**

```yaml
name: workout-tracker

services:
  postgres:
    image: postgres:16.4-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    command:
      - postgres
      - -c
      - wal_level=logical
      - -c
      - max_wal_senders=10
      - -c
      - max_replication_slots=10
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  postgres_data:
```

- [ ] **Step 3: Verify `.gitignore` already excludes `infra/.env`**

Run:

```bash
touch infra/.env && git check-ignore infra/.env
```

Expected output: `infra/.env` is printed (meaning it IS ignored). If nothing prints, the file is NOT ignored — fix `.gitignore` by adding `infra/.env` explicitly. (The existing `.gitignore` has `.env` and `.env.*` with `!.env.example`, so this should pass without changes.)

Clean up:

```bash
rm infra/.env
```

- [ ] **Step 4: Validate compose syntax**

Run:

```bash
cd infra && cp .env.example .env && docker compose --env-file .env config > /dev/null && echo OK
```

Expected: prints `OK`. (`infra/.env` is created from the example for the rest of the plan; it remains gitignored.)

- [ ] **Step 5: Commit**

```bash
git add infra/compose.yml infra/.env.example
git commit -m "infra: add Postgres 16 base compose service with logical replication"
```

Expected: one commit created with two files.

---

### Task 3: Dev-mode compose override (host port mapping)

**Files:**
- Create: `infra/compose.dev.yml`

- [ ] **Step 1: Write `infra/compose.dev.yml`**

```yaml
# Local-development overrides. Apply with:
#   docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d
# Exposes Postgres on the host so `psql` and local tooling can connect.

services:
  postgres:
    ports:
      - "5432:5432"
```

- [ ] **Step 2: Validate the merged config exposes the port**

Run:

```bash
cd infra && docker compose -f compose.yml -f compose.dev.yml --env-file .env config | grep -A2 "ports:"
```

Expected: output contains `- 5432:5432` (or the equivalent expanded form `target: 5432 / published: "5432"`).

- [ ] **Step 3: Commit**

```bash
git add infra/compose.dev.yml
git commit -m "infra: add dev-mode compose override exposing Postgres port"
```

---

### Task 4: Bring up Postgres and verify end-to-end

**Files:** none. This task is verification only — no source changes, no commit.

- [ ] **Step 1: Start the stack in detached mode**

Run:

```bash
cd infra && docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d
```

Expected: ends with `Container workout-tracker-postgres-1  Started` (or similar).

- [ ] **Step 2: Wait for `healthy`**

Run:

```bash
cd infra && for i in $(seq 1 20); do
  status=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-postgres-1 2>/dev/null || echo starting)
  echo "attempt $i: $status"
  [ "$status" = "healthy" ] && break
  sleep 2
done
```

Expected: within ~20 seconds, output ends with `attempt N: healthy`.

- [ ] **Step 3: Confirm `wal_level=logical` is active**

Run:

```bash
cd infra && set -a && . .env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SHOW wal_level;"
```

Expected: prints exactly `logical`.

- [ ] **Step 4: Confirm replication-slot config is in place**

Run:

```bash
cd infra && set -a && . .env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SHOW max_replication_slots;"
```

Expected: prints `10`.

- [ ] **Step 5: Confirm the target DB exists and is empty**

Run:

```bash
cd infra && set -a && . .env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"
```

Expected: `Did not find any relations.`

- [ ] **Step 6: Tear down (data persists in the named volume)**

Run:

```bash
cd infra && docker compose -f compose.yml -f compose.dev.yml --env-file .env down
```

Expected: containers stopped and removed; the `workout-tracker_postgres_data` volume is retained.

- [ ] **Step 7: Bring it back up to confirm persistence**

Run:

```bash
cd infra && docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d
# Wait for healthy (re-run the loop from Step 2 if needed)
sleep 8
set -a && . .env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1;"
```

Expected: prints `1`. The same named volume is reattached automatically — no schema/data loss between `down` and `up`.

- [ ] **Step 8: No commit (verification only)**

This task verifies behaviour; no source changes were made.

---

### Task 5: Runbook (`infra/README.md`)

**Files:**
- Modify: `infra/README.md` (replaces the placeholder from Task 1)

- [ ] **Step 1: Replace `infra/README.md` with the full runbook**

Full file contents (overwrite):

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add infra/README.md
git commit -m "docs(infra): add runbook for local Postgres compose stack"
```

---

## End-state verification

Run from the repo root:

```bash
# Files exist
test -f infra/compose.yml \
  && test -f infra/compose.dev.yml \
  && test -f infra/.env.example \
  && test -f infra/README.md \
  && echo "files OK"

# Directories exist
test -d app && test -d web && test -d server && test -d api \
  && test -d powersync && test -d docs/adr \
  && echo "dirs OK"

# Stack starts healthy
cd infra
[ -f .env ] || cp .env.example .env
docker compose -f compose.yml -f compose.dev.yml --env-file .env up -d
for i in $(seq 1 20); do
  status=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-postgres-1 2>/dev/null || echo starting)
  [ "$status" = "healthy" ] && break
  sleep 2
done
[ "$status" = "healthy" ] && echo "postgres OK"

# wal_level is logical
set -a && . .env && set +a
[ "$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'SHOW wal_level;')" = "logical" ] \
  && echo "wal_level OK"
```

Expected output (in order):

```
files OK
dirs OK
postgres OK
wal_level OK
```

If all four print, Plan 1 is complete. Proceed to Plan 2 (Go API foundations + migrations).
