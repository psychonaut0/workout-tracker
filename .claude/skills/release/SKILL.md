---
name: release
description: Cut a Reps app release — bump pubspec, verify green, merge --no-ff, tag vX.Y.Z, push, watch CI publish the signed APK. Use when asked to release, ship, or tag a new app version.
---

# Reps app release

Publishes `reps-vX.Y.Z.apk` to GitHub Releases via `.github/workflows/android-release.yml` (fires on `v*` tags). The in-app OTA updater picks it up from `releases/latest`. Full signing/setup background: `app/android/RELEASE.md`.

All commands run from the **repo root** (never `cd`).

## Preconditions
- Work is merged or ready to merge to `main`; `make -C app analyze` clean and `make -C app test` green (run them — don't assume).
- If server code changed too: `make -C server test` green (needs the dev Postgres up).

## Steps

1. **Bump the version** in `app/pubspec.yaml`: `version: X.Y.Z+N` — `X.Y.Z` must equal the tag you'll cut (the workflow **hard-fails on mismatch**; it strips `+N` before comparing). Bump `+N` too as repo convention, but note CI stamps the released APK's `versionCode` from the workflow run number (`--build-number=${{ github.run_number }}`, auto-increasing), so pubspec `+N` only affects locally-built APKs. The in-app OTA gate compares `X.Y.Z` semver only.
2. Commit the bump on the feature branch: `chore(app): bump version to X.Y.Z` (Conventional Commits, subject line only).
3. Merge to main with `git merge --no-ff <branch>` (repo convention), then tag:
   ```
   git tag -a vX.Y.Z -m "Reps vX.Y.Z — <short summary>"
   git push origin main && git push origin vX.Y.Z
   ```
4. **Watch CI and confirm the asset** — do not declare success before this:
   ```
   RID=$(gh run list --workflow=android-release.yml --limit 1 --json databaseId -q '.[0].databaseId')
   gh run watch "$RID" --exit-status
   gh release view vX.Y.Z --json assets -q '([.assets[].name] | join(", "))'
   ```
   Expect `completed/success` and the `reps-vX.Y.Z.apk` asset.

## Notes
- Pushes to main that touch `server/**` (or `build.yml` itself) rebuild the **server** image to GHCR — an app-only release merge does NOT trigger it. Either way, production (`ct-workout` LXC) only picks a new image up on a manual redeploy from the separate infra repo (`personal/infra/stacks/ct-workout/`). Server-side fixes are NOT live until that redeploy; say so when relevant.
- If the release must be rolled back: `git revert -m 1 <merge-commit>` on main, bump to a NEW **higher** `X.Y.Z` (the OTA gate compares semver — never reuse or lower), and tag that. Never delete/re-point a published tag.
