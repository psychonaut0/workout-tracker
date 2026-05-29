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
