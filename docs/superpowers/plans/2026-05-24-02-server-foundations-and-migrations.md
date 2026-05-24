# Plan 2 — Server Foundations & First Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Go HTTP server under `server/` exposing `/healthz` (liveness) and `/readyz` (DB-backed readiness), with `goose` migrations applying `users` and `exercises` tables to the Postgres from Plan 1. End state: from a clean clone, `make -C server migrate-up && make -C server run` brings up an API that responds 200 to both endpoints with the two tables in place.

**Architecture:** Single Go module at `server/` using chi for routing, pgx/v5 (pgxpool) for Postgres, slog (stdlib) for structured JSON logging, and goose (installed via Go 1.24's `tool` directive in `go.mod`) for migrations. Configuration is env-driven (`DATABASE_URL`, `HTTP_ADDR`, `LOG_LEVEL`). Code is organized so each package owns one concern: `internal/config` parses env, `internal/db` opens the pgxpool, `internal/api` exposes handlers and the router. Tests use stdlib `testing` + `net/http/httptest`; the DB connection test uses the existing dev Postgres from Plan 1, gated on `TEST_DATABASE_URL` so unit tests still run if it's down.

**Tech Stack:** Go 1.24 (for the `tool` directive), `github.com/go-chi/chi/v5`, `github.com/jackc/pgx/v5/pgxpool`, `github.com/pressly/goose/v3` (as a Go tool), stdlib `log/slog`, GNU Make, Postgres 16 from Plan 1.

**Spec sections covered:** Repo layout → `server/`, Stack → Backend row, Architecture → "Go API (chi + sqlc)" (sqlc deferred to Plan 3 — no queries exist yet), Data model → `users` + `exercises`, Testing → "table-driven unit tests for handlers; integration tests against a real Postgres".

**Conventions in effect (from memory):**

- All commands in this plan and the resulting `server/README.md` run from the **repo root** — no `cd` mid-runbook. Use `make -C server <target>`.
- Commit messages are Conventional Commits with standard types only. Subject-line-only, no body.
- No "Plan N" references in committed files; descriptive language instead.

---

### Task 1: Initialize the Go module + base Makefile

**Files:**
- Create: `server/go.mod`
- Create: `server/Makefile`
- Create: `server/.gitignore`

- [ ] **Step 1: Verify Go 1.24+ is available**

Run from repo root:

```bash
go version
```

Expected: output contains `go1.24` or `go1.25` or `go1.26`. If older, STOP and report BLOCKED — Plan 2 uses the `tool` directive in `go.mod` which requires Go 1.24.

- [ ] **Step 2: Initialize the Go module**

Run from repo root:

```bash
cd server && go mod init workout-tracker/server && cd ..
```

Expected: `server/go.mod` is created with module path `workout-tracker/server` and a `go 1.24` (or newer) directive.

- [ ] **Step 3: Write `server/.gitignore`**

Contents:

```
# Build artifacts
bin/

# Go test/coverage output
*.test
*.out
coverage.txt
```

- [ ] **Step 4: Write `server/Makefile`**

Contents:

```makefile
# All targets are meant to be invoked from the repo root via `make -C server <target>`.
# This Makefile sources infra/.env to derive DATABASE_URL when one is not provided.

-include ../infra/.env

DATABASE_URL ?= postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:5432/$(POSTGRES_DB)?sslmode=disable

.PHONY: help build test fmt vet

help:
	@echo "Targets (run from repo root as 'make -C server <target>'):"
	@echo "  build  Compile the server binary into server/bin/server"
	@echo "  test   Run all Go tests"
	@echo "  fmt    go fmt ./..."
	@echo "  vet    go vet ./..."

build:
	go build -o bin/server ./cmd/server

test:
	TEST_DATABASE_URL=$(DATABASE_URL) go test ./...

fmt:
	go fmt ./...

vet:
	go vet ./...
```

Note: Makefiles require **tab** indentation for recipe lines (not spaces). Verify with `cat -A server/Makefile` after writing — recipe lines should start with `^I`.

- [ ] **Step 5: Verify the Makefile parses**

Run from repo root:

```bash
make -C server help
```

Expected: prints the help text listing build / test / fmt / vet.

- [ ] **Step 6: Commit**

Run from repo root:

```bash
git add server/go.mod server/Makefile server/.gitignore
git commit -m "chore(server): initialize Go module and base Makefile"
```

Expected: commit contains 3 added files. (Note: `server/README.md` from Plan 1 is unchanged at this point.)

---

### Task 2: Config loader

**Files:**
- Create: `server/internal/config/config.go`
- Create: `server/internal/config/config_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/config/config_test.go`:

```go
package config

import "testing"

func TestLoad_AppliesDefaultsWhenOnlyDatabaseURLIsSet(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("LOG_LEVEL", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":8080" {
		t.Errorf("HTTPAddr default: got %q, want %q", cfg.HTTPAddr, ":8080")
	}
	if cfg.LogLevel != "info" {
		t.Errorf("LogLevel default: got %q, want %q", cfg.LogLevel, "info")
	}
	if cfg.DatabaseURL != "postgres://x:y@localhost/db" {
		t.Errorf("DatabaseURL: got %q", cfg.DatabaseURL)
	}
}

func TestLoad_RespectsExplicitValues(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("LOG_LEVEL", "debug")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel: got %q", cfg.LogLevel)
	}
}

func TestLoad_FailsWhenDatabaseURLMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when DATABASE_URL is empty, got nil")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from repo root:

```bash
make -C server test
```

Expected: build error — `package config does not exist` or similar. Compilation failure is the expected "red".

- [ ] **Step 3: Write the implementation**

File `server/internal/config/config.go`:

```go
// Package config loads server configuration from environment variables.
package config

import (
	"fmt"
	"os"
)

type Config struct {
	HTTPAddr    string
	DatabaseURL string
	LogLevel    string
}

func Load() (Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	httpAddr := os.Getenv("HTTP_ADDR")
	if httpAddr == "" {
		httpAddr = ":8080"
	}
	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}
	return Config{
		HTTPAddr:    httpAddr,
		DatabaseURL: dbURL,
		LogLevel:    logLevel,
	}, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run from repo root:

```bash
make -C server test
```

Expected: all three tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/config/
git commit -m "feat(server): env-driven config loader"
```

---

### Task 3: chi router + /healthz

**Files:**
- Create: `server/internal/api/router.go`
- Create: `server/internal/api/healthz.go`
- Create: `server/internal/api/healthz_test.go`
- Modify: `server/go.mod` (will gain `go-chi/chi/v5` dep)

- [ ] **Step 1: Add chi dependency**

Run from repo root:

```bash
cd server && go get github.com/go-chi/chi/v5 && cd ..
```

Expected: `server/go.mod` now contains a `require github.com/go-chi/chi/v5 vX.Y.Z` line; `server/go.sum` is created/updated.

- [ ] **Step 2: Write the failing test**

File `server/internal/api/healthz_test.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthz_Returns200WithJSON(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	NewRouter().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("content-type: got %q, want %q", got, "application/json")
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body unmarshal: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("body[status]: got %q, want %q", body["status"], "ok")
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
make -C server test
```

Expected: build failure — `undefined: NewRouter` or `package api does not exist`.

- [ ] **Step 4: Implement the router**

File `server/internal/api/router.go`:

```go
// Package api defines the HTTP router and handlers for the server.
package api

import "github.com/go-chi/chi/v5"

func NewRouter() *chi.Mux {
	r := chi.NewRouter()
	r.Get("/healthz", Healthz)
	return r
}
```

File `server/internal/api/healthz.go`:

```go
package api

import "net/http"

// Healthz is a liveness probe: 200 if the process is up. Does not touch any
// dependencies; for readiness use /readyz.
func Healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
make -C server test
```

Expected: all tests PASS (config tests from Task 2 + this new one).

- [ ] **Step 6: Commit**

```bash
git add server/internal/api/ server/go.mod server/go.sum
git commit -m "feat(server): chi router with /healthz liveness endpoint"
```

---

### Task 4: pgxpool DB connection helper

**Files:**
- Create: `server/internal/db/conn.go`
- Create: `server/internal/db/conn_test.go`
- Modify: `server/go.mod` (will gain `pgx/v5` deps)

- [ ] **Step 1: Add pgx/v5 dependency**

Run from repo root:

```bash
cd server && go get github.com/jackc/pgx/v5/pgxpool && cd ..
```

Expected: `server/go.mod` gains `github.com/jackc/pgx/v5` (the pgxpool subpackage is part of this module).

- [ ] **Step 2: Write the failing tests**

File `server/internal/db/conn_test.go`:

```go
package db

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestNewPool_ConnectsAndPingsSuccessfully(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping integration test (run via `make -C server test`)")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := NewPool(ctx, dbURL)
	if err != nil {
		t.Fatalf("NewPool: %v", err)
	}
	defer pool.Close()

	var got int
	if err := pool.QueryRow(ctx, "SELECT 1").Scan(&got); err != nil {
		t.Fatalf("SELECT 1: %v", err)
	}
	if got != 1 {
		t.Errorf("SELECT 1: got %d, want 1", got)
	}
}

func TestNewPool_FailsForUnreachableHost(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if _, err := NewPool(ctx, "postgres://nobody@127.0.0.1:1/none?sslmode=disable&connect_timeout=1"); err == nil {
		t.Fatal("expected error for unreachable host, got nil")
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
make -C server test
```

Expected: build error — `undefined: NewPool` / `package db does not exist`.

- [ ] **Step 4: Implement the pool helper**

File `server/internal/db/conn.go`:

```go
// Package db owns the Postgres connection pool used by handlers.
package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool aliases pgxpool.Pool so callers can depend on this package without
// importing pgxpool directly.
type Pool = pgxpool.Pool

// NewPool opens a pgxpool connection, verifies it with Ping, and returns the
// ready-to-use pool. The caller owns the pool and must Close it on shutdown.
func NewPool(ctx context.Context, databaseURL string) (*Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return pool, nil
}
```

- [ ] **Step 5: Ensure the local dev Postgres is up (test prerequisite)**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
for i in $(seq 1 20); do
  hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-postgres-1 2>/dev/null || echo starting)
  [ "$hc" = "healthy" ] && break
  sleep 2
done
echo "postgres: $hc"
```

Expected: ends with `postgres: healthy`.

- [ ] **Step 6: Run test to verify it passes**

```bash
make -C server test
```

Expected: all tests PASS (config + healthz + the two DB tests). The DB tests now actually run because `make -C server test` sets `TEST_DATABASE_URL` from `infra/.env`.

- [ ] **Step 7: Commit**

```bash
git add server/internal/db/ server/go.mod server/go.sum
git commit -m "feat(server): pgxpool-backed Postgres connection helper"
```

---

### Task 5: /readyz endpoint with DB ping

**Files:**
- Modify: `server/internal/api/router.go` (NewRouter now takes a Pinger)
- Modify: `server/internal/api/healthz_test.go` (call site update for NewRouter)
- Create: `server/internal/api/readyz.go`
- Create: `server/internal/api/readyz_test.go`

- [ ] **Step 1: Write the failing tests**

File `server/internal/api/readyz_test.go`:

```go
package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakePinger struct{ err error }

func (f *fakePinger) Ping(ctx context.Context) error { return f.err }

func TestReadyz_Returns200WhenPingerSucceeds(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	NewRouter(&fakePinger{}).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusOK)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if body["status"] != "ready" {
		t.Errorf("body[status]: got %q, want %q", body["status"], "ready")
	}
}

func TestReadyz_Returns503WhenPingerFails(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	NewRouter(&fakePinger{err: errors.New("connection refused")}).ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusServiceUnavailable)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if body["status"] != "unavailable" {
		t.Errorf("body[status]: got %q, want %q", body["status"], "unavailable")
	}
}
```

- [ ] **Step 2: Refactor the router to accept a Pinger**

Replace `server/internal/api/router.go` with:

```go
// Package api defines the HTTP router and handlers for the server.
package api

import (
	"context"

	"github.com/go-chi/chi/v5"
)

// Pinger is the surface area /readyz needs from the DB pool. Defined here so
// the api package does not import the db package.
type Pinger interface {
	Ping(ctx context.Context) error
}

func NewRouter(pinger Pinger) *chi.Mux {
	r := chi.NewRouter()
	r.Get("/healthz", Healthz)
	r.Get("/readyz", Readyz(pinger))
	return r
}
```

- [ ] **Step 3: Add the Readyz handler**

File `server/internal/api/readyz.go`:

```go
package api

import (
	"context"
	"net/http"
	"time"
)

// Readyz is a readiness probe: 200 if the DB ping succeeds within 2s,
// 503 otherwise. Use this for load-balancer or orchestrator readiness checks.
func Readyz(pinger Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		w.Header().Set("Content-Type", "application/json")
		if err := pinger.Ping(ctx); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"unavailable"}`))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}
}
```

- [ ] **Step 4: Update the existing healthz test for the new router signature**

Replace `server/internal/api/healthz_test.go` with:

```go
package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthz_Returns200WithJSON(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	NewRouter(&fakePinger{}).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("content-type: got %q, want %q", got, "application/json")
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body unmarshal: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("body[status]: got %q, want %q", body["status"], "ok")
	}
}
```

(The `fakePinger` type is defined in `readyz_test.go` and shared at the package-test level.)

- [ ] **Step 5: Run tests to verify they all pass**

```bash
make -C server test
```

Expected: all tests PASS (config + healthz + the two readyz tests + the two db tests).

- [ ] **Step 6: Commit**

```bash
git add server/internal/api/
git commit -m "feat(server): /readyz endpoint with DB ping"
```

---

### Task 6: main.go entrypoint with graceful shutdown

**Files:**
- Create: `server/cmd/server/main.go`
- Modify: `server/Makefile` (add a `run` target)

- [ ] **Step 1: Write `server/cmd/server/main.go`**

Contents:

```go
// Package main is the workout-tracker HTTP server entrypoint.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"workout-tracker/server/internal/api"
	"workout-tracker/server/internal/config"
	"workout-tracker/server/internal/db"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		logger.Error("config load failed", "err", err)
		os.Exit(1)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("db connect failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	srv := &http.Server{
		Addr:    cfg.HTTPAddr,
		Handler: api.NewRouter(pool),
	}

	go func() {
		logger.Info("server starting", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	logger.Info("shutdown signal received")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
	}
	logger.Info("server stopped")
}
```

- [ ] **Step 2: Add a `run` target to the Makefile**

Append to `server/Makefile` (after `vet`):

```makefile

