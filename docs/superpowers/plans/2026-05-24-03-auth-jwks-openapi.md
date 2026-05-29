# Plan 3 — Auth, JWKS & OpenAPI v0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email+password authentication to the Go server — issuing a short-lived API access JWT plus a rotating opaque refresh token, minting short-lived PowerSync JWTs on demand, and publishing an RS256 public key at a JWKS endpoint that PowerSync trusts — and author an OpenAPI 3.1 contract describing the auth surface.

**Architecture:** A new `internal/auth` package owns password hashing (Argon2id), RSA key loading + RFC 7638 `kid` derivation, the JWKS document, JWT signing/verification (golang-jwt v5, RS256), and the refresh-token store (pgx-backed, rotation with reuse detection). HTTP handlers and the auth middleware live in `internal/api` and orchestrate the auth package through small interfaces (the same decoupling pattern Plan 2 used for `Pinger`). Two tokens with separated concerns: a stateless ~15-minute API access JWT (`aud=workout-tracker-api`) verified by the API itself, plus a separately-minted ~5-minute PowerSync JWT (`aud=workout-tracker-powersync`, `sub=user UUID`) for the sync layer; a 30-day opaque refresh token (stored only as a SHA-256 hash, rotated on every use, whole family revoked on reuse) is the only stateful auth component. The same RSA keypair signs both JWTs; its public half is served unauthenticated at `/.well-known/jwks.json`. The OpenAPI 3.1 YAML at `api/openapi.yaml` is the contract, linted in CI with vacuum.

**Tech Stack:** Go 1.26, chi v5, pgx/v5, `github.com/golang-jwt/jwt/v5` v5.3.1, `golang.org/x/crypto/argon2`, stdlib `crypto/rsa`/`crypto/x509`/`encoding/pem`/`math/big`/`crypto/sha256`/`crypto/subtle`, goose migrations, `github.com/daveshanley/vacuum` v0.27.2 (lint tool, run via `go run`, not imported), OpenAPI 3.1.0.

**Spec sections covered:** Architecture → auth flow (JWT issuance, JWKS trust, `sub=user_id`, sync rules by `request.user_id`); Stack → API contract row (OpenAPI 3.1, hand-authored); Data model → `users` (login reads it) + a new `refresh_tokens` table; Deployment → JWKS reachable by the PowerSync service; the spec's open question "Auth shape: JWT-only vs JWT + httpOnly cookie; refresh-token rotation" (resolved below). Also folds in two carry-over findings from the Plan 2 review: wire `LogLevel` into the slog handler, and add HTTP server timeouts before auth endpoints land.

---

## Defaults chosen (override any before execution)

These resolve the research's open questions. Each is a config value or a localized choice, so changing one is cheap — but call it out now if you disagree:

| # | Decision | Default | Reversibility |
| - | -------- | ------- | ------------- |
| 1 | Signing algorithm | **RS256**, single RSA keypair, **3072-bit** | `alg`/bits localized to `keys.go`/`token.go`; JWK `n`/`e` is algorithm-agnostic |
| 2 | Access-token lifetime | **15m** | `ACCESS_TOKEN_TTL` env, default in config |
| 3 | Refresh-token lifetime | **30d (720h)**, rotation + reuse detection, **strict** (no grace window) | `REFRESH_TOKEN_TTL` env; grace window is a documented future refinement |
| 4 | PowerSync token lifetime | **5m** (PowerSync hard-rejects > 60m) | `POWERSYNC_TOKEN_TTL` env |
| 5 | Audiences | API `workout-tracker-api`, PowerSync `workout-tracker-powersync` | `API_AUDIENCE` / `POWERSYNC_AUDIENCE` env |
| 6 | Refresh-token transport (Plan 3) | **JSON response body** (mobile-first; Flutter uses secure storage). Web httpOnly-cookie transport is deferred to the web plan. | Handlers return the token in JSON; a cookie variant can be layered later |
| 7 | Opportunistic password rehash on login | **No** (YAGNI for one user) | Documented as a future hook in the login handler |
| 8 | OpenAPI version | **3.1.0** | `api/openapi.yaml` header |

The two structural choices the research most strongly endorsed — **two separate tokens** and a **stateful `refresh_tokens` table with rotation** — are locked because they are painful to retrofit and align with "build it right for the decade."

### Deferred hardening (acceptable for a single-user, Tailscale-only app)

These are deliberately out of scope for Plan 3 — noted so they aren't lost:

- **Login timing oracle:** the unknown-user path returns before running Argon2id, so response timing can distinguish "user exists." Negligible for one user; equalize later by verifying against a fixed dummy hash on the unknown-user path.
- **`createuser` password via flag:** the plaintext appears in shell history and `/proc/<pid>/cmdline`. Fine for a local one-off admin tool; switch to a prompt (`golang.org/x/term`) or env var if it ever matters.
- **`refresh_tokens` row growth:** consumed/expired rows accumulate; add a periodic cleanup `DELETE` later (see Task 11 note).
- **Rate-limiting** on `/auth/login`: unnecessary behind Tailscale; add if the API is ever exposed more broadly (Argon2id also makes brute-force expensive).

---

## Conventions in effect (from memory)

- Every command in this plan and in the resulting READMEs runs from the **repo root**; use `make -C server <target>` and explicit paths — never `cd` mid-runbook.
- Commit messages are Conventional Commits with standard types only, subject-line-only, no body.
- No "Plan N" references in committed files; use descriptive language.
- TDD: write the failing test, run it red, implement, run it green, commit.

---

## File structure (what each new unit owns)

```
server/
├── cmd/
│   ├── genkey/main.go          # one-off: generate the RSA private key PEM
│   └── createuser/main.go      # one-off: create a user (email + hashed password)
├── internal/
│   ├── auth/
│   │   ├── password.go         # Argon2id HashPassword / VerifyPassword (PHC strings)
│   │   ├── keys.go             # GenerateAndWritePEM / LoadPrivateKeyPEM / ThumbprintKID
│   │   ├── jwks.go             # JWK / JWKS types, PublicJWK, JWKSHandler
│   │   ├── token.go            # Signer (Sign) + Verifier (Verify), RS256, golang-jwt v5
│   │   ├── users.go            # UserStore.FindByEmail (pgx)
│   │   └── refresh_store.go    # RefreshStore Issue/Rotate/RevokeFamily (pgx)
│   ├── api/
│   │   ├── middleware_auth.go  # RequireAuth chi middleware; UserIDFromContext
│   │   └── auth_handlers.go    # AuthHandler: Login/Refresh/Logout/PowerSyncToken
│   └── config/config.go        # extended: key path, audiences, issuer, TTLs, slog level
└── db/migrations/00003_create_refresh_tokens.sql
api/openapi.yaml                # OpenAPI 3.1 contract (source of truth)
```

The canonical auth-package API (referenced across tasks; defined once here so later tasks stay consistent):

- `auth.HashPassword(plain string) (string, error)` / `auth.VerifyPassword(plain, encoded string) (bool, error)`
- `auth.GenerateAndWritePEM(path string, bits int) error` / `auth.LoadPrivateKeyPEM(path string) (*rsa.PrivateKey, error)` / `auth.ThumbprintKID(pub *rsa.PublicKey) string`
- `auth.PublicJWK(pub *rsa.PublicKey, kid string) auth.JWK` / `auth.JWKSHandler(pub *rsa.PublicKey, kid string) http.HandlerFunc`
- `auth.NewSigner(priv *rsa.PrivateKey, kid, issuer string) *auth.Signer` with `(*Signer).Sign(subject, audience string, ttl time.Duration) (string, error)`
- `auth.NewVerifier(pub *rsa.PublicKey, issuer string) *auth.Verifier` with `(*Verifier).Verify(tokenStr, audience string) (*auth.Claims, error)`
- `auth.NewUserStore(pool *db.Pool) *auth.UserStore` with `(*UserStore).FindByEmail(ctx, email) (*auth.User, error)`; `auth.ErrUserNotFound`
- `auth.NewRefreshStore(pool *db.Pool, ttl time.Duration) *auth.RefreshStore` with `Issue(ctx, userID) (string, error)`, `Rotate(ctx, presented) (userID, newToken string, err error)`, `RevokeFamily(ctx, presented string) error`; `auth.ErrInvalidRefreshToken`, `auth.ErrRefreshReused`

---

### Task 1: Add direct dependencies (golang-jwt v5, x/crypto)

**Files:**
- Modify: `server/go.mod`, `server/go.sum`

- [ ] **Step 1: Add golang-jwt/jwt/v5 pinned and promote x/crypto to direct**

Run from repo root:

```bash
go -C server get github.com/golang-jwt/jwt/v5@v5.3.1
go -C server get golang.org/x/crypto/argon2
```

Do **not** run `go mod tidy` here. Neither package is imported by any code yet
(`x/crypto/argon2` lands in Task 2, `jwt/v5` in Task 8), and under Go's module-graph
pruning `go mod tidy` would drop the not-yet-imported `jwt/v5` and re-mark
`x/crypto` as `// indirect`. `go get` records both as explicit (direct) requires;
they become genuinely used by Task 8, after which a `go mod tidy` is safe (and is
exercised naturally by the end-state build in Task 20).

Expected: `go.mod` gains `github.com/golang-jwt/jwt/v5 v5.3.1` and `golang.org/x/crypto vX.Y.Z` in the **direct** require block (no `// indirect`). The transitive `github.com/golang-jwt/jwt/v4` stays `// indirect`.

- [ ] **Step 2: Verify the dependency state**

Run from repo root:

```bash
grep -E 'golang-jwt/jwt/v5|golang.org/x/crypto' server/go.mod
go -C server build ./...
```

Expected: `golang-jwt/jwt/v5 v5.3.1` appears WITHOUT `// indirect`; `golang.org/x/crypto` appears WITHOUT `// indirect`; `go build ./...` succeeds (no code uses them yet, so this just confirms the module graph resolves).

