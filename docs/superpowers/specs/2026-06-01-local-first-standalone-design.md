# Local-first standalone (Spec A) — design

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** Make the app a fully working **standalone local-first** app that needs no server. A PowerSync server becomes an *optional* add-on for sync/backup. This spec covers everything needed to use the app with zero network. Connecting a server *later* and reconciling data (registration, keep-local/keep-remote, auto-merge) is **Spec B — explicitly deferred** (captured at the end).

## Problem

Today the app cannot be used without a reachable backend:
- App entry is gated on `_loggedIn` (a saved refresh token), and the only way to get one is `POST $apiBaseUrl/auth/login` against a live server.
- The configurable server URL lives in Profile/Settings, which is **behind** the login gate — a chicken-and-egg loop: you can't log in without the right URL, and you can't set the URL without logging in.
- Identity comes *from the server*: the current `user_id` is read off a **synced** `sessions` row via `SessionRepository.anyUserId()`; on a never-synced install it returns `null`, so even the `muscle_targets` client seed is skipped and writes have no owner.
- The exercise catalog + default day templates are **server-seeded** (migrations `00005`, `00014`, `00019`) and only reach the client via sync, so a never-synced install is empty.

The local SQLite store itself is NOT the blocker — PowerSync is local-first and `openDatabase()` already works with no `connect()`. The blockers are the **login gate**, **server-derived identity**, and **server-only seed data**.

## Goals / success criteria

1. A fresh install launches, shows a one-time **onboarding** choice, and lands in a fully usable app **with no network and no login**.
2. All create/read/update/delete flows (sessions, exercises, bodyweight, targets, day templates) work offline against the local DB, owned by a **locally-generated identity**.
3. The **server URL is editable without logging in**; login becomes an optional action in Settings.
4. Existing installs that already have data/a session are **not orphaned** (identity continuity).
5. No regression: `flutter analyze` clean, existing tests pass, new logic unit-tested.

Non-goal for this spec: actually syncing to a server, registering accounts, or reconciling local vs remote data (all Spec B).

## Architecture

### 1. Local identity — `IdentityService`

A new small `ChangeNotifier`/service (shared_preferences-backed, sibling to `SettingsService`) owning:
- `String currentUserId` — the effective owner id for all local writes/queries.
- `bool onboardingComplete`.

**Initialization (in `main()` before `runApp`), in priority order:**
1. If a `currentUserId` is already persisted → use it.
2. Else if the install already has an identity to adopt — a remembered login or existing synced data (`SessionRepository.anyUserId()` returns non-null) → adopt that id and persist it (continuity for existing installs; also implies `onboardingComplete = true`).
3. Else → generate a new `uuid.v4()`, persist it. `onboardingComplete` stays false (fresh install → show onboarding).

Every site that currently calls `anyUserId()` to obtain the owner switches to `IdentityService.currentUserId`. `anyUserId()` may remain as the *adoption probe* in step 2 but is no longer the runtime identity source.