.PHONY: run

run:
	DATABASE_URL=$(DATABASE_URL) go run ./cmd/server
```

Also update the `help` target to list `run`:

```makefile
help:
	@echo "Targets (run from repo root as 'make -C server <target>'):"
	@echo "  build  Compile the server binary into server/bin/server"
	@echo "  run    Run the server against the local dev DB"
	@echo "  test   Run all Go tests"
	@echo "  fmt    go fmt ./..."
	@echo "  vet    go vet ./..."
```

- [ ] **Step 3: Verify the binary compiles**

Run from repo root:

```bash
make -C server build
```

Expected: produces `server/bin/server` with no errors.

- [ ] **Step 4: Smoke-test the running server**

Make sure Postgres is up (from Task 4 Step 5 if you haven't already). Then run from repo root in one terminal:

```bash
make -C server run
```

Expected: stdout contains a JSON log line like `{"time":"...","level":"INFO","msg":"server starting","addr":":8080"}`.

In another terminal (or paste sequentially after Ctrl+Z'ing the run):

```bash
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:8080/healthz
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:8080/readyz
```

Expected: both print `200`.

Stop the server with Ctrl+C. Expected: shutdown log line `{"...","msg":"server stopped"}`.

- [ ] **Step 5: Commit**

```bash
git add server/cmd/ server/Makefile
git commit -m "feat(server): main entrypoint with graceful shutdown and run target"
```

---

### Task 7: Install goose as a Go tool + Makefile migrate targets

**Files:**
- Modify: `server/go.mod` (gains a `tool` directive for goose)
- Modify: `server/Makefile` (adds `migrate-*` targets)
- Create: `server/db/migrations/.gitkeep`

- [ ] **Step 1: Add goose as a Go tool**

Run from repo root:

```bash
cd server && go get -tool github.com/pressly/goose/v3/cmd/goose@latest && cd ..
```

Expected: `server/go.mod` gains a `tool github.com/pressly/goose/v3/cmd/goose` line; `go.sum` updated.

- [ ] **Step 2: Verify the tool is invocable**

Run from repo root:

```bash
cd server && go tool goose -version && cd ..
```

Expected: prints `goose version: vX.Y.Z` (some non-empty version string).

- [ ] **Step 3: Create the migrations directory**

Run from repo root:

```bash
mkdir -p server/db/migrations && touch server/db/migrations/.gitkeep
```

- [ ] **Step 4: Add migrate targets to the Makefile**

Append to `server/Makefile` (after the `run` target):

```makefile