- [ ] **Step 3: Commit**

```bash
git add server/go.mod server/go.sum
git commit -m "build(server): add golang-jwt/v5 and promote x/crypto to direct"
```

---

### Task 2: Password hashing package (Argon2id)

**Files:**
- Create: `server/internal/auth/password.go`
- Create: `server/internal/auth/password_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/password_test.go`:

```go
package auth

import (
	"strings"
	"testing"
)

func TestHashPassword_ProducesVerifiablePHCString(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Errorf("unexpected PHC prefix: %q", hash)
	}

	ok, err := VerifyPassword("correct horse battery staple", hash)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if !ok {
		t.Error("expected password to verify, got false")
	}
}

func TestHashPassword_RejectsWrongPassword(t *testing.T) {
	hash, err := HashPassword("right-password")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	ok, err := VerifyPassword("wrong-password", hash)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if ok {
		t.Error("expected wrong password to fail, got true")
	}
}

func TestHashPassword_SaltsAreUnique(t *testing.T) {
	a, _ := HashPassword("same")
	b, _ := HashPassword("same")
	if a == b {
		t.Error("expected unique salts to produce different hashes")
	}
}

func TestVerifyPassword_RejectsMalformedHash(t *testing.T) {
	if _, err := VerifyPassword("x", "not-a-phc-string"); err != ErrInvalidHash {
		t.Errorf("got %v, want ErrInvalidHash", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: HashPassword` / `undefined: ErrInvalidHash`.

- [ ] **Step 3: Write the implementation**

File `server/internal/auth/password.go`:

```go
// Package auth provides password hashing, RSA key handling, JWT signing and
// verification, and the refresh-token store for the workout-tracker server.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// OWASP Argon2id baseline (19 MiB, t=2, p=1). Parameters are embedded in every
// hash, so they can be raised later without breaking stored hashes.
const (
	argonMemoryKiB uint32 = 19456 // 19 MiB
	argonTime      uint32 = 2
	argonThreads   uint8  = 1
	saltLen        int    = 16
	keyLen         uint32 = 32
)

var (
	ErrInvalidHash         = errors.New("password: invalid PHC hash format")
	ErrIncompatibleVersion = errors.New("password: incompatible argon2 version")
)

// HashPassword derives an Argon2id hash and returns a self-describing PHC string:
// $argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>.
func HashPassword(plain string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("password: generate salt: %w", err)
	}
	key := argon2.IDKey([]byte(plain), salt, argonTime, argonMemoryKiB, argonThreads, keyLen)
	return fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemoryKiB, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

// VerifyPassword re-derives using the parameters parsed from the stored PHC
// string and compares in constant time. Returns (true,nil) on match,
// (false,nil) on a valid hash that does not match, (false,err) on a malformed hash.
func VerifyPassword(plain, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, ErrInvalidHash
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, ErrInvalidHash
	}
	if version != argon2.Version {
		return false, ErrIncompatibleVersion
	}

	var memory, time uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
		return false, ErrInvalidHash
	}
	if time == 0 || threads == 0 {
		return false, ErrInvalidHash // argon2.IDKey panics on zero time/threads
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, ErrInvalidHash
	}
	storedKey, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, ErrInvalidHash
	}

	computed := argon2.IDKey([]byte(plain), salt, time, memory, threads, uint32(len(storedKey)))
	return subtle.ConstantTimeCompare(storedKey, computed) == 1, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: `ok  workout-tracker/server/internal/auth` with all four password tests passing (plus existing packages still green).

- [ ] **Step 5: Commit**

```bash
git add server/internal/auth/password.go server/internal/auth/password_test.go
git commit -m "feat(server): argon2id password hashing"
```

---

### Task 3: RSA keys — load, generate, RFC 7638 kid

**Files:**
- Create: `server/internal/auth/keys.go`
- Create: `server/internal/auth/keys_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/keys_test.go`:

```go
package auth

import (
	"path/filepath"
	"testing"
)

func TestGenerateLoadAndThumbprint_RoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "key.pem")
	if err := GenerateAndWritePEM(path, 2048); err != nil { // 2048 keeps the test fast
		t.Fatalf("GenerateAndWritePEM: %v", err)
	}

	priv, err := LoadPrivateKeyPEM(path)
	if err != nil {
		t.Fatalf("LoadPrivateKeyPEM: %v", err)
	}

	kid1 := ThumbprintKID(&priv.PublicKey)
	if kid1 == "" {
		t.Fatal("empty kid")
	}

	// Loading again must yield the same deterministic kid.
	priv2, err := LoadPrivateKeyPEM(path)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if kid2 := ThumbprintKID(&priv2.PublicKey); kid2 != kid1 {
		t.Errorf("kid not deterministic: %q != %q", kid1, kid2)
	}
}

func TestLoadPrivateKeyPEM_RejectsMissingFile(t *testing.T) {
	if _, err := LoadPrivateKeyPEM(filepath.Join(t.TempDir(), "nope.pem")); err == nil {
		t.Fatal("expected error for missing key file, got nil")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: GenerateAndWritePEM` / `undefined: LoadPrivateKeyPEM` / `undefined: ThumbprintKID`.

- [ ] **Step 3: Write the implementation**

File `server/internal/auth/keys.go`:

```go
package auth

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
)

// GenerateAndWritePEM creates a new RSA private key and writes it as a PKCS#8
// PEM file with 0600 permissions. Intended to be run once, offline.
func GenerateAndWritePEM(path string, bits int) error {
	priv, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return fmt.Errorf("generate key: %w", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return fmt.Errorf("marshal key: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}
	block := &pem.Block{Type: "PRIVATE KEY", Bytes: der}
	return os.WriteFile(path, pem.EncodeToMemory(block), 0o600)
}

// LoadPrivateKeyPEM loads a PKCS#8 RSA private key from a PEM file.
func LoadPrivateKeyPEM(path string) (*rsa.PrivateKey, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read key file: %w", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, errors.New("auth: no PEM block found in key file")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse key: %w", err)
	}
	priv, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("auth: key is not an RSA private key")
	}
	return priv, nil
}

