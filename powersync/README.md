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