MIGRATIONS_DIR := db/migrations

.PHONY: migrate-up migrate-down migrate-status migrate-reset

migrate-up:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" up

migrate-down:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" down

migrate-status:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" status

migrate-reset:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" reset
```

Also update the `help` target to list them:

```makefile
help:
	@echo "Targets (run from repo root as 'make -C server <target>'):"
	@echo "  build           Compile the server binary into server/bin/server"
	@echo "  run             Run the server against the local dev DB"
	@echo "  test            Run all Go tests"
	@echo "  fmt             go fmt ./..."
	@echo "  vet             go vet ./..."
	@echo "  migrate-up      Apply all pending migrations"
	@echo "  migrate-down    Roll back the most recent migration"
	@echo "  migrate-status  Show migration status"
	@echo "  migrate-reset   Roll back ALL migrations (destructive)"
```

- [ ] **Step 5: Verify the migrate-status target runs (against an empty migrations dir)**

Run from repo root (Postgres must be up):

```bash
make -C server migrate-status
```

Expected: prints a header like `Applied At Migration` with no rows below it (no migrations defined yet). Exit code 0.

- [ ] **Step 6: Commit**

```bash
git add server/db/ server/go.mod server/go.sum server/Makefile
git commit -m "build(server): add goose tool directive and migrate Makefile targets"
```

---

### Task 8: Migration 0001 — `users` table

**Files:**
- Create: `server/db/migrations/00001_create_users.sql`

- [ ] **Step 1: Write the migration**

File `server/db/migrations/00001_create_users.sql`:

```sql
-- +goose Up
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT NOT NULL UNIQUE,
    password_hash   TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE users;
