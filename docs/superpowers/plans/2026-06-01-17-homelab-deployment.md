# Homelab Deployment (ct-workout) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (INLINE) — this plan does remote/destructive ops (Proxmox CT creation, service starts, DNS) that must be confirmed with the user step-by-step per `personal/ops/CLAUDE.md`. Do NOT autonomously subagent the Phase-2 remote tasks. Phase-1 repo tasks may be subagent'd. Steps use checkbox (`- [ ]`).

**Goal:** Run the workout backend as an always-on `ct-workout` LXC on the homelab (Go API + app Postgres + PowerSync + PowerSync-storage), reachable at `http://workout.lan` (API) and `http://workout-sync.lan` (PowerSync) on-LAN and over Tailscale, so the phone syncs without this laptop.

**Architecture:** Follow the homelab's conventions exactly: a new Proxmox LXC, Docker Compose stack committed at `personal/infra/stacks/ct-workout/`, GHCR image for the Go server (portfolio pattern), Caddy+Pi-hole `.lan` names via `infra dns add`, registered with `ct-backup` + Portainer. Fresh DB; the phone uploads its local data via Spec B keep-my-data.

**Tech Stack:** Proxmox LXC (Debian 13), Docker Compose, GHCR (`ghcr.io/psychonaut0/...`), the `infra` Go CLI, Caddy, Pi-hole, restic (ct-backup), Tailscale. Go server image from `server/Dockerfile`.

**Spec:** `docs/superpowers/specs/2026-06-01-homelab-deployment-design.md`. Infra conventions: `personal/infra/CLAUDE.md`. Safety: confirm every remote/destructive action.

**Repos:** `WT = /home/psy/Documents/personal/projects/workout-tracker`; `INFRA = /home/psy/Documents/personal/infra`.

**Branches:** `WT`: `homelab-deploy` (client edit only). `INFRA`: `add-ct-workout`.

---

## PHASE 1 — Repo artifacts (NO server touch; safe to do now)

### Task 1: Author the `ct-workout` stack in the infra repo

**Files (all under `INFRA/stacks/ct-workout/`):**
- Create: `docker-compose.yml`, `.env.example`, `powersync/powersync.yaml`, `powersync/sync-rules.yaml`, `README.md`

- [ ] **Step 1: Copy the PowerSync config verbatim**
```bash
mkdir -p /home/psy/Documents/personal/infra/stacks/ct-workout/powersync
cp /home/psy/Documents/personal/projects/workout-tracker/powersync/powersync.yaml \
   /home/psy/Documents/personal/projects/workout-tracker/powersync/sync-rules.yaml \
   /home/psy/Documents/personal/infra/stacks/ct-workout/powersync/
ls /home/psy/Documents/personal/infra/stacks/ct-workout/powersync/
```
Expected: `powersync.yaml  sync-rules.yaml`.

- [ ] **Step 2: Write `docker-compose.yml`**

Create `INFRA/stacks/ct-workout/docker-compose.yml` — the WT compose adapted: GHCR server image (no build), published host ports `8080` (API) + `8090→8080` (PowerSync), JWT secret path local to the stack dir, plus a `portainer-agent` sidecar. `<SERVER_IMAGE_TAG>` is the tag pushed in Task 2 (a real `sha-<short>` value — fill it in then):
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
    command: [postgres, -c, wal_level=logical, -c, max_wal_senders=10, -c, max_replication_slots=10]
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

  server:
    image: ghcr.io/psychonaut0/workout-tracker-server:<SERVER_IMAGE_TAG>
    restart: unless-stopped
    user: "${SERVER_UID:-1000}:${SERVER_GID:-1000}"
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable
      JWT_PRIVATE_KEY_PATH: /run/secrets/jwt_private_key
      POWERSYNC_URL: ${POWERSYNC_URL}
    secrets:
      - jwt_private_key
    healthcheck:
      test: ["CMD", "/server", "-healthcheck"]
      interval: 5s
      timeout: 5s
      retries: 10

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
    ports:
      - "8090:8080"
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
      - ./powersync:/config:ro
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:8080/probes/liveness').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 30s

  portainer-agent:
    image: portainer/agent:latest
    container_name: portainer-agent
    restart: unless-stopped
    ports:
      - "9001:9001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes

volumes:
  postgres_data:
  powersync_storage_data:

secrets:
  jwt_private_key:
    file: ./secrets/jwt_private_key.pem
```
Note the two changes from WT compose that matter: `secrets.jwt_private_key.file` is now `./secrets/jwt_private_key.pem` (relative to the stack dir on the CT — generated in Phase 2, gitignored), and the powersync config mount is `./powersync` (local to the stack).

- [ ] **Step 3: Write `.env.example`**

Create `INFRA/stacks/ct-workout/.env.example` (mirrors WT's, prod values):
```bash
# Copy to /opt/stacks/ct-workout/.env on the CT and fill with REAL random secrets.
# .env is gitignored; ct-backup captures it nightly.
POSTGRES_USER=workout
POSTGRES_PASSWORD=__SET_A_LONG_RANDOM__
POSTGRES_DB=workout_tracker

# Client-reachable PowerSync endpoint (phone via Caddy/.lan over Tailscale).
POWERSYNC_URL=http://workout-sync.lan

# uid:gid that owns ./secrets/jwt_private_key.pem (mode 0600) on the CT.
SERVER_UID=1000
SERVER_GID=1000

PS_REPLICATION_PASSWORD=__SET_A_LONG_RANDOM__
POWERSYNC_STORAGE_USER=powersync
POWERSYNC_STORAGE_PASSWORD=__SET_A_LONG_RANDOM__
POWERSYNC_STORAGE_DB=powersync_storage
PS_ADMIN_API_TOKEN=__SET_A_LONG_RANDOM__
```

- [ ] **Step 4: Write `README.md`**

Create `INFRA/stacks/ct-workout/README.md` documenting: GHCR image roll-forward/back (bump `:sha-` tag → `infra deploy ct-workout`); the one-time `powersync_role` replication-user SQL (below); that `.env` + `secrets/jwt_private_key.pem` are gitignored and captured by ct-backup; the two `.lan` names. Include the one-time SQL verbatim (from `WT/server/README.md` — read it and copy the exact `CREATE ROLE powersync_role ... ` + publication grant statements; if not present there, the canonical form is):
```sql
CREATE ROLE powersync_role WITH REPLICATION LOGIN PASSWORD '<PS_REPLICATION_PASSWORD>';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_role;
-- publication "powersync" is created by the app's goose migration 0004; verify it exists.
```
(READ `WT/server/README.md` for the project's exact wording and use that.)

- [ ] **Step 5: gitignore the secrets**

Ensure `INFRA/stacks/ct-workout/` secrets aren't committed. Check `INFRA/.gitignore` (root) covers `.env` + `secrets/`; if it doesn't already (most stacks rely on a root rule), add:
```
stacks/ct-workout/.env
stacks/ct-workout/secrets/
```
Verify: `git -C /home/psy/Documents/personal/infra status --porcelain stacks/ct-workout | grep -iE '\.env$|secrets/' || echo CLEAN` → `CLEAN` (only compose/.env.example/powersync/README staged).

- [ ] **Step 6: Commit (on INFRA branch `add-ct-workout`)**
```bash
cd /home/psy/Documents/personal/infra && git checkout -b add-ct-workout
git add stacks/ct-workout/docker-compose.yml stacks/ct-workout/.env.example stacks/ct-workout/powersync/ stacks/ct-workout/README.md .gitignore
git commit -m "feat(ct-workout): add workout-tracker stack (GHCR server + powersync)"
```

---

### Task 2: Build + push the GHCR server image

**Files:** none (produces a registry image + the tag for Task 1 Step 2).

- [ ] **Step 1: Confirm GHCR auth**
```bash
docker login ghcr.io -u psychonaut0   # needs a PAT with packages:write; skip if already logged in
```
If not logged in and no token available, STOP and ask the user to `docker login ghcr.io` (interactive) via `! docker login ghcr.io`.

- [ ] **Step 2: Build for amd64 (the Proxmox hosts are Intel) + tag with the git short SHA**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker/server
SHA=$(git rev-parse --short HEAD)
docker build --platform linux/amd64 -t ghcr.io/psychonaut0/workout-tracker-server:sha-$SHA -f Dockerfile .
echo "TAG=sha-$SHA"
```
Expected: build succeeds; note `sha-$SHA`.