> **Why a single persisted local UUID** (chosen over always-generating-fresh, which would orphan existing rows; and over deferring identity to first-sync, which is the very thing we're removing): one stable owner id makes every local row self-consistent. When Spec B attaches a server, mapping this local id to the server account is B's job.

### 2. Onboarding + seeding

A first-launch screen (shown when `!onboardingComplete`) with two choices:
- **"Start empty"** → seed nothing; set `onboardingComplete = true`; enter the app.
- **"Add starter exercises"** → seed, then `onboardingComplete = true`, enter the app:
  - **24 exercises + traits**, ported from the server seed into a client-side Dart seed module (`lib/data/catalog_seed.dart`), sourced from migrations `00005_seed_template_exercises.sql` (names/slugs/muscles) + `00019_seed_exercise_traits.sql` (equip/compound/base_weight_kg/plate_step_kg/default_rep_low|high/default_warmup_sets/default_working_sets/default_rir_low|high). Inserted as the user's OWN rows: `created_by = currentUserId`, `is_template = 0` → fully editable/deletable.
  - **8 default muscle targets** via the existing `MuscleTargetRepository.seedDefaultsIfEmpty(currentUserId)`.
  - Day templates: **not** seeded (the user builds their own split).

Seeders are idempotent (insert only when the target table is empty), so a re-run / re-open never duplicates.

### 3. Login-optional bootstrap + settings-loop fix

`main()` flow becomes:
1. Load `SettingsService` + `UnitService` + `IdentityService`; set `apiBaseUrl = settings.serverUrl`.
2. `openDatabase()` (local, always).
3. `auth.load()`. If **sync is enabled** (a new `SettingsService.syncEnabled`, default false) **and** a remembered session exists → `connectSync(auth)`. Otherwise stay purely local.
4. `runApp`. Home routing: `!onboardingComplete` → `OnboardingScreen`; else → `AppShell` (local data).

The login gate is removed from app entry. `LoginScreen` and the auth/sync code stay intact but are reached from **Settings**: a "Sync & Backend" section that, when not connected, shows the **editable server URL + a Sign in / Enable sync action** (this is reachable without being logged in, which dissolves the loop). Signing in sets `syncEnabled = true` and calls `connectSync`. Sign-out keeps existing behaviour but returns to the local app (not a login wall).

### 4. Components / files

- **Create** `lib/identity/identity_service.dart` — `IdentityService` (currentUserId, onboardingComplete, init logic).
- **Create** `lib/data/catalog_seed.dart` — the 24-exercise starter data (const) + a `seedStarterCatalog(SqlExecutor, userId)` that inserts exercises (+ delegates muscle targets).
- **Create** `lib/ui/onboarding_screen.dart` — two-choice first-launch screen.
- **Modify** `lib/main.dart` — bootstrap (identity + onboarding routing + conditional connectSync).
- **Modify** `lib/settings/settings_service.dart` — add `syncEnabled` (persisted, default false).
- **Modify** call sites of `anyUserId()` for runtime ownership → `currentUserId` (e.g. the muscle-target seed call, Today/session write paths).
- **Modify** Settings/Profile UI — host login as optional; editable server URL pre-login.

### 5. Error handling / edge cases

- Zero-network is the *normal* path, not an error: no connect attempt unless `syncEnabled`.
- Seed idempotency guards against double-seed on re-open.
- Existing-install adoption (identity step 2) prevents orphaning prior data.
- `disconnectAndClear()` on sign-out wipes synced data — for Spec A (no sync) this path is only reachable if a server was connected; behaviour unchanged, but it must return to the **local app**, not a login wall.

### 6. Testing

- `IdentityService`: persists a generated id; reuses it on reload; adopts an existing id (mock probe returns non-null) and sets onboardingComplete; generates fresh when nothing present.
- `catalog_seed`: inserts exactly 24 exercises with correct traits + `created_by`/`is_template=0`; idempotent when non-empty; muscle targets seeded (8).
- Onboarding routing: `!onboardingComplete` → onboarding; complete → shell.
- Repos use `currentUserId` (not `anyUserId`) for writes.
- Existing suite stays green (97+).

## Spec B — deferred (captured, NOT in this spec)

Build only after Spec A lands; scope as its own spec (it is **not** small):
- **Registration flow** — new server endpoint to create users (backend has only login/refresh/logout today) + client UI.
- **First-login reconciliation** — on connecting a server: if local and remote data don't overlap → auto-merge (keep both); if they conflict/overlap → ask the user **keep local** or **keep remote**.
- **PowerSync attach spike** — verify how PowerSync uploads pre-existing local writes on first `connect()` and how the local `currentUserId` maps to the authenticated server `user_id` (server stamps ownership on upload). This determines whether attach-later is lossless. Must be spiked before B is planned.