// ThumbprintKID returns the RFC 7638 SHA-256 JWK thumbprint of an RSA public
// key, used as a stable, deterministic key id. The canonical members for an RSA
// key are exactly e, kty, n in lexicographic order with no whitespace.
func ThumbprintKID(pub *rsa.PublicKey) string {
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	canonical := fmt.Sprintf(`{"e":%q,"kty":"RSA","n":%q}`, e, n)
	sum := sha256.Sum256([]byte(canonical))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the two keys tests PASS alongside the rest.

- [ ] **Step 5: Commit**

```bash
git add server/internal/auth/keys.go server/internal/auth/keys_test.go
git commit -m "feat(server): RSA key load/generate and RFC 7638 kid"
```

---

### Task 4: genkey CLI + generate the dev key

**Files:**
- Create: `server/cmd/genkey/main.go`
- Modify: `server/Makefile` (add `gen-jwt-key`), `server/.gitignore` (ignore `.secrets/`)

- [ ] **Step 1: Write `server/cmd/genkey/main.go`**

```go
// Command genkey writes a new RSA private key PEM for JWT signing.
// Run once: make -C server gen-jwt-key
package main

import (
	"flag"
	"log"

	"workout-tracker/server/internal/auth"
)

func main() {
	out := flag.String("out", ".secrets/jwt_private_key.pem", "output path for the PEM private key")
	bits := flag.Int("bits", 3072, "RSA key size in bits")
	flag.Parse()

	if err := auth.GenerateAndWritePEM(*out, *bits); err != nil {
		log.Fatalf("genkey: %v", err)
	}
	log.Printf("genkey: wrote %d-bit RSA private key to %s", *bits, *out)
}
```

- [ ] **Step 2: Add the `.secrets/` ignore**

Append to `server/.gitignore`:

```
# Local signing keys (never commit)
.secrets/
```

(The root `.gitignore` already ignores `*.pem`/`*.key`; this is belt-and-suspenders for the directory.)

- [ ] **Step 3: Add the `gen-jwt-key` Make target**

Append to `server/Makefile` (after the migrate targets):

```makefile

JWT_PRIVATE_KEY_PATH ?= .secrets/jwt_private_key.pem

.PHONY: gen-jwt-key

gen-jwt-key:
	go run ./cmd/genkey -out $(JWT_PRIVATE_KEY_PATH) -bits 3072
```

Recipe lines must be TAB-indented.

- [ ] **Step 4: Generate the dev key and confirm it is ignored**

Run from repo root:

```bash
make -C server gen-jwt-key
git check-ignore server/.secrets/jwt_private_key.pem
```

Expected: the genkey log line prints; `git check-ignore` prints the path (confirming it is ignored). `git status` must NOT show the key file.

- [ ] **Step 5: Commit (the CLI + Makefile + gitignore only — NOT the key)**

```bash
git add server/cmd/genkey/ server/Makefile server/.gitignore
git commit -m "feat(server): genkey utility and gen-jwt-key target"
```

Expected: `git show --stat HEAD` lists `server/cmd/genkey/main.go`, `server/Makefile`, `server/.gitignore` — and NOT `server/.secrets/jwt_private_key.pem`.

---

### Task 5: Extend config (key path, audiences, issuer, TTLs, slog level)

**Files:**
- Modify: `server/internal/config/config.go`
- Modify: `server/internal/config/config_test.go`
- Modify: `server/Makefile` (pass `JWT_PRIVATE_KEY_PATH` to `run`)

- [ ] **Step 1: Replace `server/internal/config/config_test.go`**

```go
package config

import (
	"log/slog"
	"testing"
	"time"
)

func setRequired(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "/run/secrets/jwt.pem")
}

func TestLoad_AppliesDefaults(t *testing.T) {
	setRequired(t)
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("LOG_LEVEL", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":8080" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.JWTIssuer != "workout-tracker" {
		t.Errorf("JWTIssuer: got %q", cfg.JWTIssuer)
	}
	if cfg.APIAudience != "workout-tracker-api" {
		t.Errorf("APIAudience: got %q", cfg.APIAudience)
	}
	if cfg.PowerSyncAudience != "workout-tracker-powersync" {
		t.Errorf("PowerSyncAudience: got %q", cfg.PowerSyncAudience)
	}
	if cfg.AccessTokenTTL != 15*time.Minute {
		t.Errorf("AccessTokenTTL: got %v", cfg.AccessTokenTTL)
	}
	if cfg.RefreshTokenTTL != 720*time.Hour {
		t.Errorf("RefreshTokenTTL: got %v", cfg.RefreshTokenTTL)
	}
	if cfg.PowerSyncTokenTTL != 5*time.Minute {
		t.Errorf("PowerSyncTokenTTL: got %v", cfg.PowerSyncTokenTTL)
	}
}

func TestLoad_RespectsExplicitValues(t *testing.T) {
	setRequired(t)
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("ACCESS_TOKEN_TTL", "30m")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.SlogLevel() != slog.LevelDebug {
		t.Errorf("SlogLevel: got %v, want debug", cfg.SlogLevel())
	}
	if cfg.AccessTokenTTL != 30*time.Minute {
		t.Errorf("AccessTokenTTL: got %v", cfg.AccessTokenTTL)
	}
}

func TestLoad_FailsWhenDatabaseURLMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "/run/secrets/jwt.pem")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when DATABASE_URL is empty")
	}
}

func TestLoad_FailsWhenKeyPathMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when JWT_PRIVATE_KEY_PATH is empty")
	}
}

func TestLoad_FailsOnBadDuration(t *testing.T) {
	setRequired(t)
	t.Setenv("ACCESS_TOKEN_TTL", "not-a-duration")
	if _, err := Load(); err == nil {
		t.Fatal("expected error for malformed ACCESS_TOKEN_TTL")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build/compile failures — `cfg.JWTIssuer undefined`, `cfg.SlogLevel undefined`, etc.

- [ ] **Step 3: Replace `server/internal/config/config.go`**

```go
// Package config loads server configuration from environment variables.
package config

import (
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr    string
	DatabaseURL string
	LogLevel    string

	JWTPrivateKeyPath string
	JWTIssuer         string
	APIAudience       string
	PowerSyncAudience string
	PowerSyncURL      string

	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	PowerSyncTokenTTL time.Duration
}

func Load() (Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	keyPath := os.Getenv("JWT_PRIVATE_KEY_PATH")
	if keyPath == "" {
		return Config{}, fmt.Errorf("JWT_PRIVATE_KEY_PATH is required")
	}

	accessTTL, err := getDuration("ACCESS_TOKEN_TTL", 15*time.Minute)
	if err != nil {
		return Config{}, err
	}
	refreshTTL, err := getDuration("REFRESH_TOKEN_TTL", 720*time.Hour)
	if err != nil {
		return Config{}, err
	}
	psTTL, err := getDuration("POWERSYNC_TOKEN_TTL", 5*time.Minute)
	if err != nil {
		return Config{}, err
	}

	return Config{
		HTTPAddr:          getString("HTTP_ADDR", ":8080"),
		DatabaseURL:       dbURL,
		LogLevel:          getString("LOG_LEVEL", "info"),
		JWTPrivateKeyPath: keyPath,
		JWTIssuer:         getString("JWT_ISSUER", "workout-tracker"),
		APIAudience:       getString("API_AUDIENCE", "workout-tracker-api"),
		PowerSyncAudience: getString("POWERSYNC_AUDIENCE", "workout-tracker-powersync"),
		PowerSyncURL:      getString("POWERSYNC_URL", "http://localhost:8080"),
		AccessTokenTTL:    accessTTL,
		RefreshTokenTTL:   refreshTTL,
		PowerSyncTokenTTL: psTTL,
	}, nil
}

// SlogLevel maps the LOG_LEVEL string to a slog.Level (default info).
func (c Config) SlogLevel() slog.Level {
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func getString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getDuration(key string, def time.Duration) (time.Duration, error) {
	v := os.Getenv(key)
	if v == "" {
		return def, nil
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return d, nil
}
```

- [ ] **Step 4: Pass the key path to the `run` target**

In `server/Makefile`, replace the existing `run:` recipe so it provides `JWT_PRIVATE_KEY_PATH` (the variable was defined in Task 4):

```makefile
run:
	DATABASE_URL=$(DATABASE_URL) JWT_PRIVATE_KEY_PATH=$(JWT_PRIVATE_KEY_PATH) go run ./cmd/server
```

- [ ] **Step 5: Run test to verify it passes**

Run: `make -C server test`
Expected: all config tests PASS.

- [ ] **Step 6: Commit**

```bash
git add server/internal/config/ server/Makefile
git commit -m "feat(server): config for keys, audiences, issuer, and token TTLs"
```

---

### Task 6: Harden main.go (slog level + HTTP timeouts)

This closes the two carry-over findings from the Plan 2 review. `main.go` still wires `api.NewRouter(pool)` (old signature) — route wiring changes later in Task 16.

**Files:**
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Replace `server/cmd/server/main.go`**

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
	cfg, err := config.Load()
	if err != nil {
		slog.Error("config load failed", "err", err)
		os.Exit(1)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.SlogLevel()}))
	slog.SetDefault(logger)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("db connect failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           api.NewRouter(pool),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
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

- [ ] **Step 2: Build and smoke-test (the dev key now exists; config requires its path)**

Run from repo root (Postgres up from Plan 1; key generated in Task 4). Launch the
**built binary directly** rather than `make run`: `make run` shells out to
`go run`, which does not forward `SIGTERM` to its compiled child, so a
backgrounded `kill -TERM $!` would kill the wrapper and orphan the server on
`:8080`. Running the binary makes `$!` the real PID and exercises graceful shutdown.

```bash
make -C server build
set -a && . infra/.env && set +a
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB?sslmode=disable" \
JWT_PRIVATE_KEY_PATH=server/.secrets/jwt_private_key.pem \
  server/bin/server > /tmp/wt-p3-t6.log 2>&1 &
SERVER_PID=$!
sleep 2
curl -sS -o /dev/null -w "healthz=%{http_code}\n" http://localhost:8080/healthz
curl -sS -o /dev/null -w "readyz=%{http_code}\n" http://localhost:8080/readyz
kill -TERM "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
grep -c '"level":"INFO"' /tmp/wt-p3-t6.log
```

Expected: `healthz=200`, `readyz=200`, and at least one INFO log line, and the log ends with `"msg":"server stopped"` (graceful shutdown ran). (If `LOG_LEVEL=debug` were set, debug lines would appear — proving the carry-over wiring works.)

- [ ] **Step 3: Commit**

```bash
git add server/cmd/server/main.go
git commit -m "fix(server): wire log level into slog and add HTTP server timeouts"
```

---

### Task 7: JWKS document + handler

**Files:**
- Create: `server/internal/auth/jwks.go`
- Create: `server/internal/auth/jwks_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/jwks_test.go`:

```go
package auth

import (
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func testKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	priv, err := rsaTestKey()
	if err != nil {
		t.Fatalf("generate test key: %v", err)
	}
	return priv
}

func TestPublicJWK_HasExpectedFields(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)

	jwk := PublicJWK(&priv.PublicKey, kid)
	if jwk.Kty != "RSA" || jwk.Alg != "RS256" {
		t.Errorf("kty/alg: got %q/%q", jwk.Kty, jwk.Alg)
	}
	if jwk.Kid != kid {
		t.Errorf("kid: got %q, want %q", jwk.Kid, kid)
	}
	// The common RSA exponent 65537 encodes to "AQAB".
	if jwk.E != "AQAB" {
		t.Errorf("e: got %q, want AQAB", jwk.E)
	}
	if jwk.N == "" {
		t.Error("n is empty")
	}
}

func TestJWKSHandler_ServesOneKey(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil)
	JWKSHandler(&priv.PublicKey, kid).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("content-type: got %q", ct)
	}
	var doc JWKS
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(doc.Keys) != 1 || doc.Keys[0].Kid != kid {
		t.Errorf("expected one key with kid %q, got %+v", kid, doc.Keys)
	}
}
```

File `server/internal/auth/testhelpers_test.go` (shared test helper — RSA key generation used by jwks/token tests):

```go
package auth

import (
	"crypto/rand"
	"crypto/rsa"
)

// rsaTestKey generates a small RSA key for fast tests.
func rsaTestKey() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, 2048)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: PublicJWK` / `undefined: JWKS` / `undefined: JWKSHandler`.

- [ ] **Step 3: Write the implementation**

File `server/internal/auth/jwks.go`:

```go
package auth

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
)