- [ ] **Step 3: Push**
```bash
docker push ghcr.io/psychonaut0/workout-tracker-server:sha-$SHA
```
Expected: push completes. (Make the package visible/private as desired in GHCR settings; the CT pulls it — if private, the CT needs a pull token; if the user prefers, mark it private and we configure a CT pull secret in Phase 2. Default: ask the user whether to keep it private + provide a read token, or public.)

- [ ] **Step 4: Pin the tag in the stack**

Edit `INFRA/stacks/ct-workout/docker-compose.yml`: replace `<SERVER_IMAGE_TAG>` with `sha-<SHA>` from Step 2. Commit:
```bash
cd /home/psy/Documents/personal/infra
git add stacks/ct-workout/docker-compose.yml
git commit -m "feat(ct-workout): pin server image sha-<SHA>"
```

---

### Task 3: Wire `ct-workout` into infra discovery + backups

**Files (INFRA):** `stacks/hosts.yaml` (+ regenerate `cli/internal/discover/fleet.json`), `stacks/ct-backup/scripts/pre-backup.sh`, `stacks/ct-backup/scripts/backup-dispatch.sh`

> These edits use the CONFIRMED IP from Phase 2 Task 5. If running Phase 1 before the IP is fixed, use a placeholder and update in Task 5. READ each file first to match its exact format.

- [ ] **Step 1: Register the host**

In `INFRA/stacks/hosts.yaml`, add `ct-workout` with its IP, matching the file's existing entry format (read it first). Then regenerate the embedded fleet map the way the release workflow does:
```bash
cd /home/psy/Documents/personal/infra
go run ./cli/cmd/snapshot-services ./.. > cli/internal/discover/fleet.json 2>/dev/null || \
  echo "NOTE: match the exact snapshot command from .github/workflows/release.yml (it cd's into cli/ and runs ./cmd/snapshot-services ..)"
grep -n 'ct-workout' cli/internal/discover/fleet.json
```
Expected: `ct-workout` appears in `fleet.json` hosts (+ its services). (Match the real snapshot invocation from `release.yml` — read it; the path may differ.)

- [ ] **Step 2: Add the two Postgres dumps to backup-dispatch**

