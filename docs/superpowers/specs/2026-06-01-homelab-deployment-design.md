# Homelab Deployment (ct-workout) — design

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** Deploy the workout-tracker backend (Go API + app Postgres + PowerSync service + PowerSync-storage Postgres) as an always-on self-hosted service on the homelab, following the homelab's established conventions, so the phone syncs without this laptop running. Reachable on-LAN and remotely over Tailscale via `.lan` Caddy hostnames.

**Spans two repos:** `personal/projects/workout-tracker` (app/server source + GHCR image) and `personal/infra` (the `ct-workout` stack + deploy/backup/DNS wiring). The infra repo's conventions are authoritative (see `personal/infra/CLAUDE.md`).

**Safety:** Per `personal/ops/CLAUDE.md`, every destructive/remote action (CT creation, service start, DNS change, firewall) is confirmed with the user before execution. Read-only checks (status, next-free VMID/IP) are fine to run first.

## Decisions (locked)
- **Server image:** GHCR — build + push `ghcr.io/psychonaut0/workout-tracker-server:<sha>` and reference it by tag in the stack (portfolio pattern; infra repo holds deploy config only). Manual build/push for this first deploy; CI/CD automation is a separate later goal. Postgres + PowerSync use their existing public images.
- **Data:** Fresh homelab DB. No dump/restore. The user registers a fresh account on the homelab; the phone's local data uploads via Spec B's "keep my data" merge. (The dev `me@example.com` account is not carried over.)
- **Reachability:** `.lan` Caddy hostnames (private), reachable on-LAN and over Tailscale (the user's phone already resolves `.lan` over the tailnet). No public/internet exposure, no Cloudflare Tunnel.

## Target architecture
A new Proxmox LXC `ct-workout` on the cluster runs the 4-service Docker Compose stack at `/opt/stacks/ct-workout/`, with a local copy committed at `personal/infra/stacks/ct-workout/`. Caddy (on ct-mgmt) reverse-proxies two `.lan` names to it; Pi-hole resolves them. The app's API and the PowerSync endpoint are distinct URLs:
- `http://workout.lan` → `ct-workout:8080` (Go API; the app's `apiBaseUrl`).
- `http://workout-sync.lan` → `ct-workout:8090` (PowerSync service; the `POWERSYNC_URL` the server returns to clients).

## Components / changes

### A. New stack — `personal/infra/stacks/ct-workout/`
- **`docker-compose.yml`** — adapted from `workout-tracker/infra/compose.yml`:
  - `server`: replace `build: {context: ../server}` with `image: ghcr.io/psychonaut0/workout-tracker-server:<sha>`; keep the JWT file-secret (`/run/secrets/jwt_private_key`), `DATABASE_URL`, `POWERSYNC_URL=${POWERSYNC_URL}`, `user: ${SERVER_UID}:${SERVER_GID}`; **publish `8080`** on the CT.
  - `postgres` (app DB) + `powersync-storage` (bucket DB): unchanged images, named volumes `postgres_data` / `powersync_storage_data`, `restart: unless-stopped`, healthchecks.
  - `powersync`: `journeyapps/powersync-service:1.21.0`, config bind-mount `./powersync:/config:ro`, **publish `8090`** on the CT.
  - add a `portainer-agent` sidecar (port 9001) per the homelab norm.
- **`.env.example`** — template mirroring `workout-tracker/infra/.env.example`, with `POWERSYNC_URL=http://workout-sync.lan` and a note that the real `.env` lives at `/opt/stacks/ct-workout/.env` (gitignored, backed up by ct-backup).
- **`powersync/powersync.yaml`** — copied from `workout-tracker/powersync/`.
- **`README.md`** — deploy notes: GHCR tag bump = roll forward; the one-time `powersync_role` replication-user SQL (from `server/README.md`); the two backup PG dumps.

### B. Infra repo wiring
- **`stacks/hosts.yaml`** + re-snapshot **`cli/internal/discover/fleet.json`** — register `ct-workout` + its IP (so `infra deploy/status/logs ct-workout` work).
- **`stacks/ct-backup/scripts/pre-backup.sh`** — add `[ct-workout]=<ip>` to `CT_IPS`; add `pg-dump-workout` (app DB) and `pg-dump-powersync` (storage DB) SSH subcommands in `backup-dispatch.sh` and invoke them in the dump stage; create `/etc/backup-dispatch.conf` on ct-workout. (`.env` capture is automatic for every CT.)
- **DNS/Caddy** via `infra dns add workout.lan http://<ct-ip>:8080` and `infra dns add workout-sync.lan http://<ct-ip>:8090` — appends Caddy blocks on ct-mgmt + Pi-hole records.

### C. GHCR image (workout-tracker repo)
- Build `ghcr.io/psychonaut0/workout-tracker-server:<sha>` from `server/Dockerfile`; push (requires a GH token with `packages:write`). Pin the `:sha-<short>` tag in `ct-workout`'s compose. (CI to auto-build on release is deferred.)

### D. Server provisioning (remote — each step confirmed with the user)
1. **Create LXC `ct-workout`** on Proxmox. *VMID + IP confirmed with the user first (Explore-agent guess 117 / `192.168.3.17` is unverified).* Debian 13 unprivileged; **2 vCPU / 2 GB RAM / 16 GB disk** (revisit if PowerSync + 2 Postgres need more); AppArmor unconfined + proc/sys rw for Docker-in-LXC.
2. `scripts/bootstrap-ct.sh ct-workout` — installs Docker + copies the stack to `/opt/stacks/ct-workout/`.
3. Place the real `.env` (fresh random secrets) + generate the JWT private key on the CT (owned by `SERVER_UID`, mode 0600).
4. One-time DB step: create the `powersync_role` replication user + password on the app Postgres (per `server/README.md`).
5. `docker compose up -d` — the Go server runs goose migrations on startup; PowerSync replicates.
6. `infra dns add` the two `.lan` names; verify: API health on `workout.lan`, PowerSync liveness on `workout-sync.lan`, and a `/auth/register` smoke.

### E. Client change (workout-tracker app)
- Add `.lan` (includeSubdomains) to `app/android/app/src/main/res/xml/network_security_config.xml` cleartext allow (traffic is WireGuard-encrypted over Tailscale; plain on-LAN). Rebuild + install the APK.
- In-app: set the server URL to `http://workout.lan`, sign in / register; Spec B's keep-my-data uploads the phone's local data to the fresh homelab DB.

## Data flow (first real use)
Phone (local data) → Profile → set server URL `http://workout.lan` → register/sign-in → Spec B keep-my-data → upload queue flushes to `ct-workout` Go API (slug-suffix + savepoint keep it clean) → app Postgres → PowerSync replicates → `POWERSYNC_URL=http://workout-sync.lan` streams back to the phone. Subsequent syncs work on-LAN and over Tailscale, independent of this laptop.

## Error handling / rollback
- GHCR image rollback = pin a previous `:sha-` tag and `infra deploy ct-workout`.
- Fresh DB means a failed first sync loses nothing server-side; the phone retains its local data and retries.
- CT is disposable: destroy + recreate from the committed stack + `.env` from ct-backup.

## Verification / success criteria
1. `ct-workout` runs all 4 services healthy (`infra status ct-workout` / Portainer / Gatus).
2. `http://workout.lan` serves the API (health + `/auth/register` 400/200) and `http://workout-sync.lan` serves PowerSync liveness — from LAN **and** from the phone over Tailscale.
3. The phone, pointed at `http://workout.lan`, registers + syncs; data lands in the homelab app Postgres; a second device/session sees it.
4. `ct-workout` is registered in `infra` discovery, DNS, and ct-backup (both DB dumps appear in the next backup).
5. This laptop's dev stack is no longer required for the phone to sync.

## Out of scope (separate efforts)
- CI/CD to auto-build/push the GHCR image on release (the standing CI/CD goal).
- Public internet exposure / Cloudflare Tunnel / TLS certs (Tailscale + `.lan` only).
- Migrating dev data; multi-user hardening; the app rename.
- Gatus check definitions tuning beyond basic up/down (basic registration only).

## Confirm-before-provisioning (explicit unknowns)
- Exact next-free **VMID** and **IP** on `192.168.3.x` (verify read-only against Proxmox / inventory; confirm with user).
- That the phone resolves `.lan` over Tailscale via the existing subnet-router + Pi-hole path (user states it works; confirm the `POWERSYNC_URL` host matches).
- Resource sizing (2 vCPU / 2 GB) is a starting point; confirm against the cluster's headroom.