// JWK is a single JSON Web Key (RSA public key) as served at the JWKS endpoint.
type JWK struct {
	Kty string `json:"kty"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// JWKS is a JSON Web Key Set.
type JWKS struct {
	Keys []JWK `json:"keys"`
}

// PublicJWK builds the JWK for one static RSA public key. n and e are
// Base64urlUInt values (RFC 7518): minimal big-endian bytes, base64url no padding.
func PublicJWK(pub *rsa.PublicKey, kid string) JWK {
	return JWK{
		Kty: "RSA",
		Use: "sig",
		Alg: "RS256",
		Kid: kid,
		N:   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
	}
}

// JWKSHandler serves the immutable JWKS. The body is marshaled once at startup;
// the endpoint must be unauthenticated so PowerSync can poll it.
func JWKSHandler(pub *rsa.PublicKey, kid string) http.HandlerFunc {
	body, _ := json.Marshal(JWKS{Keys: []JWK{PublicJWK(pub, kid)}})
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		_, _ = w.Write(body)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the JWKS tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/auth/jwks.go server/internal/auth/jwks_test.go server/internal/auth/testhelpers_test.go
git commit -m "feat(server): JWKS document and unauthenticated handler"
```

---

### Task 8: JWT signer + verifier (RS256)

**Files:**
- Create: `server/internal/auth/token.go`
- Create: `server/internal/auth/token_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/token_test.go`:

```go
package auth

import (
	"testing"
	"time"
)

func TestSignAndVerify_RoundTrips(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, err := signer.Sign("user-123", "workout-tracker-api", 5*time.Minute)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	claims, err := verifier.Verify(tok, "workout-tracker-api")
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.Subject != "user-123" {
		t.Errorf("sub: got %q", claims.Subject)
	}
}

func TestVerify_RejectsWrongAudience(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-powersync", time.Minute)
	if _, err := verifier.Verify(tok, "workout-tracker-api"); err == nil {
		t.Fatal("expected audience mismatch to fail")
	}
}

func TestVerify_RejectsExpiredToken(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-api", -1*time.Minute) // already expired
	if _, err := verifier.Verify(tok, "workout-tracker-api"); err == nil {
		t.Fatal("expected expired token to fail")
	}
}

func TestSign_SetsKidHeader(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-api", time.Minute)
	parsed, _, err := newParserHeader(tok)
	if err != nil {
		t.Fatalf("parse header: %v", err)
	}
	if parsed != kid {
		t.Errorf("kid header: got %q, want %q", parsed, kid)
	}
}
```

File `server/internal/auth/token_header_test.go` (helper to read the `kid` header without verifying):

```go
package auth

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
)

// newParserHeader extracts the kid from a JWT's header segment (test helper).
func newParserHeader(token string) (string, bool, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", false, errors.New("not a JWT")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", false, err
	}
	var h struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(raw, &h); err != nil {
		return "", false, err
	}
	return h.Kid, h.Alg == "RS256", nil
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: NewSigner` / `undefined: NewVerifier` / `undefined: Claims`.

- [ ] **Step 3: Write the implementation**

File `server/internal/auth/token.go`:

```go
package auth

import (
	"crypto/rsa"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims is the JWT claim set for both the API access token and the PowerSync token.
type Claims struct {
	jwt.RegisteredClaims
}

// Signer mints RS256 JWTs with a stable kid header.
type Signer struct {
	priv   *rsa.PrivateKey
	kid    string
	issuer string
}

func NewSigner(priv *rsa.PrivateKey, kid, issuer string) *Signer {
	return &Signer{priv: priv, kid: kid, issuer: issuer}
}

// Sign mints an RS256 JWT for subject with the given audience and lifetime.
func (s *Signer) Sign(subject, audience string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			Audience:  jwt.ClaimStrings{audience},
			Issuer:    s.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = s.kid
	return token.SignedString(s.priv)
}

// Verifier validates RS256 JWTs against the public key.
type Verifier struct {
	pub    *rsa.PublicKey
	issuer string
}

func NewVerifier(pub *rsa.PublicKey, issuer string) *Verifier {
	return &Verifier{pub: pub, issuer: issuer}
}

// Verify parses and validates a token, requiring RS256, a present exp, the
// expected audience, and the configured issuer.
func (v *Verifier) Verify(tokenStr, audience string) (*Claims, error) {
	claims := &Claims{}
	_, err := jwt.ParseWithClaims(
		tokenStr,
		claims,
		func(t *jwt.Token) (any, error) { return v.pub, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}),
		jwt.WithExpirationRequired(),
		jwt.WithAudience(audience),
		jwt.WithIssuer(v.issuer),
	)
	if err != nil {
		return nil, err
	}
	return claims, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: all four token tests PASS. (The expired-token test relies on `WithExpirationRequired` + default exp validation; the wrong-audience test on `WithAudience`; the alg pinning on `WithValidMethods`.)

- [ ] **Step 5: Commit**

```bash
git add server/internal/auth/token.go server/internal/auth/token_test.go server/internal/auth/token_header_test.go
git commit -m "feat(server): RS256 JWT signer and verifier"
```

---

### Task 9: Migration 0003 — refresh_tokens table

**Files:**
- Create: `server/db/migrations/00003_create_refresh_tokens.sql`

- [ ] **Step 1: Write the migration**

File `server/db/migrations/00003_create_refresh_tokens.sql`:

```sql
-- +goose Up
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id   UUID NOT NULL,
    token_hash  BYTEA NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ
);

CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

-- +goose Down
DROP TABLE refresh_tokens;
```

- [ ] **Step 2: Apply and verify**

Run from repo root (Postgres up):

```bash
make -C server migrate-up
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\d refresh_tokens'
```

Expected: `migrate-up` prints `OK   00003_create_refresh_tokens.sql`; `\d refresh_tokens` shows the eight columns, the unique index on `token_hash`, the FK to `users(id)`, and the `family`/`user` indexes.

- [ ] **Step 3: Verify rollback then re-apply**

```bash
make -C server migrate-down
make -C server migrate-up
make -C server migrate-status
```

Expected: down drops the table; up re-creates it; status shows all three migrations `Applied`.

- [ ] **Step 4: Commit**

```bash
git add server/db/migrations/00003_create_refresh_tokens.sql
git commit -m "feat(server): migration 0003 — create refresh_tokens table"
```

---

### Task 10: User store + createuser CLI

**Files:**
- Create: `server/internal/auth/users.go`
- Create: `server/internal/auth/users_test.go`
- Create: `server/cmd/createuser/main.go`
- Modify: `server/Makefile` (add `create-user`)

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/users_test.go`:

```go
package auth

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping DB integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestUserStore_FindByEmail(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	email := "find-" + randomSuffix() + "@example.com"

	_, err := pool.Exec(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)`, email, "hash")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE email=$1`, email) })

	store := NewUserStore(pool)
	u, err := store.FindByEmail(ctx, email)
	if err != nil {
		t.Fatalf("FindByEmail: %v", err)
	}
	if u.PasswordHash != "hash" || u.ID == "" {
		t.Errorf("unexpected user: %+v", u)
	}
}

func TestUserStore_FindByEmail_NotFound(t *testing.T) {
	pool := testPool(t)
	store := NewUserStore(pool)
	if _, err := store.FindByEmail(context.Background(), "nobody@example.com"); err != ErrUserNotFound {
		t.Errorf("got %v, want ErrUserNotFound", err)
	}
}
```

File `server/internal/auth/random_test.go` (test-only unique-suffix helper):

```go
package auth

import (
	"crypto/rand"
	"encoding/hex"
)

func randomSuffix() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: NewUserStore` / `undefined: ErrUserNotFound`.

- [ ] **Step 3: Write `server/internal/auth/users.go`**

```go
package auth

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrUserNotFound is returned when no user matches the lookup.
var ErrUserNotFound = errors.New("auth: user not found")

// User is the minimal user record needed for authentication.
type User struct {
	ID           string
	PasswordHash string
}

// UserStore reads users from Postgres.
type UserStore struct {
	pool *pgxpool.Pool
}

func NewUserStore(pool *pgxpool.Pool) *UserStore {
	return &UserStore{pool: pool}
}

// FindByEmail returns the user with the given email, or ErrUserNotFound.
func (s *UserStore) FindByEmail(ctx context.Context, email string) (*User, error) {
	var u User
	err := s.pool.QueryRow(ctx,
		`SELECT id::text, password_hash FROM users WHERE email = $1`, email,
	).Scan(&u.ID, &u.PasswordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}
```

- [ ] **Step 4: Write `server/cmd/createuser/main.go`**

```go
// Command createuser inserts a user with a hashed password.
// Run: make -C server create-user EMAIL=me@example.com PASSWORD=secret
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"workout-tracker/server/internal/auth"
)

func main() {
	email := flag.String("email", "", "user email")
	password := flag.String("password", "", "user password")
	flag.Parse()

	if *email == "" || *password == "" {
		log.Fatal("createuser: -email and -password are required")
	}
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("createuser: DATABASE_URL is required")
	}

	hash, err := auth.HashPassword(*password)
	if err != nil {
		log.Fatalf("createuser: hash: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("createuser: db: %v", err)
	}
	defer pool.Close()

	if _, err := pool.Exec(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)`, *email, hash); err != nil {
		log.Fatalf("createuser: insert: %v", err)
	}
	log.Printf("createuser: created user %s", *email)
}
```

- [ ] **Step 5: Add the `create-user` Make target**

Append to `server/Makefile`:

```makefile

.PHONY: create-user

create-user:
	DATABASE_URL=$(DATABASE_URL) go run ./cmd/createuser -email $(EMAIL) -password $(PASSWORD)
```

- [ ] **Step 6: Run tests + a real createuser**

Run from repo root (Postgres up, migrations applied):

```bash
make -C server test
make -C server create-user EMAIL=me@example.com PASSWORD=devpassword
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT email FROM users WHERE email='me@example.com';"
```

Expected: tests PASS (user-store integration tests run against the dev DB); createuser logs success; psql prints `me@example.com`.

- [ ] **Step 7: Commit**

```bash
git add server/internal/auth/users.go server/internal/auth/users_test.go server/internal/auth/random_test.go server/cmd/createuser/ server/Makefile
git commit -m "feat(server): user lookup store and createuser utility"
```

---

### Task 11: Refresh-token store (rotation + reuse detection)

**Files:**
- Create: `server/internal/auth/refresh_store.go`
- Create: `server/internal/auth/refresh_store_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/auth/refresh_store_test.go` (uses `testPool` from `users_test.go` and `randomSuffix` from `random_test.go`, both in this package):

```go
package auth

import (
	"context"
	"testing"
	"time"
)

