# Workout Tracker — Stack & Architecture Design

**Date:** 2026-05-24
**Status:** Approved — ready for implementation planning.

## Context

Personal workout-logging app for tracking progressive overload (top working-set
weight per exercise, PRs, bodyweight trend). The primary use case is logging a
session on a phone at the gym — where cell/wifi connectivity is unreliable —
and reviewing trends on desktop. The app is self-hosted on the homelab and
reached via Tailscale. It is built like a real product (native phone,
production-grade sync, performance-first) and intended to run for the next
decade with minimal babysitting. Not a portfolio piece, not marketed.

Source-of-truth requirements live in `README.md`; this document captures the
architectural decisions that flow from those requirements.

## Goals

- **Offline-first on phone**: logging works mid-set with no network, always.
- **Single canonical source of truth**: data lives in homelab Postgres; phone
  has a synced subset.
- **Native-feel performance** on phone: smooth animations, instant feedback,
  low battery cost.
- **Built to last**: stable stack with clean separation, so the backend can
  outlive the frontends and vice versa.
- **Single-user today, multi-user-ready tomorrow**: no hardcoded assumptions
  that block adding accounts later.

## Non-goals

- Public/marketed product, App Store presence, or sign-up flow polish.
- Real-time multiplayer / live partner views.
- Wearable / HRV / sleep integration.
- Nutrition tracking (handled by the knowledge vault).

## Stack

| Layer        | Choice                                                        |
| ------------ | ------------------------------------------------------------- |
| Phone        | Flutter (Impeller) + Drift (SQLite) + Rive for animations     |
| Sync         | PowerSync, self-hosted in Docker                              |
| Backend      | Go + chi + sqlc + Postgres                                    |
| API contract | REST + OpenAPI 3.1 (hand-authored YAML), codegen for clients  |
| Web          | Next.js (App Router) + Tailwind v4 + shadcn/ui + Recharts     |
| Auth         | JWT issued by Go API; consumed by PowerSync via JWKS          |
| Infra        | Docker Compose on homelab + Tailscale; Postgres logical repl. |

### Why these choices (in one line each)

- **Flutter** — strongest perf-per-effort for native phone with rich
  animations; Impeller solves historical jank; Rive gives cheap
  state-machine-driven motion.
- **PowerSync** — production-grade Postgres↔SQLite sync with first-class
  Flutter SDK; Apache-2.0 self-hostable; we don't have to own the sync code.
- **Go + chi + sqlc** — single static binary that lives next to Postgres on
  the homelab with zero runtime drama; type-safe SQL via codegen, idiomatic
  Go, smallest possible deploy.
- **OpenAPI 3.1** — universal contract; mature Dart codegen (`dio`) and TS
  codegen (`openapi-typescript` / `orval`). Connect-RPC was tempting but
  `connect-dart` isn't mature enough to bet on yet.