```

Note: `pgcrypto` provides `gen_random_uuid()`. We don't drop the extension on Down because it may be shared with future migrations.

- [ ] **Step 2: Apply the migration**

Run from repo root (Postgres must be up):

```bash
make -C server migrate-up
```

Expected: output contains `OK   00001_create_users.sql` (or similar success line).

- [ ] **Step 3: Verify the table exists**

Run from repo root:

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d users'
```

Expected: psql prints a table description with columns `id` (uuid), `email` (text), `password_hash` (text), `created_at` (timestamp with time zone). The unique constraint on `email` and the primary key on `id` should be listed under `Indexes`.

- [ ] **Step 4: Verify rollback works**

```bash
make -C server migrate-down
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d users'
```

Expected: the `\d users` after `migrate-down` reports `Did not find any relation named "users"`.

- [ ] **Step 5: Re-apply (leave the schema in `up` state for Task 9)**

```bash
make -C server migrate-up
```

Expected: `OK   00001_create_users.sql` again.

- [ ] **Step 6: Commit**

```bash
git add server/db/migrations/00001_create_users.sql
git commit -m "feat(server): migration 0001 — create users table"
```

---

### Task 9: Migration 0002 — `exercises` table

**Files:**
- Create: `server/db/migrations/00002_create_exercises.sql`