func TestRefreshStore_RotateAndReuseDetection(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()

	email := "rt-" + randomSuffix() + "@example.com"
	var userID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1,$2) RETURNING id::text`,
		email, "hash").Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE id=$1::uuid`, userID) })

	store := NewRefreshStore(pool, time.Hour)

	first, err := store.Issue(ctx, userID)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	gotUser, second, err := store.Rotate(ctx, first)
	if err != nil {
		t.Fatalf("Rotate: %v", err)
	}
	if gotUser != userID {
		t.Errorf("rotate user: got %q want %q", gotUser, userID)
	}
	if second == first {
		t.Error("rotated token should differ from the original")
	}

	if _, _, err := store.Rotate(ctx, first); err != ErrRefreshReused {
		t.Errorf("reuse: got %v, want ErrRefreshReused", err)
	}
	if _, _, err := store.Rotate(ctx, second); err == nil {
		t.Error("expected second token to be revoked after reuse of first")
	}
}

func TestRefreshStore_RotateUnknownToken(t *testing.T) {
	pool := testPool(t)
	store := NewRefreshStore(pool, time.Hour)
	if _, _, err := store.Rotate(context.Background(), "not-a-real-token"); err != ErrInvalidRefreshToken {
		t.Errorf("got %v, want ErrInvalidRefreshToken", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: NewRefreshStore` / `undefined: ErrRefreshReused` / `undefined: ErrInvalidRefreshToken`.

- [ ] **Step 3: Write `server/internal/auth/refresh_store.go`**

```go
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalidRefreshToken = errors.New("auth: invalid or expired refresh token")
	ErrRefreshReused       = errors.New("auth: refresh token reuse detected")
)

// RefreshStore manages opaque refresh tokens: it stores only their SHA-256
// hashes, rotates them on every use, and revokes the whole token family when a
// consumed token is presented again (reuse detection).
type RefreshStore struct {
	pool *pgxpool.Pool
	ttl  time.Duration
}

func NewRefreshStore(pool *pgxpool.Pool, ttl time.Duration) *RefreshStore {
	return &RefreshStore{pool: pool, ttl: ttl}
}

// newToken returns a random opaque token (base64url) and its SHA-256 hash.
func newToken() (plain string, hash []byte, err error) {
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		return "", nil, err
	}
	plain = base64.RawURLEncoding.EncodeToString(raw)
	sum := sha256.Sum256([]byte(plain))
	return plain, sum[:], nil
}

func hashToken(plain string) []byte {
	sum := sha256.Sum256([]byte(plain))
	return sum[:]
}

// Issue creates a brand-new token in a new family for the user.
func (s *RefreshStore) Issue(ctx context.Context, userID string) (string, error) {
	plain, hash, err := newToken()
	if err != nil {
		return "", err
	}
	_, err = s.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
		 VALUES ($1::uuid, gen_random_uuid(), $2, $3)`,
		userID, hash, time.Now().Add(s.ttl))
	if err != nil {
		return "", fmt.Errorf("issue refresh token: %w", err)
	}
	return plain, nil
}

// Rotate atomically consumes the presented token and issues a successor in the
// same family. The consume is a single conditional UPDATE ... RETURNING run
// inside a transaction, so two concurrent rotations of the same token cannot
// both succeed: Postgres takes a row lock, the loser re-evaluates the
// `used_at IS NULL` predicate after the winner commits, matches zero rows, and
// falls into the reuse path. If the presented token exists but was already used
// or revoked, the whole family is revoked and ErrRefreshReused is returned.
func (s *RefreshStore) Rotate(ctx context.Context, presented string) (string, string, error) {
	hash := hashToken(presented)

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Atomic conditional consume: matches at most once, only if the token is live.
	var userID, familyID string
	err = tx.QueryRow(ctx,
		`UPDATE refresh_tokens SET used_at = NOW()
		 WHERE token_hash = $1 AND used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW()
		 RETURNING user_id::text, family_id::text`, hash,
	).Scan(&userID, &familyID)
	if err == nil {
		newPlain, newHash, nerr := newToken()
		if nerr != nil {
			return "", "", nerr
		}
		if _, ierr := tx.Exec(ctx,
			`INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
			 VALUES ($1::uuid, $2::uuid, $3, $4)`,
			userID, familyID, newHash, time.Now().Add(s.ttl)); ierr != nil {
			return "", "", ierr
		}
		if cerr := tx.Commit(ctx); cerr != nil {
			return "", "", cerr
		}
		return userID, newPlain, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", "", err
	}

	// The token is not live. Classify: genuine reuse (used/revoked) -> revoke the
	// whole family; merely expired or entirely unknown -> invalid, no family action.
	var familyID2 string
	var usedAt, revokedAt *time.Time
	derr := tx.QueryRow(ctx,
		`SELECT family_id::text, used_at, revoked_at FROM refresh_tokens WHERE token_hash = $1`, hash,
	).Scan(&familyID2, &usedAt, &revokedAt)
	if errors.Is(derr, pgx.ErrNoRows) {
		return "", "", ErrInvalidRefreshToken
	}
	if derr != nil {
		return "", "", derr
	}
	if usedAt != nil || revokedAt != nil {
		if _, rerr := tx.Exec(ctx,
			`UPDATE refresh_tokens SET revoked_at = NOW()
			 WHERE family_id = $1::uuid AND revoked_at IS NULL`, familyID2); rerr != nil {
			return "", "", rerr
		}
		if cerr := tx.Commit(ctx); cerr != nil {
			return "", "", cerr
		}
		return "", "", ErrRefreshReused
	}
	return "", "", ErrInvalidRefreshToken // exists but expired
}

// RevokeFamily revokes the entire family of the presented token (logout).
// It is idempotent: an unknown token is a no-op.
func (s *RefreshStore) RevokeFamily(ctx context.Context, presented string) error {
	hash := hashToken(presented)
	var familyID string
	err := s.pool.QueryRow(ctx,
		`SELECT family_id::text FROM refresh_tokens WHERE token_hash = $1`, hash,
	).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = NOW()
		 WHERE family_id = $1::uuid AND revoked_at IS NULL`, familyID)
	return err
}
```

> **Follow-up (deferred):** consumed/expired `refresh_tokens` rows accumulate over time. A periodic `DELETE FROM refresh_tokens WHERE expires_at < NOW()` (a cron job or a later cleanup task) keeps the table bounded. Not needed for a single user in Plan 3 — documented here so it isn't forgotten.

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the refresh-store integration tests PASS against the dev DB.

- [ ] **Step 5: Commit**

```bash
git add server/internal/auth/refresh_store.go server/internal/auth/refresh_store_test.go
git commit -m "feat(server): refresh-token store with rotation and reuse detection"
```

---

### Task 12: Auth middleware

**Files:**
- Create: `server/internal/api/middleware_auth.go`
- Create: `server/internal/api/middleware_auth_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/api/middleware_auth_test.go`:

```go
package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"workout-tracker/server/internal/auth"
)

func newAuthPair(t *testing.T) (*auth.Signer, *auth.Verifier) {
	t.Helper()
	priv, err := rsaKeyForTest()
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	kid := auth.ThumbprintKID(&priv.PublicKey)
	return auth.NewSigner(priv, kid, "workout-tracker"), auth.NewVerifier(&priv.PublicKey, "workout-tracker")
}

func TestRequireAuth_AllowsValidToken(t *testing.T) {
	signer, verifier := newAuthPair(t)
	tok, _ := signer.Sign("user-42", "workout-tracker-api", time.Minute)

	var seenUser string
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			seenUser, _ = UserIDFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if seenUser != "user-42" {
		t.Errorf("user: got %q", seenUser)
	}
}

func TestRequireAuth_RejectsMissingHeader(t *testing.T) {
	_, verifier := newAuthPair(t)
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/protected", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestRequireAuth_RejectsBadToken(t *testing.T) {
	_, verifier := newAuthPair(t)
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer not.a.jwt")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}
```

File `server/internal/api/testhelpers_test.go` (shared RSA key generator for api tests):

```go
package api

import (
	"crypto/rand"
	"crypto/rsa"
)

func rsaKeyForTest() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, 2048)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: RequireAuth` / `undefined: UserIDFromContext`.

- [ ] **Step 3: Write `server/internal/api/middleware_auth.go`**

```go
package api

import (
	"context"
	"net/http"
	"strings"

	"workout-tracker/server/internal/auth"
)

type ctxKey int

const userIDKey ctxKey = iota

// RequireAuth verifies the Bearer access token and stores the user id (the token
// subject) in the request context. It rejects with 401 on any failure.
func RequireAuth(v *auth.Verifier, audience string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			token, ok := strings.CutPrefix(header, "Bearer ")
			if !ok || token == "" {
				writeJSONError(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			claims, err := v.Verify(token, audience)
			if err != nil {
				writeJSONError(w, http.StatusUnauthorized, "invalid token")
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, claims.Subject)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserIDFromContext returns the authenticated user id set by RequireAuth.
func UserIDFromContext(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(userIDKey).(string)
	return id, ok
}
```

File `server/internal/api/errors.go` (shared JSON error writer used by middleware and handlers):

```go
package api

import (
	"encoding/json"
	"net/http"
)

// writeJSONError writes a structured error body: {"error":{"message":"..."}}.
func writeJSONError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]string{"message": message},
	})
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the three middleware tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/api/middleware_auth.go server/internal/api/errors.go server/internal/api/middleware_auth_test.go server/internal/api/testhelpers_test.go
git commit -m "feat(server): bearer-token auth middleware"
```

---

### Task 13: Login / refresh / logout handlers

Handlers depend on small interfaces (fakes in tests), keeping the DB out of handler unit tests.

**Files:**
- Create: `server/internal/api/auth_handlers.go`
- Create: `server/internal/api/auth_handlers_test.go`

- [ ] **Step 1: Write the failing test**

File `server/internal/api/auth_handlers_test.go`:

```go
package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"workout-tracker/server/internal/auth"
)

