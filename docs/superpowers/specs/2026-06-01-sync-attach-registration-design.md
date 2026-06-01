# Sync Attach + Registration (Spec B) — design

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** Let a standalone (local-first, Spec A) install **connect a server later** without losing data, and let users **register new accounts**. Fixes the two bugs found on-device when a standalone install first connected. Approach **X (build on the current synced-table storage)** — chosen over PowerSync's local-only-tables pattern because Spec A already ships on synced tables with real data on-device, so the local-only retrofit's migration + schema-switch cost outweighs its dedupe elegance for a single-user app.

**Builds on:** Spec A (`docs/superpowers/specs/2026-06-01-local-first-standalone-design.md`). Bug context: `project_sync_attach_bugs_for_spec_b` (memory).

## Problem

A standalone install accumulates local data (a generated `currentUserId`, optionally 24 seeded exercises, logged sessions). When it first connects a server, two bugs surface (observed on-device 2026-06-01):
1. **Upload batch-poisoning:** `server/internal/api/sync_upload.go` runs the whole upload batch in ONE pgx transaction (`Begin` ~:64 → `for op := range req.Batch` ~:75 → single `Commit` ~:107). One constraint violation aborts the transaction; the skip-on-error loop keeps going but every later op fails `SQLSTATE 25P02`, the `Commit` fails (503), and PowerSync retries the batch forever. The "log & skip bad op, never 4xx" contract is silently defeated by any one bad op.
2. **Seed↔template slug collision:** the client starter seed (`app/lib/data/catalog_seed.dart`) reuses the exact slugs of the server's template exercises (both from migration `00005`). The `exercises` table has a global `UNIQUE(slug)` (`exercises_slug_key`), so a seeded exercise collides on upload (triggering bug 1).

There is also **no registration** endpoint today (only login/refresh/logout), and **no UI/flow** to merge local data with a server on first connect.

## Assumed PowerSync model (validated by the B0 spike before B2/B3 are built)

- The app writes to **synced** tables; offline writes accumulate in the PowerSync upload queue (`ps_crud`).
- On `connect()`, PowerSync calls the connector's `uploadData` to flush the queue to the backend; the server stamps ownership (`user_id`/`created_by`) from the JWT.
- Server-accepted rows round-trip back via bucket download; server-skipped rows are reconciled away locally on the next checkpoint.
- Merge is therefore **additive**: local writes (fresh UUID ids) upload and add to whatever the account already has — there are no hard id conflicts, only potential duplication.
- `disconnectAndClear()` wipes local synced data (used for "use the account's data").

**If the spike contradicts this model, the plan is adjusted before B2/B3 proceed.**

## Components

### B0 — PowerSync attach spike (first implementation task)
A throwaway experiment, not shipped code: on a standalone install with local data, enable sync against the dev backend and observe (a) the offline queue flushing on connect, (b) server-accepted rows round-tripping, (c) `disconnectAndClear` discarding local cleanly, (d) what happens to a slug-colliding exercise once B1 is in place. Write findings into the plan; if the assumed model is wrong, revise B2/B3.

### B1 — Server upload batch-poisoning fix
In `server/internal/api/sync_upload.go`, wrap each op application in a Postgres `SAVEPOINT`:
- Before each op: `SAVEPOINT op`.
- Op succeeds → `RELEASE SAVEPOINT op`.
- Op fails (non-transient) → `ROLLBACK TO SAVEPOINT op`, then log + skip (existing behavior) — the outer transaction stays healthy so remaining ops and the final `Commit` succeed.
- Transient errors keep the existing 503-retry behavior.
This makes the documented skip-bad-op contract actually hold. Independent and shippable alone.

### B2 — Registration
- **Server:** new `POST /auth/register` — validate email (format) + password (min length, e.g. 8), bcrypt-hash (same cost as login), `INSERT INTO users`; on `UNIQUE(email)` violation return a clean 4xx ("email already registered"); on success reuse `issueTokens` (same token response as login).
- **Client:** a "Create account" path on the `LoginScreen` (reached via Profile → "Sign in to sync"). Same email/password fields; on success it behaves like sign-in: `setServerUrl` + `setSyncEnabled(true)` + `connectSync`.
- Registering from a standalone install with local data → the offline queue uploads into the brand-new (empty) account: a clean push-up, no reconciliation prompt needed.

### B3 — Sync attach / reconciliation
- **First sign-in flow:** after authenticating and an initial sync settling, determine whether the account already has user data (e.g. any synced `sessions`/`exercises` owned by the user).
  - **Account empty/new** → keep local automatically (the queue uploads; no prompt).
  - **Account already has data** → prompt: **"Keep my data"** (enable sync; queue uploads + merges — additive) vs **"Use the account's data"** (`disconnectAndClear` → download remote only, discard local).
- **Slug-collision fix (server):** in `applyExercise` (PUT), if inserting the client's row violates `exercises_slug_key`, retry the insert with a suffixed slug (`<slug>-<id8>`) so the row inserts under the **client's id** (sessions referencing it stay valid) and the existing template/exercise is untouched. Runs inside B1's per-op savepoint.
- **Catalog de-duplication (client):** in `watchCatalog`, hide a synced **template** exercise when the user already owns a non-template exercise with the same name, so the picker isn't doubled after attach. (If this proves noisy, it can be a follow-up — but it's in scope here.)

## Data flow (attach, the common single-user case)
Standalone (seeded + logged, local `currentUserId`) → Profile → "Sign in to sync"/"Create account" → authenticate → `setSyncEnabled(true)` + `connect()` → queue uploads: custom exercises insert as-is; seeded exercises insert with suffixed slugs (B1 keeps the batch alive); sessions/sets/bodyweight/targets insert stamped to the account → server-computed `is_top_set`/`is_pr` recompute and sync back → templates sync down but same-named ones are hidden by the client de-dup.

## Error handling
- B1: transient DB errors → 503 (client retries); constraint violations → per-op skip, batch still commits.
- B2: duplicate email → clean 4xx with a user-facing message; weak/invalid input → 4xx.
- B3: "use account's data" is destructive (wipes local) → confirm dialog. Auth/network failure during attach → stay local, surface an error, leave `syncEnabled` off.

## Testing
- Server: `register` (success, duplicate email, invalid input); upload **savepoint** behavior (a batch with one constraint-violating op still commits the rest — regression test for the 25P02 bug); `applyExercise` slug-suffix on collision.
- Client: register flow wiring; the keep-local vs use-remote decision logic (pure, testable); catalog de-dup filter (pure).
- The B0 spike is manual/observational, not an automated test.

## Out of scope
- Multi-device live conflict resolution beyond first-attach (additive merge is the model; no field-level merge).
- Migrating to PowerSync local-only tables (Option Y — explicitly rejected).
- Password reset / email verification / OAuth.
