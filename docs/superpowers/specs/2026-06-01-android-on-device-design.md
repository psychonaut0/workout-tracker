# Android on-device — Phase 1: installable debug APK

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** Phase 1 of the "run it on my phone" goal. Produce an Android **debug** APK that installs on the Pixel 9 and launches to the login screen. **No backend wiring on the phone yet** — that decision is deferred to Phase 2 (see Out of Scope).

## Why

The whole design handoff is built and validated on Linux desktop (headless smoke). The only way to find the gaps a headless smoke can't — real touch interaction, on-device rendering, actual performance — is to run it on real hardware. The target device is the user's **Pixel 9** (Android). The app currently scaffolds Linux only and there is no Android SDK on the dev machine, so getting an installable APK is a prerequisite to all on-device work.

## Success criteria

1. `make -C app doctor` reports the **Android toolchain ✓** (SDK + licenses + NDK located).
2. `make -C app scaffold-android` generates `app/android/` additively, with applicationId `dev.psy.workout_tracker`, without disturbing existing Dart/Linux files.
3. `make -C app build-apk` produces a debug APK artifact under `app/build/app/outputs/flutter-apk/`.
4. The APK installs on the Pixel 9 via `adb install` and launches to the **login screen** without crashing.
5. `flutter analyze` stays clean and all existing tests still pass (the scaffold must not break the existing build).

Phase 1 is **not** responsible for a successful login or sync — only that the app boots and renders on-device. The login attempt failing (no reachable backend) is expected and acceptable at this phase.

## The four parts

### 1. Android SDK + NDK install (dev machine, `blvcksmall`)

Current state: JDK 26 present, `adb` present, Flutter `enable-android` on, but **no Android SDK** (`flutter doctor`: "Unable to locate Android SDK").

- Install the **Android command-line tools** into a standard location (`$HOME/Android/Sdk`), set `ANDROID_HOME`/`ANDROID_SDK_ROOT` (persisted in the shell profile) and point Flutter at it via `flutter config --android-sdk`.
- Use `sdkmanager` to install: `platform-tools`, a `platforms;android-<API>` matching Flutter 3.44's `compileSdk`, the matching `build-tools`, and the **NDK** version Flutter/AGP request (PowerSync's native `sqlite-core` compiles through Flutter build hooks → NDK is **required**, not optional).
- Accept all SDK licenses (`sdkmanager --licenses` / `flutter doctor --android-licenses`).
- **JDK risk:** system JDK is **26**, newer than the Android Gradle Plugin supports. Plan must verify the AGP/Gradle version Flutter generates and, if needed, install a **JDK 17 or 21** and point Gradle at it (via `org.gradle.java.home` in `android/gradle.properties` or `flutter config --jdk-dir`). Exact JDK choice pinned at plan time against the generated AGP version.

This step is environment setup on the dev machine — no repo changes except possibly a documented env-var note in the runbook.

### 2. Android scaffold (additive)

- New Makefile target mirroring `scaffold-linux`:
  ```
  scaffold-android:
  	$(FLUTTER) create --platforms=android --org dev.psy --project-name workout_tracker .
  ```
  → applicationId `dev.psy.workout_tracker`. (Note: the existing Linux scaffold used `--org io.github.psychonaut0`; applicationId is platform-specific, and `dev.psy` is the user's explicit choice for Android.)
- `flutter create` is additive and generates its own `android/.gitignore` (covers `.gradle/`, `local.properties`, `.cxx/`, keystore artifacts), so repo ignores are mostly handled by the scaffold. Plan verifies the generated `.gitignore` and confirms no secrets/local paths are staged.

### 3. Android config

- **App label:** "Workout Tracker" (in `android/app/src/main/AndroidManifest.xml`).
- **Launcher icon:** keep the default Flutter icon for Phase 1 (custom icon is a deferred polish item).
- **`minSdkVersion`:** pinned to PowerSync's documented Android minimum at plan time (PowerSync requires a recent minSdk; do not guess the integer in the design — the plan pins it precisely, raising Flutter's default if necessary). `targetSdk`/`compileSdk` left at Flutter 3.44 defaults.
- **INTERNET permission:** present by default in Flutter's generated manifest; plan confirms it's there.
- **Cleartext HTTP (network security config):** the backend is `http://…` over Tailscale with **no TLS**, and Android blocks cleartext traffic by default (API 28+). Phase 1's APK only needs to *launch*, but to avoid re-touching the manifest in Phase 2, include a **network-security-config** that permits cleartext to the Tailscale domain (`*.tail1552c5.ts.net`) and localhost, referenced from the manifest. Scoped to those domains rather than a blanket `usesCleartextTraffic=true` so we don't globally weaken the app.

### 4. Build + install

- New Makefile targets:
  ```
  build-apk:
  	$(FLUTTER) build apk --debug
  run-android:
  	$(FLUTTER) run -d android
  ```
- Verify the artifact exists at `app/build/app/outputs/flutter-apk/app-debug.apk`.
- Install path documented: bring the Pixel onto USB (or Tailscale `adb` later), `adb install <apk>`, launch, confirm login screen renders.

## Verification (what "done" means for Phase 1)

1. `make -C app doctor` → Android toolchain ✓.
2. `make -C app analyze` → 0 issues; `make -C app test` → all green (scaffold didn't break anything).
3. `make -C app build-apk` → debug APK produced (native assets / NDK build succeeds — this is the real proof the NDK is wired).
4. On-device: `adb install` succeeds; app launches to login screen; no crash. A failed login (no backend) is expected and fine.

## Out of scope (deferred to Phase 2)

- **Backend reachability decision** (expose local dev over Tailscale vs deploy to homelab) — explicitly deferred per the user's "decide after SDK install."
- Setting `POWERSYNC_URL` to a Tailscale-reachable host; binding the dev compose to the tailnet.
- Tailscale on the Pixel; in-app server URL configuration; **actual login + sync round-trip on device.**
- Release signing / local keystore (Phase 1 is debug-signed).
- Custom launcher icon, splash, Play Store packaging.
- iOS (no Mac; out of scope entirely).

## Risks

- **JDK 26 vs AGP** — most likely friction point; mitigated by pinning a JDK 17/21 for Gradle.
- **NDK + native assets** — PowerSync's sqlite-core must compile for Android ABIs via Flutter build hooks; if the NDK version mismatches, `build-apk` fails. This is exactly what step 3's verification catches.
- **SDK install is the long pole** — large downloads; not a code risk but a time one.