- **Next.js + shadcn/ui + Tailwind v4** — code-owned components (you edit the
  files), CSS-variable theming for trivial restyles, Radix primitives for
  accessibility, Recharts for trend views (already proven in the knowledge
  vault export).

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Homelab (Tailscale only)                         │
│                                                                          │
│   ┌────────────────┐    ┌──────────────────────┐    ┌─────────────────┐  │
│   │  Postgres 16   │◀──▶│  PowerSync Service   │───▶│  Flutter app    │  │
│   │  wal_level=    │    │  (Docker)            │    │  Drift / SQLite │  │
│   │  logical       │    │  sync-rules.yaml     │    │                 │  │
│   └────────────────┘    └──────────────────────┘    └────────┬────────┘  │
│         ▲                                                    │           │
│         │  validated writes                                  │           │
│         │  + JWT issuance                                    │           │
│   ┌─────┴───────────────────────────┐                        │           │
│   │  Go API (chi + sqlc)            │◀───────────────────────┘           │
│   │  - /auth/*                      │                                    │
│   │  - /sessions, /sets, /weights   │◀──┐                                │
│   │  - /jwks (PowerSync trust)      │   │                                │
│   └─────────────────────────────────┘   │                                │
│                                         │                                │
│                                         │                                │
│                          ┌──────────────┴──────────┐                     │
│                          │  Next.js web (desktop)  │                     │
│                          │  reads via Go API       │                     │
│                          └─────────────────────────┘                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Repo layout

```
workout-tracker/
├── README.md
├── .gitignore
├── docs/
│   ├── superpowers/specs/         # design docs (this file lives here)
│   └── adr/                       # architecture decision records
├── api/
│   └── openapi.yaml               # single source of truth for the write API
├── app/                           # Flutter (Dart)
│   ├── pubspec.yaml
│   └── lib/
├── web/                           # Next.js (TypeScript)
│   ├── package.json
│   └── src/
├── server/                        # Go API
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── api/                   # chi handlers
│   │   ├── auth/                  # JWT issuance + JWKS endpoint
│   │   ├── db/                    # sqlc-generated code
│   │   └── domain/                # business logic (PR detection, top-set)
│   ├── db/queries/                # raw SQL (sqlc input)
│   ├── db/migrations/             # goose / atlas migrations
│   └── go.mod
├── powersync/
│   ├── sync-rules.yaml
│   └── README.md
└── infra/
    ├── compose.yml                # postgres + powersync + server
    ├── compose.dev.yml            # local-dev overrides
    └── README.md
```

Single polyglot monorepo. No top-level build orchestrator — each subdirectory
manages its own toolchain. CI runs per-directory pipelines that only fire on
relevant path changes.

## Data flow

### Write path (the critical one)

1. User logs a set on the phone → Flutter writes immediately to local Drift
   (SQLite). UI updates instantly. **This is the only step that has to work
   during a workout.**
2. PowerSync's Flutter client detects the local write and queues it as a
   pending upload.
3. When network is available, the PowerSync client POSTs the write to the
   **Go API** (not directly to the PowerSync service — PowerSync's documented
   pattern is that writes go through your app server so you can validate,
   compute derived fields, and enforce business rules).
4. Go API validates the write, computes `is_top_set` / `is_pr` if applicable,
   inserts into Postgres.
5. PowerSync service observes the Postgres change via logical replication and
   pushes it back to all connected clients (including the originating phone,
   idempotently — local rows reconcile by canonical `id`).

### Read path

- **Phone**: reads come from local SQLite via Drift queries. Reactive queries
  re-render the UI when PowerSync delivers new rows. No network round trip
  per read.
- **Web**: reads go straight to the Go API (no PowerSync on web — desktop has
  reliable connectivity and no offline requirement).

### Auth flow

1. User authenticates on phone (PIN/biometric over a stored credential) or
   web (login form) → POST `/auth/login` to Go API.
2. Go API returns:
   - A long-lived session JWT (refreshable) for use against the Go API.
   - A short-lived PowerSync JWT with `user_id` claim used by sync rules.
3. Phone stores both in platform secure storage (Keychain / Keystore).
4. PowerSync service validates JWTs against the Go API's JWKS endpoint
   (`/.well-known/jwks.json`).
5. Phone refreshes the PowerSync JWT before expiry; the session JWT survives
   longer with rotation.

## Data model (initial sketch)

```sql
users (
  id UUID PK,
  email TEXT UNIQUE,
  password_hash TEXT,
  created_at TIMESTAMPTZ
)

exercises (
  id UUID PK,
  name TEXT,
  slug TEXT UNIQUE,
  muscle_group TEXT,
  is_template BOOLEAN,     -- seeded template vs. user-created
  created_by UUID REFERENCES users(id) NULL,
  created_at TIMESTAMPTZ
)

sessions (
  id UUID PK,
  user_id UUID REFERENCES users(id),
  date DATE,
  split_label TEXT,        -- "Upper A", "Lower B", etc.
  notes TEXT,
  created_at TIMESTAMPTZ
)

sets (
  id UUID PK,
  session_id UUID REFERENCES sessions(id),
  exercise_id UUID REFERENCES exercises(id),
  set_number SMALLINT,
  weight_kg NUMERIC(6,2),
  reps SMALLINT,
  rir SMALLINT NULL,
  is_warmup BOOLEAN,
  is_top_set BOOLEAN,      -- computed server-side on insert
  is_pr BOOLEAN,           -- computed server-side on insert
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)

bodyweight_logs (
  id UUID PK,
  user_id UUID REFERENCES users(id),
  date DATE,
  weight_kg NUMERIC(5,2),
  created_at TIMESTAMPTZ
)
```

- Sets are **append-only in spirit**: editable for ~24h after `created_at`
  (soft rule enforced in the API; the schema allows updates so corrections
  remain possible via the desktop UI).
- `is_top_set` and `is_pr` are server-computed flags so trend queries stay
  fast (no per-read aggregation).
- Exercise table is seeded on first boot from the split documented in
  `README.md`.

## Error handling

| Layer        | Principle                                                                                                                                                |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phone        | Every action is optimistic. On sync failure, the row stays in local SQLite and PowerSync retries with backoff. **The user is never blocked on network.** |
| Go API       | Structured JSON errors `{ code, message, details }`. Never a stack trace in the response. 422 with field-level detail for validation failures.           |
| PowerSync    | Monitored: replication-slot lag + disk-fill alerts on Postgres are the only realistic failure modes.                                                     |
| Web          | React Query for fetching; show stale data + a "reconnecting" banner on transient failures rather than spinners.                                          |

## Testing strategy

| Layer    | Approach                                                                                                            |
| -------- | ------------------------------------------------------------------------------------------------------------------- |
| Go API   | Table-driven unit tests for handlers. Integration tests against a real Postgres in Docker via `testcontainers-go`.  |
| Flutter  | Widget tests for screens. Integration test suite covering the sync edge cases: offline-write, online-sync, edit-then-conflict. |
| Next.js  | Vitest + Testing Library for components. Playwright for critical journeys: log a session, view a trend.             |
| OpenAPI  | Spec is validated in CI; generated Dart + TS clients diff in PRs so contract drift is visible.                      |
| Sync     | Documented manual test plan exercising PowerSync's CLI rule-validator + a "fly to airplane mode and back" checklist. |

## Deployment

- **Local dev**: `docker compose -f infra/compose.yml -f infra/compose.dev.yml up`
  brings up Postgres + PowerSync + Go API. Flutter and Next.js run on host.
- **Homelab**: same compose stack lives on the existing homelab host, behind
  Tailscale only — no public exposure, no public DNS. Reverse-proxied through
  the existing homelab proxy for TLS.
- **Releases**:
  - Go API → static binary built in CI, copied into Docker image, restarted
    via `docker compose pull && up -d`.
  - Flutter → built locally; sideload via TestFlight (iOS, requires Apple
    Developer account) or direct APK install (Android).
  - Next.js → Node container in the compose stack.

## Bootstrapping order

Implementation will proceed roughly in this sequence; the writing-plans
session will refine it into discrete tasks.

1. `infra/compose.yml` running Postgres only — DB up.
2. `server/` skeleton: Go module, chi router, `/healthz`, sqlc wired,
   first migration committed.
3. `api/openapi.yaml` v0 with `/auth/*` endpoints.
4. Add PowerSync to compose; sync rules for `users` + `exercises` only.
5. `app/` Flutter skeleton: login screen, talks to Go API, validates
   end-to-end sync.
6. Seed `exercises` table from the README split.
7. Log-a-set flow end-to-end (phone → Postgres → phone sync-back).
8. `web/` Next.js skeleton: login, view trend for one exercise.
9. PR/top-set detection logic, charts, polish.

## Open questions (deferred to implementation plan)

- **Go migrations**: goose vs atlas vs golang-migrate.
- **Auth shape**: JWT-only vs JWT + httpOnly cookie for web; refresh-token
  rotation strategy.
- **iOS distribution**: TestFlight ($99/yr Apple Developer) vs Xcode-sideload
  (free, requires re-signing every 7 days).
- **Flutter charts**: `fl_chart` vs `syncfusion_flutter_charts`.
- **Drift schema migration cadence**: how to keep local SQLite schema in lock
  step with Postgres migrations without drift.

## Decision log

| # | Decision                              | Rationale                                                                                              |
| - | ------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1 | Phone = Flutter (not Expo)            | Native rendering pipeline + Rive give the smoothest animation story for the personal effort budget.    |
| 2 | Sync = PowerSync (not custom)         | "Scale big, done right" preference; PowerSync is the most mature self-hostable option for Flutter.     |
| 3 | Backend = Go + chi + sqlc             | Matches the homelab style (single static binary, set-and-forget). The write API is small.              |
| 4 | API = REST + OpenAPI (not Connect-RPC)| `connect-dart` is not yet mature enough to bet a decade-long project on. OpenAPI works everywhere.     |
| 5 | Web = Next.js + shadcn/ui + Tailwind  | Code-owned components → trivially restyleable; Radix primitives → accessible; Recharts → already proven. |
| 6 | Monorepo, no top-level build tool     | Polyglot stack (Dart/Go/TS); per-directory toolchains avoid premature meta-tooling.                    |
