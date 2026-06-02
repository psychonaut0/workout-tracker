# Productionize the Android app (Reps) — design

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** Rename the app to **Reps** (`io.github.psychonaut0.reps`), set up a real **release keystore**, and add **signed-release CI** that builds a properly-signed (non-debug) APK on `v*` tags and publishes it to **GitHub Releases**. Removes the debug banner and delivers the standing "Android release CI" goal (server-image CI is already done).

**Builds on:** the existing Android scaffold + the server-image CI (`.github/workflows/build.yml`). Mirrors the homelab's release convention (infra `release.yml`: `v*` tag → GitHub Actions → GitHub Releases via `softprops/action-gh-release`).

## Decisions (locked)
- **Name:** display **"Reps"**; applicationId/namespace **`io.github.psychonaut0.reps`** (real owned reverse-DNS).
- **Keystore + passwords** stored as **GitHub Actions repo secrets** for CI signing.
- **Distribution: GitHub Releases only** (LAN mirror via ct-mgmt deferred).
- Single **universal release APK** (simplest sideload).

## Components

### 1. Rename
- `app/android/app/build.gradle.kts`: `namespace` and `applicationId` → `io.github.psychonaut0.reps`.
- `app/android/app/src/main/AndroidManifest.xml`: `android:label` → `Reps`.
- Move `MainActivity.kt` from `kotlin/dev/psy/workout_tracker/` to `kotlin/io/github/psychonaut0/reps/` and update its `package` to `io.github.psychonaut0.reps` (keeps the package aligned with the namespace; `android:name=".MainActivity"` resolves against the namespace).
- Pubspec `name`/Dart package stays `workout_tracker` (internal; not user-visible) — only the Android identity + label change. (Renaming the Dart package is unnecessary churn and out of scope.)
- **Reinstall:** the new applicationId is a *distinct* app on the device — "Workout Tracker" remains installed until manually removed; "Reps" installs fresh, signs into the homelab (`workout.lan`, existing account), and downloads data (homelab is the source of truth → no data loss).

### 2. Release keystore + signing config
- Generate an RSA-2048 keystore (`keytool -genkeypair -keyalg RSA -keysize 2048 -validity 10000`), alias `reps`. Store the keystore file **outside the repo** (e.g. `~/.android-keystores/reps-release.jks`); never commit it.
- `app/android/key.properties` (gitignored) for **local** release builds:
  ```
  storeFile=/abs/path/reps-release.jks
  storePassword=…
  keyAlias=reps
  keyPassword=…
  ```
- `app/android/app/build.gradle.kts`: load `key.properties` if present; define a `release` `signingConfig` from it; set `buildTypes.release.signingConfig` to it (replacing the current `signingConfigs.getByName("debug")` default). If `key.properties` is absent (e.g. a contributor without the key), fall back to the debug signing so `--release` still builds locally — but CI always has the real key.
- `.gitignore` (app): add `key.properties`, `*.jks`, `*.keystore` (confirm `*.keystore`/`*.jks` aren't already covered).

### 3. Signed-release CI — `.github/workflows/android-release.yml`
- **Trigger:** `push: tags: ['v*']` + `workflow_dispatch`.
- **Permissions:** `contents: write` (create the GitHub Release).
- **Steps:**
  1. `actions/checkout@v4`.
  2. JDK 21 (`actions/setup-java@v4`, temurin 21 — matches the local Gradle JDK).
  3. `subosito/flutter-action@v2` with `flutter-version: 3.44.0` (matches `.fvmrc`).
  4. Decode the keystore from secret: `echo "$KEYSTORE_BASE64" | base64 -d > app/android/app/reps-release.jks` (or an abs path), and write `app/android/key.properties` from the secrets.
  5. `cd app && flutter pub get`.
  6. `flutter build apk --release --build-name=${TAG#v} --build-number=${{ github.run_number }}` (single universal APK; `--split-per-abi` NOT used).
  7. Rename the artifact to `reps-${TAG}.apk` and publish via `softprops/action-gh-release@v2` (files: the APK).
- **GitHub repo secrets** (the user adds these once): `KEYSTORE_BASE64` (base64 of the `.jks`), `KEYSTORE_PASSWORD`, `KEY_ALIAS` (=`reps`), `KEY_PASSWORD`.
- Keep `build.yml` (server image) unchanged; this is a separate workflow with its own paths/trigger.

### 4. Versioning
- A release is cut by tagging `vX.Y.Z`. `--build-name=X.Y.Z` (from the tag) sets `versionName`; `--build-number=<run_number>` sets a monotonic `versionCode`. `pubspec.yaml version` stays as the default source for local builds; CI overrides via the flags.

### 5. Local + dev flow (unchanged where possible)
- `make -C app build-apk` (debug) stays for fast local iteration.
- Add `make -C app build-apk-release` → `flutter build apk --release` (uses `key.properties` locally) for a local signed build.

## Manual one-time steps (cannot be in the repo)
1. Generate the keystore (`keytool …`), keep it safe + backed up (losing it means you can't update-in-place ever again).
2. Add the 4 GitHub Actions secrets.
3. Write local `key.properties` (for local release builds).
These are documented in a `app/android/RELEASE.md` the plan will create.

## Error handling / edge cases
- CI without secrets (e.g. a fork/PR): the workflow only runs on tags/dispatch on the main repo; PRs don't get secrets and don't release. Local builds without `key.properties` fall back to debug signing (still builds).
- Lost keystore: documented as unrecoverable for in-place updates (must reinstall under a fresh key). Backup the keystore.

## Testing / verification
- `flutter analyze` clean; existing app tests pass (rename touches only Android identity, not Dart).
- Local `flutter build apk --release` produces a signed APK with **no debug banner** (verify on-device: install, confirm no red ribbon, confirm release performance, sign into `workout.lan`, data syncs).
- A test tag (e.g. `v0.1.0`) triggers CI → a signed `reps-v0.1.0.apk` appears on GitHub Releases; install it and verify.

## Out of scope
- LAN mirror of the APK (ct-mgmt `infra-mirror`) — deferred.
- Play Store / app bundles (`.aab`); F-Droid.
- Renaming the Dart package or internal identifiers.
- The other standing items (offline-only is done; deferred odds-and-ends).