In `INFRA/stacks/ct-backup/scripts/backup-dispatch.sh` (READ it — it's an SSH forced-command dispatcher mapping a command name → an action), add two commands mirroring the existing `pg-dump-immich` pattern:
- `pg-dump-workout` → `docker exec <app-postgres-container> pg_dump -U workout workout_tracker | gzip` (match how `pg-dump-immich` names the container + creds; the app DB container will be `workout-tracker-postgres-1`).
- `pg-dump-powersync` → `docker exec <storage-container> pg_dump -U powersync powersync_storage | gzip` (container `workout-tracker-powersync-storage-1`).

- [ ] **Step 3: Register ct-workout in the backup run**

In `INFRA/stacks/ct-backup/scripts/pre-backup.sh`, add `[ct-workout]=<ip>` to the `CT_IPS` map, and invoke the two new dump commands in the database-dump stage (mirror how `pg-dump-immich` is invoked — read the stage). The `.env` capture is automatic.

- [ ] **Step 4: Commit**
```bash
cd /home/psy/Documents/personal/infra
git add stacks/hosts.yaml cli/internal/discover/fleet.json stacks/ct-backup/scripts/pre-backup.sh stacks/ct-backup/scripts/backup-dispatch.sh
git commit -m "feat(ct-workout): register in fleet discovery + nightly backups (2 PG dumps)"
```

---

### Task 4: Client — allow `.lan` cleartext + rebuild APK

**Files (WT):** `app/android/app/src/main/res/xml/network_security_config.xml`

- [ ] **Step 1: Add `.lan` to the cleartext allow**

On a new WT branch `homelab-deploy`, edit `network_security_config.xml`: add a `<domain includeSubdomains="true">lan</domain>` line inside the existing `<domain-config cleartextTrafficPermitted="true">` block (alongside `tail1552c5.ts.net`). Final block:
```xml
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">tail1552c5.ts.net</domain>
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
        <domain includeSubdomains="true">lan</domain>
    </domain-config>
```

- [ ] **Step 2: Verify + commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker && git checkout -b homelab-deploy
make -C app analyze 2>&1 | grep -iE 'no issues|error'   # config-only; expect "No issues found!"
git add app/android/app/src/main/res/xml/network_security_config.xml
git commit -m "feat(app): allow cleartext to .lan hosts (homelab over Tailscale)"
```

- [ ] **Step 3: Build the APK** (install happens in Phase 2 after the backend is up)
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk; export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
make -C app build-apk 2>&1 | tail -2
```
Expected: `app-debug.apk` built.

---

## PHASE 2 — Server provisioning (REMOTE — confirm EACH step with the user before running)

### Task 5: Determine VMID/IP + create the LXC `ct-workout`

- [ ] **Step 1 (read-only): find the next-free VMID + IP**

Confirm against Proxmox + inventory (read-only is allowed). Suggest to the user:
```bash
ssh proxmoxmain "pvesh get /cluster/nextid"          # next free VMID
ssh proxmoxmain "pct list; qm list"                  # in-use VMIDs
grep -nE '192\.168\.3\.' /home/psy/Documents/personal/infra/CLAUDE.md  # in-use IPs (pick a free one, e.g. .17)
```
Present the discovered VMID + a proposed free IP to the user; get explicit confirmation before creating anything.

- [ ] **Step 2 (CONFIRM → create): create the LXC**

With the user's confirmed VMID/IP, create a Debian 13 unprivileged LXC `ct-workout` (2 vCPU / 2 GB RAM / 16 GB disk) on `proxmoxmain`, with AppArmor unconfined + nesting for Docker (match how an existing unprivileged Docker CT, e.g. ct-portfolio, is configured — read its PCT config: `ssh proxmoxmain "pct config <ct-portfolio-vmid>"`). This is the one genuinely new resource — present the exact `pct create` command (template, rootfs, net0 with the confirmed IP, features `nesting=1`, AppArmor) to the user and run only on explicit approval.

- [ ] **Step 3: Confirm reachability + base packages**

`ssh ct-workout "cat /etc/os-release; nproc; free -m"` (after adding it to `.ssh/config` or via its IP). Confirm it's up.

---

### Task 6: Bootstrap Docker + deploy the stack (CONFIRM each)

- [ ] **Step 1: Bootstrap Docker + copy the stack** (run from proxmox/operator host per `bootstrap-ct.sh` usage — READ `INFRA/scripts/bootstrap-ct.sh` for exact invocation):
```bash
INFRA_REPO=/root/infra /root/infra/scripts/bootstrap-ct.sh ct-workout
```
(Ensure the INFRA `add-ct-workout` branch content is what's on the operator host, or sync the `stacks/ct-workout/` tree there first. Confirm with the user how their operator host gets the repo — likely a checkout at `/root/infra`.)

- [ ] **Step 2: Place real secrets on the CT**
```bash
# On ct-workout:
#  /opt/stacks/ct-workout/.env  ← copy .env.example, fill REAL long-random values
#  /opt/stacks/ct-workout/secrets/jwt_private_key.pem  ← generate the JWT key
```
Generate the JWT key the same way the project does (READ `WT/server/README.md` / `WT/server/Makefile` for the `gen-jwt-key` target — likely `openssl genpkey` RSA/EC). Set owner to `SERVER_UID:SERVER_GID` and `chmod 0600`. Present the exact commands; confirm before running.

- [ ] **Step 3: First `up` (app DB + server only) to run migrations**
```bash
# On ct-workout:
cd /opt/stacks/ct-workout && docker compose up -d postgres server
docker compose logs server | tail -20   # confirm goose migrations ran + JWKS endpoint up
```
Expected: server healthy; migrations applied (the publication `powersync` from migration 0004 now exists).

- [ ] **Step 4: One-time `powersync_role` SQL** (now that migrations created the publication):
```bash
# On ct-workout, against the app Postgres container, run the CREATE ROLE / GRANT
# statements from stacks/ct-workout/README.md, using PS_REPLICATION_PASSWORD from .env.
docker exec -i workout-tracker-postgres-1 psql -U workout -d workout_tracker -c "CREATE ROLE powersync_role WITH REPLICATION LOGIN PASSWORD '...';"
# + the GRANTs. Confirm the 'powersync' publication exists: \dRp
```
Confirm before running; present exact statements.

- [ ] **Step 5: Bring up the rest**
```bash
cd /opt/stacks/ct-workout && docker compose up -d
docker compose ps   # all 5 healthy: postgres, server, powersync-storage, powersync, portainer-agent
```
Expected: all healthy. Check `docker compose logs powersync | tail` for successful replication start.

---

### Task 7: DNS + reverse proxy + health verification

- [ ] **Step 1: Add the two `.lan` names** (CONFIRM — modifies Caddy + Pi-hole):
```bash
infra dns add workout.lan http://<ct-ip>:8080
infra dns add workout-sync.lan http://<ct-ip>:8090
infra dns ls | grep -i workout
```
Expected: both names resolve + Caddy blocks added.

- [ ] **Step 2: Verify from the LAN**
```bash
curl -s -w "\n%{http_code}\n" -X POST http://workout.lan/auth/register -H 'content-type: application/json' -d '{"email":"","password":""}'   # expect 400
curl -s -o /dev/null -w "powersync liveness: %{http_code}\n" http://workout-sync.lan/probes/liveness   # expect 200
```

- [ ] **Step 3: Verify from the phone over Tailscale** — the user opens a browser on the phone to `http://workout.lan/healthz` (or the register probe) and confirms it loads while NOT on home wifi (cellular + Tailscale). Confirms the `.lan`-over-Tailscale path.

---

### Task 8: On-device cutover + backup verification

- [ ] **Step 1: Install the Phase-1 APK** (`adb install -r .../app-debug.apk`) on the phone.
- [ ] **Step 2: Point the app at the homelab** — in Profile, set the server URL to `http://workout.lan`, then register a fresh account (or sign in). Spec B's keep-my-data prompt → uploads the phone's local data.
- [ ] **Step 3: Verify the round-trip server-side**
```bash
ssh ct-workout "docker exec workout-tracker-postgres-1 psql -U workout -d workout_tracker -At -c 'SELECT count(*) FROM exercises; SELECT count(*) FROM sessions;'"
```
Expected: the phone's exercises/sessions are now in the homelab DB.
- [ ] **Step 4: Verify backups pick it up** — trigger (or wait for) a ct-backup run and confirm `postgres.sql.gz` + `powersync-storage.sql.gz` for ct-workout appear in the restic staging/snapshot:
```bash
ssh ct-backup "ls -la /var/backup-staging/db/ct-workout/ 2>/dev/null || echo 'run pre-backup.sh first'"
```
- [ ] **Step 5: Merge both branches + push**
```bash
cd /home/psy/Documents/personal/infra && git checkout main && git merge --no-ff add-ct-workout && git push   # (confirm infra repo's default branch + remote)
cd /home/psy/Documents/personal/projects/workout-tracker && git checkout main && git merge --no-ff homelab-deploy && git push origin main
```

---

## Verification / success criteria
1. `infra status ct-workout` (or Portainer/Gatus) shows all 5 services healthy.
2. `http://workout.lan` (API) + `http://workout-sync.lan` (PowerSync liveness) reachable from LAN **and** phone over Tailscale.
3. Phone pointed at `http://workout.lan` registers + syncs; data lands in the homelab app Postgres.
4. ct-workout registered in `infra` discovery + DNS; both PG dumps appear in ct-backup.
5. Dev stack on this laptop no longer needed for the phone to sync.

## Deferred (out of scope)
CI/CD auto-build of the GHCR image (separate goal); public exposure / TLS; dev-data migration; the app rename; Gatus check tuning.
