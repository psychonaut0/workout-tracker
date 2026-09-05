# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Local DEV compose stack for Reps (production lives in the separate `personal/infra` repo as `stacks/ct-workout/` on the homelab — do not confuse the two).

## Usage

Always run from the repo root with BOTH compose files — `compose.yml` alone has no host port mappings, so a base-only `up` silently drops 8080/8090/5433 and "breaks" the dev backend:

```
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
```

Services: `postgres` (host **5433** — 5432 is occupied by an unrelated project; `wal_level=logical` for replication), `server` (8080), `powersync` (8090, `journeyapps/powersync-service`), `powersync-storage` (internal Postgres for bucket storage — no MongoDB).

## Gotchas

- `infra/.env` (gitignored) holds passwords plus `SERVER_UID`/`SERVER_GID` — compose bind-mounts the JWT key secret preserving host file ownership/mode, so the server container must run as the key's owner (`id -u`/`id -g`; secret long-syntax `uid/gid/mode` keys are swarm-only and ignored).
- The JWT signing key is a compose secret from `server/.secrets/jwt_private_key.pem` (`make -C server gen-jwt-key` if missing).
- The server self-migrates on boot (embedded goose) — no migration step in the runbook.
- PowerSync replication: migration-managed publication `powersync` + `powersync_role`; the PowerSync token audience must be `workout-tracker-powersync`.
- Full-stack runbook with verification steps: `infra/README.md`.
