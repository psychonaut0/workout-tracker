# v0.12.0 — in-app OTA updates (GitHub Releases)

**Date:** 2026-06-09
**Status:** Approved (design)
**Scope:** In-app self-update for the sideloaded Android build: check GitHub Releases for a newer signed APK, download it with progress, and launch the Android installer (in-place update — same keystore). No Play Store, no hosted code-push. Includes the prerequisite version-plumbing fix. Android-only (no-op on Linux/desktop). Ships as v0.12.0.

All facts below were confirmed by a parallel investigation (install mechanism, repo versioning, GitHub API) — see this increment's plan for the evidence trail.

---

## 0. Version plumbing (prerequisite)

**Problem (verified):** `app/pubspec.yaml` is stuck at `version: 0.1.0` despite 11 released tags; the Profile footer is a hardcoded `'workout-tracker · v1.0.0'` (`profile_screen.dart:802`); `package_info_plus` is not a dependency; nothing reads a runtime version. The release workflow DOES inject the correct version into each APK via `flutter build apk --release --build-name="${TAG#v}"`, so a release APK's `versionName` is correct (e.g. `0.11.0`) — but it's unread. OTA comparison is impossible until a real runtime version exists.

**Fix:**
- Add `package_info_plus` as a direct dependency.
- Bump `app/pubspec.yaml` to `version: 0.12.0+12` (so local/dev builds report honestly; CI still overrides `--build-name` from the tag).
- Replace the hardcoded footer (`profile_screen.dart:802`) with `PackageInfo.fromPlatform().version` (the existing "Updates" work loads it once; show `· v$version`).
- Add a guard step to `.github/workflows/android-release.yml`: after extracting `TAG`, assert `${TAG#v}` equals the pubspec `version:` (before the `+`); fail the job with a clear message if they differ. This permanently prevents tag/pubspec drift.
- Going-forward discipline (documented in the plan + CLAUDE.md note): bump pubspec `version` to match each `v*` tag.

## 1. `UpdateService` (`app/lib/update/update_service.dart`)

Pure version logic + a thin GitHub fetch; Android-guarded at the edges.

- **Pure semver compare** (unit-tested): `bool isNewer(String remote, String local)` — parses `MAJOR.MINOR.PATCH` (tolerates a leading `v` and a trailing `+build` or `-suffix`, ignoring the suffix), returns true iff remote > local numerically. Equal or older → false. Malformed → false (never offer a bogus update).
- **`Future<UpdateInfo?> checkForUpdate({bool force = false})`**:
  - Returns null immediately if not `Platform.isAndroid`.
  - `GET https://api.github.com/repos/psychonaut0/workout-tracker/releases/latest` via the existing `http` client, header `Accept: application/vnd.github+json`. Send `If-None-Match` with a persisted ETag; on **304** return null (no update, no rate cost). On 200, persist the new ETag.
  - Parse `tag_name`; find the asset whose `name` ends with `.apk` → its `browser_download_url` + `size`. Read the running version from `PackageInfo.fromPlatform().version`.
  - If `isNewer(tag, running)` → return `UpdateInfo(version: tag-without-v, notes: body, apkUrl, sizeBytes)`; else null.
  - Network/parse errors → throw a typed/caught error the UI surfaces as "couldn't check" (never crash; manual button shows the error, auto-check swallows it silently).
- **`UpdateInfo`** = `{String version; String notes; String apkUrl; int sizeBytes;}`.
- **Throttle (auto-check):** persist `lastUpdateCheckMs` in SharedPreferences. The auto path runs only when the toggle is on AND `now - lastUpdateCheckMs > 24h`; it stamps the timestamp on every attempt (success or 304). The manual button passes `force: true` and ignores the throttle.

## 2. Install (`ota_update` ^7.1.0)