- [ ] **Step 1: Write the migration**

File `server/db/migrations/00002_create_exercises.sql`:

```sql
-- +goose Up
CREATE TABLE exercises (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    muscle_group    TEXT NOT NULL,
    is_template     BOOLEAN NOT NULL DEFAULT FALSE,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX exercises_muscle_group_idx ON exercises (muscle_group);
CREATE INDEX exercises_created_by_idx ON exercises (created_by);

-- +goose Down
DROP TABLE exercises;
```

- [ ] **Step 2: Apply the migration**

```bash
make -C server migrate-up
```

Expected: output contains `OK   00002_create_exercises.sql`.

- [ ] **Step 3: Verify the table exists with the expected shape**

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d exercises'
```

Expected: psql prints the description with all seven columns. Under `Indexes` you should see `exercises_pkey`, `exercises_slug_key`, `exercises_muscle_group_idx`, `exercises_created_by_idx`. Under `Foreign-key constraints` you should see a reference to `users(id)`.

- [ ] **Step 4: Verify migrate-status reports both as applied**

```bash
make -C server migrate-status
```

Expected: two rows, both `Applied` with timestamps, for `00001_create_users.sql` and `00002_create_exercises.sql`.

- [ ] **Step 5: Commit**

```bash
git add server/db/migrations/00002_create_exercises.sql
git commit -m "feat(server): migration 0002 — create exercises table"
```

---

### Task 10: server/README.md runbook

**Files:**
- Modify: `server/README.md` (replace the Plan 1 placeholder with the full runbook)

- [ ] **Step 1: Replace `server/README.md` with the full runbook**

Overwrite with:

```markdown
# server/