// --- fakes ---

type fakeUsers struct {
	user *auth.User
	err  error
}

func (f *fakeUsers) FindByEmail(_ context.Context, _ string) (*auth.User, error) {
	return f.user, f.err
}

type fakeRefresh struct {
	issue       string
	rotateUser  string
	rotateTok   string
	rotateErr   error
	revokeCalls int
}

func (f *fakeRefresh) Issue(context.Context, string) (string, error) { return f.issue, nil }
func (f *fakeRefresh) Rotate(context.Context, string) (string, string, error) {
	return f.rotateUser, f.rotateTok, f.rotateErr
}
func (f *fakeRefresh) RevokeFamily(context.Context, string) error { f.revokeCalls++; return nil }

func newHandler(t *testing.T, users UserFinder, refresh RefreshManager) *AuthHandler {
	t.Helper()
	priv, _ := rsaKeyForTest()
	kid := auth.ThumbprintKID(&priv.PublicKey)
	signer := auth.NewSigner(priv, kid, "workout-tracker")
	return NewAuthHandler(AuthConfig{
		Users:             users,
		Refresh:           refresh,
		Signer:            signer,
		APIAudience:       "workout-tracker-api",
		PowerSyncAudience: "workout-tracker-powersync",
		PowerSyncURL:      "http://powersync:8080",
		AccessTTL:         15 * time.Minute,
		PowerSyncTTL:      5 * time.Minute,
	})
}

func TestLogin_Succeeds(t *testing.T) {
	hash, _ := auth.HashPassword("devpassword")
	h := newHandler(t, &fakeUsers{user: &auth.User{ID: "u1", PasswordHash: hash}}, &fakeRefresh{issue: "refresh-xyz"})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"me@example.com","password":"devpassword"}`))
	h.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["access_token"] == "" || body["refresh_token"] != "refresh-xyz" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestLogin_RejectsWrongPassword(t *testing.T) {
	hash, _ := auth.HashPassword("devpassword")
	h := newHandler(t, &fakeUsers{user: &auth.User{ID: "u1", PasswordHash: hash}}, &fakeRefresh{})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"me@example.com","password":"WRONG"}`))
	h.Login(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestLogin_RejectsUnknownUser(t *testing.T) {
	h := newHandler(t, &fakeUsers{err: auth.ErrUserNotFound}, &fakeRefresh{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"ghost@example.com","password":"x"}`))
	h.Login(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestRefresh_RotatesToken(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{rotateUser: "u1", rotateTok: "refresh-new"})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh",
		strings.NewReader(`{"refresh_token":"refresh-old"}`))
	h.Refresh(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["refresh_token"] != "refresh-new" || body["access_token"] == "" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestRefresh_RejectsReuse(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{rotateErr: auth.ErrRefreshReused})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh",
		strings.NewReader(`{"refresh_token":"reused"}`))
	h.Refresh(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestLogout_RevokesFamily(t *testing.T) {
	fr := &fakeRefresh{}
	h := newHandler(t, &fakeUsers{}, fr)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/logout",
		strings.NewReader(`{"refresh_token":"r"}`))
	h.Logout(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204", rec.Code)
	}
	if fr.revokeCalls != 1 {
		t.Errorf("revoke calls: got %d, want 1", fr.revokeCalls)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `undefined: AuthHandler` / `undefined: NewAuthHandler` / `undefined: UserFinder` / `undefined: RefreshManager` / `undefined: AuthConfig`.

- [ ] **Step 3: Write `server/internal/api/auth_handlers.go`**

```go
package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"workout-tracker/server/internal/auth"
)

// UserFinder looks up users for login.
type UserFinder interface {
	FindByEmail(ctx context.Context, email string) (*auth.User, error)
}

// RefreshManager issues, rotates, and revokes refresh tokens.
type RefreshManager interface {
	Issue(ctx context.Context, userID string) (string, error)
	Rotate(ctx context.Context, presented string) (userID, newToken string, err error)
	RevokeFamily(ctx context.Context, presented string) error
}

// AuthConfig wires the dependencies of AuthHandler.
type AuthConfig struct {
	Users             UserFinder
	Refresh           RefreshManager
	Signer            *auth.Signer
	APIAudience       string
	PowerSyncAudience string
	PowerSyncURL      string
	AccessTTL         time.Duration
	PowerSyncTTL      time.Duration
}

// AuthHandler serves the /auth/* endpoints.
type AuthHandler struct {
	cfg AuthConfig
}

func NewAuthHandler(cfg AuthConfig) *AuthHandler {
	return &AuthHandler{cfg: cfg}
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	RefreshToken string `json:"refresh_token"`
}

// Login verifies credentials and returns an access JWT plus a refresh token.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" || req.Password == "" {
		writeJSONError(w, http.StatusBadRequest, "email and password are required")
		return
	}

	user, err := h.cfg.Users.FindByEmail(r.Context(), req.Email)
	if err != nil {
		// Same response for unknown user and wrong password (no enumeration).
		writeJSONError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	ok, err := auth.VerifyPassword(req.Password, user.PasswordHash)
	if err != nil || !ok {
		writeJSONError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	h.issueTokens(w, r, user.ID)
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// Refresh rotates the refresh token and returns a fresh access token.
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		writeJSONError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}
	userID, newRefresh, err := h.cfg.Refresh.Rotate(r.Context(), req.RefreshToken)
	if err != nil {
		writeJSONError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	access, err := h.cfg.Signer.Sign(userID, h.cfg.APIAudience, h.cfg.AccessTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint token")
		return
	}
	writeJSON(w, http.StatusOK, tokenResponse{
		AccessToken:  access,
		TokenType:    "Bearer",
		ExpiresIn:    int(h.cfg.AccessTTL.Seconds()),
		RefreshToken: newRefresh,
	})
}

// Logout revokes the refresh token's family. Idempotent.
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		writeJSONError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}
	if err := h.cfg.Refresh.RevokeFamily(r.Context(), req.RefreshToken); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not revoke token")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *AuthHandler) issueTokens(w http.ResponseWriter, r *http.Request, userID string) {
	access, err := h.cfg.Signer.Sign(userID, h.cfg.APIAudience, h.cfg.AccessTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint token")
		return
	}
	refresh, err := h.cfg.Refresh.Issue(r.Context(), userID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not issue refresh token")
		return
	}
	writeJSON(w, http.StatusOK, tokenResponse{
		AccessToken:  access,
		TokenType:    "Bearer",
		ExpiresIn:    int(h.cfg.AccessTTL.Seconds()),
		RefreshToken: refresh,
	})
}
```

Add a shared `writeJSON` helper to `server/internal/api/errors.go` (append):

```go