- New dep `ota_update: ^7.1.0`. `OtaUpdate().execute(info.apkUrl, destinationFilename: 'reps-update.apk').listen((e) {...})` — drive a progress UI off `OtaStatus.DOWNLOADING` (`e.value` = percent); on `INSTALLING`/installer-launch, treat as success and dismiss our UI (the standard non-system-app path does not reliably emit `INSTALLATION_DONE`; the new version self-confirms on next launch). Surface `DOWNLOAD_ERROR`/`INTERNAL_ERROR`/`PERMISSION_NOT_GRANTED_ERROR`/`CANCELED` as user-facing messages. Leave `usePackageInstaller` default (silent install only benefits system apps; Reps shows the normal OS prompt).
- **Install-permission gate:** before/around `execute`, handle the "install unknown apps" authorization. Prefer reacting to ota_update's `PERMISSION_NOT_GRANTED_ERROR` event → show a `showWDialog` explainer ("Allow installing app updates") → open the system toggle via `ACTION_MANAGE_UNKNOWN_APP_SOURCES`. Mechanism for opening it: a tiny `MethodChannel` (e.g. `reps/installer` → an intent with `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`, data `package:<appId>`) OR `url_launcher` if it can target that intent; the plan picks whichever is cleanest and verifies on-device. After the user returns (app resumed), re-attempt the install.

## 3. UI (Profile → "Updates" group)

A new `_Group(label: <localized "Updates">)` in `profile_screen.dart`:
- **Current version** row (`v$version` from PackageInfo) — replaces/absorbs the old footer.
- **Check for updates** row/button → `checkForUpdate(force: true)`, with states: idle → "Check for updates"; checking → spinner; up-to-date → a transient "You're on the latest version" (snackbar or inline); error → "Couldn't check for updates"; update found → the update dialog.
- **Auto-check toggle** ("Check automatically") → `SettingsService.autoCheckUpdates` (default true), persisted.
- **Update dialog** (`showWDialog`): title "Update available · v$X" + the release notes (`body`, truncated to a few lines) + actions [Later] / [Download & install]. Choosing install runs the ota_update flow behind a progress indicator (a dialog with a `LinearProgressIndicator` driven by the percent, plus a Cancel that calls `OtaUpdate().cancel()`).
- **Auto-check trigger:** on app launch (in `main()` or the shell's first build), if Android + toggle on + throttle elapsed, run `checkForUpdate()` in the background; if it returns an `UpdateInfo`, show the update dialog once (non-blocking — don't gate startup on the network call). Use the root navigator key for the dialog context.

All new strings are ARB keys (`update*`) added to all four locales (en/it/de/es) via the established glossary; the ARB-parity test must stay green.

## 4. Android manifest

`app/android/app/src/main/AndroidManifest.xml`:
- Add `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>`.
- Add the ota_update FileProvider:
  ```xml
  <provider
      android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
      android:authorities="${applicationId}.ota_update_provider"
      android:exported="false"
      android:grantUriPermissions="true">
    <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths"/>
  </provider>
  ```
- Create `app/android/app/src/main/res/xml/filepaths.xml` with `<paths><files-path name="internal_apk_storage" path="ota_update/"/></paths>`.
- Do NOT add `WRITE_EXTERNAL_STORAGE` (ota_update 7.x uses internal storage). Desugaring + HTTPS already in place; `network_security_config` unchanged (GitHub is HTTPS).

## Testing

- **Pure:** `isNewer` matrix — 0.11.0<0.12.0, equal=false, older=false, leading `v`, `+build`/`-suffix` ignored, malformed→false.
- **UpdateService (mocked `http.Client`):** picks the `.apk` asset + returns `UpdateInfo` when remote newer; null when equal/older; null on 304 (and persists/sends ETag); throws/caught on network error; returns null off-Android.
- **SettingsService:** `autoCheckUpdates` default true + persists; `lastUpdateCheckMs` throttle logic (a pure `shouldAutoCheck(lastMs, now, enabled)` helper, unit-tested).
- **ARB parity** for the new `update*` keys (en/it/de/es).
- **On-device (user, the real gate):** manual check finds v-next; the install-permission explainer + system toggle round-trip; download progress; OS installer prompt; the app updates in place and reports the new version; auto-check fires at most once/day and the toggle disables it; non-Android builds are unaffected.

## Out of scope

SHA-256 checksum (Android signature enforcement already rejects tampered/wrong-key APKs at install; HTTPS covers transport); forced/mandatory or staged updates; iOS/desktop self-update; delta/patch updates; downgrade; release-channel/pre-release opt-in (uses `releases/latest`, which excludes pre-releases).