Go HTTP API for the workout-tracker. Stack: chi + pgx/v5 + slog + goose
(migrations) + Postgres.

All commands below run from the **repo root**.

## Prerequisites

- Go 1.24+ (`go version`)
- Postgres running locally from the `infra/` stack — see `infra/README.md`

## First-time setup

1. Start Postgres if it's not already up:

       docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d

2. Apply migrations:

       make -C server migrate-up

3. Run the server:

       make -C server run

   Stdout will show a structured JSON log line like
   `{"...","msg":"server starting","addr":":8080"}`.

4. Verify both endpoints from another terminal:

       curl -i http://localhost:8080/healthz
       curl -i http://localhost:8080/readyz

   Both should return HTTP 200 with a JSON body.

## Useful commands

| Command | What it does |
| ------- | ------------ |
| `make -C server help`            | List all Make targets |
| `make -C server build`           | Compile to `server/bin/server` |
| `make -C server run`             | Run the server against the local dev DB |
| `make -C server test`            | Run all Go tests (DB tests use the local dev DB) |
| `make -C server fmt`             | `go fmt ./...` |
| `make -C server vet`             | `go vet ./...` |
| `make -C server migrate-up`      | Apply all pending migrations |
| `make -C server migrate-down`    | Roll back the most recent migration |
| `make -C server migrate-status`  | Show migration status |
| `make -C server migrate-reset`   | Roll back **all** migrations (destructive) |

## File layout

