# Plan 4a — Containerize the Go API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the Go API as a `server` service inside the Docker Compose stack — built from a multi-stage distroless image, connecting to Postgres over the in-cluster network, with the RSA signing key mounted as a Docker secret — so a sibling service (PowerSync, added next) can reach its JWKS at `http://server:8080` over the compose network.

**Architecture:** A multi-stage Dockerfile (golang build stage → distroless static nonroot final) produces a tiny static binary. The binary gains a `-healthcheck` subcommand (distroless has no shell/curl, so the container healthcheck invokes the binary itself). A new `server` service in `infra/compose.yml` builds that image, depends on a healthy `postgres`, connects via `DATABASE_URL=postgres://…@postgres:5432/…` (in-cluster service DNS, internal port — NOT the host's 5433), reads its private key from a Compose secret at `/run/secrets/jwt_private_key`, and exposes a healthcheck using the new flag. A dev override publishes the server on host `8080` and sets the dev `POWERSYNC_URL`. The host `make -C server run` path is unchanged and remains available for fast local iteration.

**Tech Stack:** Docker multi-stage build, `golang:1.26-alpine` builder (CGO disabled, static), `gcr.io/distroless/static-debian12:nonroot` runtime, Docker Compose v2 secrets, Go stdlib `flag`/`net/http` for the healthcheck.

**Spec sections covered:** Deployment → "homelab compose stack" (the API joins the stack); Architecture → the API must be reachable in-cluster by the PowerSync service. This is the prerequisite enabler for Plan 4b (PowerSync), per the research scope recommendation that split Plan 4 into 4a (this) + 4b (PowerSync service).

---

## Decisions locked (from verified research)

| Topic | Decision |
| ----- | -------- |
| Image | Multi-stage: `golang:1.26-alpine` build → `gcr.io/distroless/static-debian12:nonroot` final. `CGO_ENABLED=0`, `-trimpath -ldflags='-s -w'`. |
| Build context | `../server` (the self-contained Go module). `server/.dockerignore` **must** exclude `.secrets/` so the RSA key never enters the build context. |
| Healthcheck | A `-healthcheck` flag on the binary (distroless has no shell). Container healthcheck: `["CMD", "/server", "-healthcheck"]`. |
| Key delivery | Docker Compose **secret** `jwt_private_key` (file `../server/.secrets/jwt_private_key.pem`) mounted at `/run/secrets/jwt_private_key`; `JWT_PRIVATE_KEY_PATH` points there. The key is mounted at runtime, never baked into the image. |
| DB connection | In-cluster: `postgres://…@postgres:5432/…?sslmode=disable` (service DNS `postgres`, internal port 5432). Host tooling still uses `localhost:5433`. |
| Migrations | Unchanged: run from the host via `make -C server migrate-up` (same DB instance). The container does not run migrations. |
| Host port | Containerized `server` publishes `8080:8080` in the dev override (same as the host `make run` — use one or the other, not both). |
| `POWERSYNC_URL` | Plumbed via env; dev override sets `http://localhost:8090` (PowerSync's future host port). Base default documented in `.env.example`. |

**Deferred to Plan 4b** (do NOT do here): the `powersync` + `powersync-storage` services, the corrected `powersync.yaml`, the `00004` publication/role migration, and the sync validation suite. The open questions about storage co-location, publication scope, sync-rules edition, and prod TLS are all 4b concerns.

## Conventions in effect (from memory)

- All commands run from the **repo root**; use `make -C server <target>` / explicit paths, never `cd` mid-runbook.
- Conventional Commits, standard types only, subject-line-only.
- No "Plan N" / "4a/4b" literals in committed files; use descriptive language.

## File structure

```
server/
├── Dockerfile              # NEW: multi-stage build → distroless
├── .dockerignore           # NEW: excludes .secrets/, bin/
└── cmd/server/
    ├── main.go             # MODIFY: handle -healthcheck flag before normal startup
    └── healthcheck.go      # NEW: testable healthcheck(baseURL) probe
infra/
├── compose.yml             # MODIFY: add `server` service + top-level secrets
├── compose.dev.yml         # MODIFY: publish server 8080, dev POWERSYNC_URL
└── .env.example            # MODIFY: add POWERSYNC_URL
```

---

### Task 1: Server Dockerfile + .dockerignore

**Files:**
- Create: `server/Dockerfile`
- Create: `server/.dockerignore`

- [ ] **Step 1: Write `server/.dockerignore`** (CRITICAL — excludes the signing key from the build context)

```
# Never send the signing key or local build output into the build context.
.secrets/
bin/

# Not needed in the image build.
*.md
```

- [ ] **Step 2: Write `server/Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1

# --- build stage ---
FROM golang:1.26-alpine AS build
WORKDIR /src

# Cache modules first.
COPY go.mod go.sum ./
RUN go mod download

# Build a static binary (no libc, no shell needed at runtime).
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/server ./cmd/server

# --- final stage ---
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

- [ ] **Step 3: Build the image**

Run from repo root:

```bash
docker build -t workout-tracker-server:plan4a -f server/Dockerfile server
```

Expected: build succeeds (modules download, static binary builds, final image is tiny). Note the build context is `server` (the module dir).

- [ ] **Step 4: Confirm the key is NOT baked into the image and the binary is the right one**

Run from repo root:

```bash
# The Dockerfile must not reference .secrets, and .dockerignore must exclude it.
grep -q '.secrets' server/.dockerignore && echo "dockerignore excludes .secrets OK"
grep -c 'secrets' server/Dockerfile   # expected: 0

# Running with no env must fail fast on config load (proves it's our binary, key not embedded).
docker run --rm workout-tracker-server:plan4a 2>&1 | head -2
```

Expected: `.dockerignore` excludes `.secrets` (prints OK); the Dockerfile has `0` references to secrets; running the image with no env prints a config error like `{"...","msg":"config load failed","err":"DATABASE_URL is required"}` and exits non-zero (the binary starts, then exits because no DB/key env is set — correct).

- [ ] **Step 5: Commit**

```bash
git add server/Dockerfile server/.dockerignore
git commit -m "build(server): multi-stage distroless Dockerfile"
```

---

### Task 2: Add a `-healthcheck` flag to the server binary

The distroless image has no shell or curl, so the container healthcheck must invoke the binary itself. Factor the probe into a testable function.

**Files:**
- Create: `server/cmd/server/healthcheck.go`
- Create: `server/cmd/server/healthcheck_test.go`
- Modify: `server/cmd/server/main.go` (handle the flag before normal startup)

- [ ] **Step 1: Write the failing test**

File `server/cmd/server/healthcheck_test.go`:

```go
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthcheck_OKOn200(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	if err := healthcheck(srv.URL); err != nil {
		t.Fatalf("expected nil for 200, got %v", err)
	}
}

func TestHealthcheck_ErrorsOnNon200(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	if err := healthcheck(srv.URL); err == nil {
		t.Fatal("expected an error for 503, got nil")
	}
}

func TestHealthcheck_ErrorsOnUnreachable(t *testing.T) {
	if err := healthcheck("http://127.0.0.1:1"); err == nil {
		t.Fatal("expected an error for an unreachable host, got nil")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: healthcheck`.

- [ ] **Step 3: Write `server/cmd/server/healthcheck.go`**

```go
package main

import (
	"fmt"
	"net/http"
	"time"
)

// healthcheck probes baseURL + "/healthz" and returns nil only on HTTP 200.
// Used by the `-healthcheck` flag so the distroless container (no shell/curl)
// can health-check itself by re-invoking the binary.
func healthcheck(baseURL string) error {
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(baseURL + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthz returned %d", resp.StatusCode)
	}
	return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the three healthcheck tests PASS (and all other packages still pass).

- [ ] **Step 5: Wire the flag into `main.go`**

Replace `server/cmd/server/main.go` with EXACTLY (this adds `flag` handling at the top of `main`, before config load, and an `os` import is already present):

```go
// Package main is the workout-tracker HTTP server entrypoint.
package main

import (
	"context"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"workout-tracker/server/internal/api"
	"workout-tracker/server/internal/auth"
	"workout-tracker/server/internal/config"
	"workout-tracker/server/internal/db"
)

func main() {
	healthFlag := flag.Bool("healthcheck", false, "probe /healthz on the local HTTP_ADDR and exit 0 (healthy) or 1")
	flag.Parse()
	if *healthFlag {
		addr := os.Getenv("HTTP_ADDR")
		if addr == "" {
			addr = ":8080"
		}
		if err := healthcheck("http://localhost" + addr); err != nil {
			os.Exit(1)
		}
		os.Exit(0)
	}

	cfg, err := config.Load()
	if err != nil {
		slog.Error("config load failed", "err", err)
		os.Exit(1)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.SlogLevel()}))
	slog.SetDefault(logger)

	priv, err := auth.LoadPrivateKeyPEM(cfg.JWTPrivateKeyPath)
	if err != nil {
		logger.Error("load signing key failed", "err", err)
		os.Exit(1)
	}
	kid := auth.ThumbprintKID(&priv.PublicKey)
	signer := auth.NewSigner(priv, kid, cfg.JWTIssuer)
	verifier := auth.NewVerifier(&priv.PublicKey, cfg.JWTIssuer)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("db connect failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	authHandler := api.NewAuthHandler(api.AuthConfig{
		Users:             auth.NewUserStore(pool),
		Refresh:           auth.NewRefreshStore(pool, cfg.RefreshTokenTTL),
		Signer:            signer,
		APIAudience:       cfg.APIAudience,
		PowerSyncAudience: cfg.PowerSyncAudience,
		PowerSyncURL:      cfg.PowerSyncURL,
		AccessTTL:         cfg.AccessTokenTTL,
		PowerSyncTTL:      cfg.PowerSyncTokenTTL,
	})

	srv := &http.Server{
		Addr: cfg.HTTPAddr,
		Handler: api.NewRouter(api.Deps{
			Pinger:      pool,
			JWKS:        auth.JWKSHandler(&priv.PublicKey, kid),
			Auth:        authHandler,
			Verifier:    verifier,
			APIAudience: cfg.APIAudience,
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		logger.Info("server starting", "addr", cfg.HTTPAddr, "kid", kid)
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

- [ ] **Step 6: Verify build + tests + the flag against a running server**

Run from repo root (Postgres up on 5433, dev key present):

```bash
make -C server test
make -C server build
# Start the host server, probe with the flag from a second invocation, then stop.
set -a && . infra/.env && set +a
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5433/$POSTGRES_DB?sslmode=disable" \
JWT_PRIVATE_KEY_PATH=server/.secrets/jwt_private_key.pem \
  server/bin/server > /tmp/wt-p4a-t2.log 2>&1 &
SERVER_PID=$!
sleep 2
server/bin/server -healthcheck; echo "healthcheck exit=$?"
kill -TERM "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
# With the server down, the flag must report unhealthy:
server/bin/server -healthcheck; echo "healthcheck-when-down exit=$?"
```

Expected: tests pass; build OK; `healthcheck exit=0` while the server is up; `healthcheck-when-down exit=1` after it stops.

- [ ] **Step 7: Commit**

```bash
git add server/cmd/server/healthcheck.go server/cmd/server/healthcheck_test.go server/cmd/server/main.go
git commit -m "feat(server): -healthcheck flag for container probes"
```

---

### Task 3: `server` compose service + secret + env

**Files:**
- Modify: `infra/compose.yml` (add the `server` service + top-level `secrets`)
- Modify: `infra/.env.example` (add `POWERSYNC_URL`)

- [ ] **Step 1: Add the `server` service and `secrets` block to `infra/compose.yml`**

Insert a `server` service under `services:` (after the `postgres` service), and add a top-level `secrets:` block. The full file becomes:

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

  server:
    build:
      context: ../server
      dockerfile: Dockerfile
    restart: unless-stopped
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

volumes:
  postgres_data:

secrets:
  jwt_private_key:
    file: ../server/.secrets/jwt_private_key.pem
```

- [ ] **Step 2: Add `POWERSYNC_URL` to `infra/.env.example`**

Append to `infra/.env.example`:

```bash

# URL the PowerSync client (phone/web) uses to reach the sync service.
# Must be reachable from the CLIENT (phone over Tailscale), NOT an in-cluster name.
# Dev default (set in compose.dev.yml): http://localhost:8090
# Prod: the Tailscale hostname/IP of this host on the PowerSync port.
POWERSYNC_URL=http://localhost:8090
```

Also add the same line to your local `infra/.env` (which is gitignored) so compose has the value:

```bash
printf '\nPOWERSYNC_URL=http://localhost:8090\n' >> infra/.env
```

- [ ] **Step 3: Validate the merged config**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env config >/dev/null && echo "compose config OK"
docker compose -f infra/compose.yml --env-file infra/.env config | grep -A3 'secrets:' | head -8
```

Expected: `compose config OK`; the secrets block resolves the `jwt_private_key` file path.

- [ ] **Step 4: Commit**

```bash
git add infra/compose.yml infra/.env.example
git commit -m "feat(infra): containerized server service with key as a compose secret"
```

(Note: `infra/.env` is gitignored and not committed.)

---

### Task 4: Dev override — publish server port + dev `POWERSYNC_URL`

**Files:**
- Modify: `infra/compose.dev.yml`

- [ ] **Step 1: Add the `server` override to `infra/compose.dev.yml`**

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
```

- [ ] **Step 2: Validate the merged dev config exposes the server port**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env config | grep -A4 'published: "8080"'
```

Expected: shows the `8080` host-port publishing for the server service (target 8080).

- [ ] **Step 3: Commit**

```bash
git add infra/compose.dev.yml
git commit -m "feat(infra): publish containerized server on host 8080 in dev"
```

---

### Task 5: End-state verification

**Files:** none — verification only, no commit.

The containerized server and the host `make -C server run` both bind host port 8080, so they are mutually exclusive. Ensure no host `make run` server is running before this.

- [ ] **Step 1: Build + bring up postgres and the containerized server**

Run from repo root:

```bash
# Stop any host-run server holding :8080
pkill -f 'server/bin/server$' 2>/dev/null || true
pkill -f 'cmd/server' 2>/dev/null || true

docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d --build
```

Expected: both `postgres` and `server` build/start. (`postgres` likely already healthy from prior plans.)

- [ ] **Step 2: Wait for the server container to be healthy**

Run from repo root:

```bash
for i in $(seq 1 24); do
  hc=$(docker inspect --format='{{.State.Health.Status}}' workout-tracker-server-1 2>/dev/null || echo starting)
  echo "attempt $i: $hc"
  [ "$hc" = "healthy" ] && break
  sleep 2
done
```

Expected: reaches `healthy` (the `-healthcheck` flag working inside the container proves the binary self-probe path). If it stays `unhealthy`, check `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env logs server`.

- [ ] **Step 3: Hit the containerized API from the host**

Run from repo root:

```bash
curl -sS -o /dev/null -w "healthz=%{http_code}\n" http://localhost:8080/healthz
curl -sS -o /dev/null -w "readyz=%{http_code}\n" http://localhost:8080/readyz
curl -sS http://localhost:8080/.well-known/jwks.json \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d["keys"][0]["kty"]=="RSA";print("jwks OK kid="+d["keys"][0]["kid"][:12])'
```

Expected: `healthz=200`, `readyz=200` (readyz proves the container reached `postgres:5432` in-cluster), and `jwks OK …` (proves the secret-mounted key loaded).

- [ ] **Step 4: Full auth flow against the containerized API**

Run from repo root (the dev user `me@example.com`/`devpassword` exists in the DB from earlier work):

```bash
LOGIN=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' -d '{"email":"me@example.com","password":"devpassword"}')
ACCESS=$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
echo "login OK"
curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print("powersync-token endpoint="+d["endpoint"])'
```

Expected: `login OK`; the powersync-token `endpoint` prints `http://localhost:8090` (the dev `POWERSYNC_URL` — proving the env plumbing works; the URL isn't live until Plan 4b).

- [ ] **Step 5: Confirm the key is mounted (not baked) and not tracked**

Run from repo root:

```bash
# The key is present at the secret path inside the container's runtime, but the
# image itself has no /run/secrets baked in (it's a tmpfs mount). Confirm the
# source file is untracked and the Dockerfile never copies it.
git ls-files server/.secrets/ | grep -q . && echo "TRACKED (BAD)" || echo "key untracked OK"
grep -c 'secrets' server/Dockerfile  # expected 0
```

Expected: `key untracked OK`; Dockerfile secrets references `0`.

- [ ] **Step 6: Confirm git state**

Run from repo root:

```bash
git status
git log --oneline main..HEAD
```

Expected: working tree clean; the log shows the 4 commits added by this plan:

```
feat(infra): publish containerized server on host 8080 in dev
feat(infra): containerized server service with key as a compose secret
feat(server): -healthcheck flag for container probes
build(server): multi-stage distroless Dockerfile
```

- [ ] **Step 7: (Optional) tear down the containerized server, restore host-dev mode**

The host `make -C server run` remains the fast-iteration path. To switch back:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env stop server
# then `make -C server run` works on :8080 again
```

- [ ] **Step 8: No commit (verification only)**

Plan 4a is complete. The Go API now runs in-cluster as `server` (reachable at `http://server:8080` over the compose network). Proceed to Plan 4b (add the PowerSync + powersync-storage services, the `00004` publication/role migration, the corrected `powersync.yaml`, and the sync validation suite).