// writeJSON writes v as a JSON response with the given status.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: all six auth-handler tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/api/auth_handlers.go server/internal/api/errors.go server/internal/api/auth_handlers_test.go
git commit -m "feat(server): login, refresh, and logout handlers"
```

---

### Task 14: PowerSync-token handler

**Files:**
- Modify: `server/internal/api/auth_handlers.go` (add `PowerSyncToken`)
- Modify: `server/internal/api/auth_handlers_test.go` (add the test)

- [ ] **Step 1: Add the failing test**

Append to `server/internal/api/auth_handlers_test.go`:

```go
func TestPowerSyncToken_MintsScopedToken(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/powersync-token", nil)
	// Simulate the auth middleware having authenticated the user.
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, "user-99"))
	h.PowerSyncToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["endpoint"] != "http://powersync:8080" || body["token"] == "" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestPowerSyncToken_RequiresAuthenticatedUser(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/powersync-token", nil)
	h.PowerSyncToken(rec, req) // no user in context
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C server test`
Expected: build failure — `h.PowerSyncToken undefined`.

- [ ] **Step 3: Add the handler**

Append to `server/internal/api/auth_handlers.go`:

```go

type powerSyncTokenResponse struct {
	Endpoint  string `json:"endpoint"`
	Token     string `json:"token"`
	ExpiresAt int64  `json:"expires_at"` // unix seconds; debug aid only
}

// PowerSyncToken mints a short-lived PowerSync JWT for the authenticated user.
// It must be registered behind RequireAuth so UserIDFromContext is populated.
func (h *AuthHandler) PowerSyncToken(w http.ResponseWriter, r *http.Request) {
	userID, ok := UserIDFromContext(r.Context())
	if !ok || userID == "" {
		writeJSONError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	token, err := h.cfg.Signer.Sign(userID, h.cfg.PowerSyncAudience, h.cfg.PowerSyncTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint powersync token")
		return
	}
	writeJSON(w, http.StatusOK, powerSyncTokenResponse{
		Endpoint:  h.cfg.PowerSyncURL,
		Token:     token,
		ExpiresAt: time.Now().Add(h.cfg.PowerSyncTTL).Unix(),
	})
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C server test`
Expected: the two PowerSync-token tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/api/auth_handlers.go server/internal/api/auth_handlers_test.go
git commit -m "feat(server): PowerSync token endpoint"
```

---

### Task 15: Wire routes + main.go

Refactor `NewRouter` to take a dependency struct, register the auth routes and JWKS, and load the signing key in `main.go`.

**Files:**
- Modify: `server/internal/api/router.go`
- Modify: `server/internal/api/healthz_test.go`, `server/internal/api/readyz_test.go` (call-site update)
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Replace `server/internal/api/router.go`**

```go
// Package api defines the HTTP router and handlers for the server.
package api

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"

	"workout-tracker/server/internal/auth"
)

// Pinger is the surface area /readyz needs from the DB pool.
type Pinger interface {
	Ping(ctx context.Context) error
}

// Deps are the dependencies the router wires into handlers and middleware.
type Deps struct {
	Pinger      Pinger
	JWKS        http.HandlerFunc
	Auth        *AuthHandler
	Verifier    *auth.Verifier
	APIAudience string
}

// NewRouter builds the chi router. Auth is nil-safe for the health-only tests:
// when Auth/Verifier/JWKS are nil, only /healthz and /readyz are registered.
func NewRouter(d Deps) *chi.Mux {
	r := chi.NewRouter()
	r.Get("/healthz", Healthz)
	r.Get("/readyz", Readyz(d.Pinger))

	if d.JWKS != nil {
		r.Get("/.well-known/jwks.json", d.JWKS)
	}
	if d.Auth != nil {
		r.Post("/auth/login", d.Auth.Login)
		r.Post("/auth/refresh", d.Auth.Refresh)
		r.Post("/auth/logout", d.Auth.Logout)
		if d.Verifier != nil {
			r.Group(func(pr chi.Router) {
				pr.Use(RequireAuth(d.Verifier, d.APIAudience))
				pr.Post("/auth/powersync-token", d.Auth.PowerSyncToken)
			})
		}
	}
	return r
}
```

- [ ] **Step 2: Update the existing health tests for the new signature**

In `server/internal/api/healthz_test.go`, replace the `NewRouter(&fakePinger{})` call with:

```go
	NewRouter(Deps{Pinger: &fakePinger{}}).ServeHTTP(rec, req)
```

In `server/internal/api/readyz_test.go`, replace both `NewRouter(&fakePinger{})` and `NewRouter(&fakePinger{err: ...})` calls with:

```go
	NewRouter(Deps{Pinger: &fakePinger{}}).ServeHTTP(rec, req)
```
and
```go
	NewRouter(Deps{Pinger: &fakePinger{err: errors.New("connection refused")}}).ServeHTTP(rec, req)
```

- [ ] **Step 3: Replace `server/cmd/server/main.go` to load the key and wire deps**

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
	"workout-tracker/server/internal/auth"
	"workout-tracker/server/internal/config"
	"workout-tracker/server/internal/db"
)

func main() {
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

- [ ] **Step 4: Build + full test run**

Run: `make -C server test && make -C server build`
Expected: every package passes; binary builds.

- [ ] **Step 5: End-to-end smoke test (login → powersync-token → jwks)**

Run from repo root (Postgres up, migrations applied, dev key generated, `me@example.com` created in Task 10):

Launch the built binary directly (Step 4 already ran `make -C server build`), so
`$!` is the real server PID:

```bash
set -a && . infra/.env && set +a
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB?sslmode=disable" \
JWT_PRIVATE_KEY_PATH=server/.secrets/jwt_private_key.pem \
  server/bin/server > /tmp/wt-p3-t15.log 2>&1 &
SERVER_PID=$!
sleep 2

echo "--- jwks ---"
curl -sS http://localhost:8080/.well-known/jwks.json | head -c 200; echo

echo "--- login ---"
LOGIN=$(curl -sS -X POST http://localhost:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"devpassword"}')
echo "$LOGIN" | head -c 200; echo
ACCESS=$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

echo "--- powersync-token ---"
curl -sS -X POST http://localhost:8080/auth/powersync-token \
  -H "Authorization: Bearer $ACCESS" | head -c 200; echo

echo "--- powersync-token without auth (expect 401) ---"
curl -sS -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8080/auth/powersync-token

kill -TERM "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
```

Expected: jwks returns `{"keys":[{"kty":"RSA",...}]}`; login returns a JSON object with `access_token`/`refresh_token`; powersync-token returns `{"endpoint":...,"token":...}`; the unauthenticated powersync-token call prints `401`.

- [ ] **Step 6: Commit**

```bash
git add server/internal/api/router.go server/internal/api/healthz_test.go server/internal/api/readyz_test.go server/cmd/server/main.go
git commit -m "feat(server): wire JWKS and auth routes into the router"
```

---

### Task 16: OpenAPI 3.1 contract

The Go server is hand-written chi, so the spec is documentation + the source for future client codegen. It is NOT served from the server (a `go:embed` cannot reach `../api` outside the server module, and serving a spec on a private Tailscale-only app is unnecessary). Clients (Flutter, web) will generate from this file directly in later plans.

**Files:**
- Create: `api/openapi.yaml`

- [ ] **Step 1: Write `api/openapi.yaml`**

```yaml
openapi: 3.1.0
info:
  title: Workout Tracker API
  version: 0.1.0
  description: >
    Auth surface for the workout-tracker server. Issues a short-lived API access
    JWT plus a rotating refresh token, mints short-lived PowerSync tokens, and
    publishes the RS256 public key as a JWKS.
servers:
  - url: http://localhost:8080
    description: Local development
paths:
  /healthz:
    get:
      summary: Liveness probe
      operationId: getHealthz
      responses:
        "200":
          description: Process is up
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Status"
  /readyz:
    get:
      summary: Readiness probe (checks the database)
      operationId: getReadyz
      responses:
        "200":
          description: Ready
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Status"
        "503":
          description: Database unavailable
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Status"
  /.well-known/jwks.json:
    get:
      summary: JSON Web Key Set (public signing key)
      operationId: getJwks
      responses:
        "200":
          description: The signing key set
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JWKS"
  /auth/login:
    post:
      summary: Exchange email + password for tokens
      operationId: postAuthLogin
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/LoginRequest"
      responses:
        "200":
          description: Authenticated
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TokenResponse"
        "400":
          description: Malformed request
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
        "401":
          description: Invalid credentials
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
  /auth/refresh:
    post:
      summary: Rotate the refresh token and get a fresh access token
      operationId: postAuthRefresh
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/RefreshRequest"
      responses:
        "200":
          description: Rotated
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/TokenResponse"
        "400":
          description: Malformed request
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
        "401":
          description: Invalid or reused refresh token
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
  /auth/logout:
    post:
      summary: Revoke the refresh token family
      operationId: postAuthLogout
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/RefreshRequest"
      responses:
        "204":
          description: Revoked
        "400":
          description: Malformed request
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
  /auth/powersync-token:
    post:
      summary: Mint a short-lived PowerSync token for the authenticated user
      operationId: postAuthPowerSyncToken
      security:
        - bearerAuth: []
      responses:
        "200":
          description: A PowerSync token
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/PowerSyncTokenResponse"
        "401":
          description: Authentication required
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Error"
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  schemas:
    Status:
      type: object
      properties:
        status:
          type: string
      required: [status]
    LoginRequest:
      type: object
      properties:
        email:
          type: string
          format: email
        password:
          type: string
      required: [email, password]
    RefreshRequest:
      type: object
      properties:
        refresh_token:
          type: string
      required: [refresh_token]
    TokenResponse:
      type: object
      properties:
        access_token:
          type: string
        token_type:
          type: string
        expires_in:
          type: integer
        refresh_token:
          type: string
      required: [access_token, token_type, expires_in, refresh_token]
    PowerSyncTokenResponse:
      type: object
      properties:
        endpoint:
          type: string
        token:
          type: string
        expires_at:
          type: integer
      required: [endpoint, token, expires_at]
    JWK:
      type: object
      properties:
        kty:
          type: string
        use:
          type: string
        alg:
          type: string
        kid:
          type: string
        n:
          type: string
        e:
          type: string
      required: [kty, alg, kid, n, e]
    JWKS:
      type: object
      properties:
        keys:
          type: array
          items:
            $ref: "#/components/schemas/JWK"
      required: [keys]
    Error:
      type: object
      properties:
        error:
          type: object
          properties:
            message:
              type: string
          required: [message]
      required: [error]
```

- [ ] **Step 2: Commit**

```bash
git add api/openapi.yaml
git commit -m "docs(api): OpenAPI 3.1 contract for the auth surface"
```

---

### Task 17: OpenAPI lint target (vacuum)

**Files:**
- Modify: `server/Makefile` (add `lint-spec`)

- [ ] **Step 1: Add the `lint-spec` target**

Append to `server/Makefile`:

```makefile

.PHONY: lint-spec

lint-spec:
	go run github.com/daveshanley/vacuum@v0.27.2 lint -d --fail-severity error ../api/openapi.yaml
```

(The target lives in the server Makefile for one consistent `make -C server` entry point; the spec is at the repo-root `api/`, hence `../api/openapi.yaml`.)

- [ ] **Step 2: Run the linter**

Run from repo root:

```bash
make -C server lint-spec
```

Expected: vacuum downloads on first run, then reports results. The spec must pass with **no error-severity** findings (the `--fail-severity error` gate). Warnings (e.g., missing `description` on some fields, missing top-level `tags`) are acceptable and do not fail the target. If any **error** is reported, fix `api/openapi.yaml` until the target exits 0.

- [ ] **Step 3: Commit**

```bash
git add server/Makefile
git commit -m "build(server): add lint-spec target using vacuum"
```

---

### Task 18: PowerSync client_auth config

PowerSync isn't deployed until it joins the stack in a later plan, but the auth contract it must use is known now, so commit the config alongside the auth work. This adds a documented config fragment; it is not wired into a running service yet.

**Files:**
- Create: `powersync/sync-rules.yaml`
- Create: `powersync/powersync.yaml`
- Modify: `powersync/README.md`

- [ ] **Step 1: Write `powersync/powersync.yaml` (service config fragment)**

```yaml
# PowerSync self-hosted service configuration (consumed when the sync service
# joins the compose stack). The client_auth block tells PowerSync to trust JWTs
# signed by the Go API: it fetches the public key from the API's JWKS endpoint
# and requires the token audience to match.
#
# jwks_uri + audience are the definitely-required keys. allow_local_jwks is
# included to permit the plain-HTTP internal JWKS URL (the in-cluster `server`
# host, not public HTTPS); VERIFY this exact key name against the pinned
# PowerSync service image when the service is wired in — if the image rejects an
# unknown key, drop the line (a plain-http internal jwks_uri may already be
# accepted) or rename it per that version's docs.
client_auth:
  jwks_uri: http://server:8080/.well-known/jwks.json
  audience:
    - workout-tracker-powersync
  allow_local_jwks: true
```

- [ ] **Step 2: Write `powersync/sync-rules.yaml` (single-user bucket)**

```yaml
# PowerSync sync rules. Each connected client receives only its own rows,
# keyed by the authenticated user id (the JWT "sub" claim, exposed as
# request.user_id()). Tables are added as later plans introduce them.
bucket_definitions:
  by_user:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM exercises WHERE created_by = bucket.user_id OR is_template = true
```

- [ ] **Step 3: Replace `powersync/README.md`**

```markdown
# powersync/

PowerSync self-hosted service configuration. The service itself joins the
compose stack in a later plan; these files define the auth contract and sync
rules it will use.

## Files

- `powersync.yaml` — the `client_auth` block: PowerSync fetches the Go API's
  JWKS to verify tokens and requires audience `workout-tracker-powersync`. It
  also includes `allow_local_jwks: true` to accept the plain-HTTP internal JWKS
  URL — verify that key name against the pinned PowerSync image when the service
  is wired in (drop or rename it if the image rejects it).
- `sync-rules.yaml` — buckets each client to its own rows by the JWT `sub`
  (`request.user_id()`).

## Auth contract (issued by the Go API)

- PowerSync JWT: `sub` = user UUID, `aud` = `workout-tracker-powersync`,
  RS256, `kid` in the header matching the JWKS, lifetime 5 minutes
  (PowerSync rejects tokens older than 60 minutes).
- The Go API mints these at `POST /auth/powersync-token` (access-token
  authenticated) and serves the public key at `/.well-known/jwks.json`.

## Key rotation

The signing key's `kid` is the RFC 7638 thumbprint, stable across restarts as
long as the same key file is mounted. To rotate: serve both the old and new
public keys in the JWKS, wait for PowerSync to re-fetch (a few minutes), sign
new tokens with the new `kid`, keep the old key until outstanding tokens expire
(at most 60 minutes), then remove it. Never hot-swap a `kid`.
```

- [ ] **Step 4: Validate YAML parses**

Run from repo root:

```bash
python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in ['powersync/powersync.yaml','powersync/sync-rules.yaml']]; print('yaml OK')"
```

Expected: prints `yaml OK`.

- [ ] **Step 5: Commit**

```bash
git add powersync/
git commit -m "feat(powersync): client_auth and sync-rules config for JWKS trust"
```

---

### Task 19: README / runbook updates

**Files:**
- Modify: `server/README.md`
- Modify: `api/README.md`

- [ ] **Step 1: Update `server/README.md`**

Insert a new `## Authentication` section after the existing `## Endpoints` section, and add the new Make targets to the "Useful commands" table. The section to insert:

```markdown
## Authentication

The server issues a short-lived **API access JWT** (`aud=workout-tracker-api`,
default 15m) plus a rotating **opaque refresh token** (default 30d, stored only
as a SHA-256 hash, rotated on every use, whole family revoked on reuse). It also
mints a separate short-lived **PowerSync JWT** (`aud=workout-tracker-powersync`,
default 5m) on demand. Both JWTs are RS256, signed by one RSA keypair whose
public half is published at `/.well-known/jwks.json`.

### One-time setup

1. Generate the signing key (writes `server/.secrets/jwt_private_key.pem`,
   which is gitignored):

       make -C server gen-jwt-key

2. Apply migrations (creates `users`, `exercises`, `refresh_tokens`):

       make -C server migrate-up

3. Create your user:

       make -C server create-user EMAIL=me@example.com PASSWORD=yourpassword

### Auth endpoints

| Path | Method | Auth | Behavior |
| ---- | ------ | ---- | -------- |
| `/.well-known/jwks.json` | GET | none | Public signing key (JWKS) |
| `/auth/login` | POST | none | `{email,password}` → `{access_token, token_type, expires_in, refresh_token}` |
| `/auth/refresh` | POST | none | `{refresh_token}` → rotated tokens |
| `/auth/logout` | POST | none | `{refresh_token}` → 204; revokes the family |
| `/auth/powersync-token` | POST | Bearer access token | → `{endpoint, token, expires_at}` |

### Configuration (additional env vars)

| Env var | Required | Default | Notes |
| ------- | -------- | ------- | ----- |
| `JWT_PRIVATE_KEY_PATH` | yes | — | Path to the PKCS#8 RSA private key PEM |
| `JWT_ISSUER` | no | `workout-tracker` | `iss` claim |
| `API_AUDIENCE` | no | `workout-tracker-api` | Access-token audience |
| `POWERSYNC_AUDIENCE` | no | `workout-tracker-powersync` | PowerSync-token audience |
| `POWERSYNC_URL` | no | `http://localhost:8080` | Endpoint returned to the PowerSync client (set when PowerSync joins) |
| `ACCESS_TOKEN_TTL` | no | `15m` | Access-token lifetime |
| `REFRESH_TOKEN_TTL` | no | `720h` | Refresh-token lifetime |
| `POWERSYNC_TOKEN_TTL` | no | `5m` | PowerSync-token lifetime (< 60m) |
```

Add these rows to the "Useful commands" table:

```markdown
| `make -C server gen-jwt-key`     | Generate the RSA signing key (one-off) |
| `make -C server create-user EMAIL=.. PASSWORD=..` | Create a user |
| `make -C server lint-spec`       | Lint `api/openapi.yaml` with vacuum |
```

- [ ] **Step 2: Update `api/README.md`**

Replace `api/README.md` with:

```markdown
# api/

OpenAPI 3.1 contract for the workout-tracker API — the source of truth for
client codegen (Dart for the phone app, TypeScript for the web app) in later
plans.

- `openapi.yaml` — the spec. Covers the auth surface (`/auth/*`,
  `/.well-known/jwks.json`) and the health probes.

## Lint

    make -C server lint-spec

Runs `vacuum` against `openapi.yaml` with an error-severity gate.

## Client generation (later plans)

- Dart (phone): OpenAPI Generator `dart-dio`.
- TypeScript (web): `openapi-typescript` + `openapi-fetch`.

The server itself is hand-written chi; the spec is not served at runtime.
```

- [ ] **Step 3: Commit**

```bash
git add server/README.md api/README.md
git commit -m "docs: document auth, JWKS, and OpenAPI workflow"
```

---

### Task 20: End-state verification

**Files:** none — verification only, no commit.

- [ ] **Step 1: Clean rebuild + full test suite**

Run from repo root:

```bash
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
sleep 5
make -C server migrate-up
make -C server test
make -C server build
make -C server lint-spec
```

Expected: migrations applied; every Go package passes; binary builds; vacuum reports no error-severity findings.

- [ ] **Step 2: Ensure the dev user exists**

Run from repo root:

```bash
set -a && . infra/.env && set +a
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "SELECT count(*) FROM users WHERE email='me@example.com';"
# If it prints 0, create the user:
# make -C server create-user EMAIL=me@example.com PASSWORD=devpassword
```

Expected: prints `1` (or create the user, then re-check).

- [ ] **Step 3: Full auth flow against the running server**

Run from repo root (Step 1 already ran `make -C server build`; launch the binary
directly so `$!` is the real PID):

```bash
set -a && . infra/.env && set +a
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB?sslmode=disable" \
JWT_PRIVATE_KEY_PATH=server/.secrets/jwt_private_key.pem \
  server/bin/server > /tmp/wt-p3-final.log 2>&1 &
SERVER_PID=$!
sleep 2

# JWKS has exactly one RSA key
curl -sS http://localhost:8080/.well-known/jwks.json \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["keys"][0]["kty"]=="RSA" and d["keys"][0]["e"]=="AQAB"; print("jwks OK", d["keys"][0]["kid"][:12])'

# Login
LOGIN=$(curl -sS -X POST http://localhost:8080/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"devpassword"}')
ACCESS=$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
REFRESH=$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["refresh_token"])')
echo "login OK"

# PowerSync token requires the access token
curl -sS -X POST http://localhost:8080/auth/powersync-token -H "Authorization: Bearer $ACCESS" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["token"] and d["endpoint"]; print("powersync-token OK")'

# Refresh rotates
REFRESH2=$(curl -sS -X POST http://localhost:8080/auth/refresh -H 'Content-Type: application/json' \
  -d "{\"refresh_token\":\"$REFRESH\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["refresh_token"])')
test "$REFRESH2" != "$REFRESH" && echo "refresh rotates OK"

# Reusing the old refresh token is rejected (401) and revokes the family
curl -sS -o /dev/null -w "reuse=%{http_code}\n" -X POST http://localhost:8080/auth/refresh \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH\"}"

# The rotated token is now also dead (family revoked) -> 401
curl -sS -o /dev/null -w "rotated-after-reuse=%{http_code}\n" -X POST http://localhost:8080/auth/refresh \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH2\"}"

kill -TERM "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
```

Expected output includes: `jwks OK <kid>`, `login OK`, `powersync-token OK`, `refresh rotates OK`, `reuse=401`, `rotated-after-reuse=401`.

- [ ] **Step 4: Confirm git state**

Run from repo root:

```bash
git status
git log --oneline bfae17f..HEAD | wc -l
```

Expected: working tree clean; the log shows **19** new commits (Tasks 1–19; Task 20 adds none). Confirm `server/.secrets/jwt_private_key.pem` is NOT tracked: `git ls-files server/.secrets/` prints nothing.

- [ ] **Step 5: No commit (verification only)**

Plan 3 is complete. Next: Plan 4 (PowerSync service in the compose stack — wiring `powersync.yaml`/`sync-rules.yaml` into a running container and validating end-to-end sync).