- `cmd/server/main.go` — entry point: load config, open DB, start HTTP server with graceful shutdown.
- `internal/config/` — env-driven config loader (`DATABASE_URL`, `HTTP_ADDR`, `LOG_LEVEL`).
- `internal/db/` — `pgxpool` factory.
- `internal/api/` — chi router and HTTP handlers (`/healthz`, `/readyz`).
- `db/migrations/` — goose-managed `.sql` migrations.

## Endpoints

| Path        | Method | Behavior |
| ----------- | ------ | -------- |
| `/healthz`  | GET    | Liveness — 200 if the process is up. Does not touch the DB. |
| `/readyz`   | GET    | Readiness — 200 if `pool.Ping` succeeds within 2s, 503 otherwise. |

## Configuration

| Env var         | Required | Default     | Notes |
| --------------- | -------- | ----------- | ----- |
| `DATABASE_URL`  | yes      | —           | Standard libpq-style URL (`postgres://user:pass@host:port/db?sslmode=disable`). |
| `HTTP_ADDR`     | no       | `:8080`     | Listen address. |
| `LOG_LEVEL`     | no       | `info`      | Reserved for future slog level wiring. |

## Tests

`make -C server test` runs every test under `./...`. Tests that require a
real Postgres connection (currently `internal/db`) skip when
`TEST_DATABASE_URL` is not set; the `make test` target sets it from
`infra/.env`.

## Migrations

Goose is installed as a Go tool via the `tool` directive in `go.mod`.
There is no separate binary to install — `go tool goose` resolves to the
pinned version. Migrations live in `db/migrations/` and follow goose's
`<seq>_<name>.sql` naming.
```

- [ ] **Step 2: Commit**

```bash
git add server/README.md
git commit -m "docs(server): runbook for build, run, test, and migrate"
```

---

### Task 11: End-state verification

**Files:** none. This task is verification only — no source changes, no commit.

- [ ] **Step 1: Ensure a clean DB state**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
sleep 5
make -C server migrate-reset
make -C server migrate-up
make -C server migrate-status
```

Expected: after `migrate-reset`, status reports "Pending"; after `migrate-up`, both migrations show `Applied`.

- [ ] **Step 2: Verify both tables exist with the expected columns**

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\dt'
```

Expected: output lists three relations — `users`, `exercises`, and goose's own `goose_db_version` table.

- [ ] **Step 3: Run the full test suite**

```bash
make -C server test
```

Expected: every package passes — `config`, `api`, and `db` all green.

- [ ] **Step 4: Build the binary**

```bash
make -C server build
```

Expected: produces `server/bin/server` with no errors or warnings.

- [ ] **Step 5: Start the server in the background and probe both endpoints**

```bash
make -C server run &
SERVER_PID=$!
sleep 2
curl -sS -o /dev/null -w "healthz=%{http_code}\n" http://localhost:8080/healthz
curl -sS -o /dev/null -w "readyz=%{http_code}\n" http://localhost:8080/readyz
kill -TERM "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
```

Expected: prints `healthz=200` and `readyz=200`. The server logs a graceful-shutdown line after `kill -TERM`.

- [ ] **Step 6: Verify git state is clean**

```bash
git status
git log --oneline fb2676f..HEAD
```

Expected: working tree clean; the log shows the 8 commits added by Plan 2:

```
docs(server): runbook for build, run, test, and migrate
feat(server): migration 0002 — create exercises table
feat(server): migration 0001 — create users table
build(server): add goose tool directive and migrate Makefile targets
feat(server): main entrypoint with graceful shutdown and run target
feat(server): /readyz endpoint with DB ping
feat(server): pgxpool-backed Postgres connection helper
feat(server): chi router with /healthz liveness endpoint
feat(server): env-driven config loader
chore(server): initialize Go module and base Makefile
```

(That's 10 lines — Tasks 1 through 10 each produced one commit; Task 11 is verification-only and produces none.)

- [ ] **Step 7: No commit (verification only)**

Plan 2 is complete. Proceed to Plan 3 (auth + JWKS + OpenAPI v0).
