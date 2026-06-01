# Android On-Device (Phase 1: installable debug APK) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an Android **debug** APK (applicationId `dev.psy.workout_tracker`) that builds from this repo, installs on the Pixel 9, and launches to the login screen — no on-phone backend wiring yet.

**Architecture:** Install the Android SDK/NDK + a Gradle-compatible JDK on the dev machine (`blvcksmall`, CachyOS/Arch); add an additive Android scaffold to the existing Flutter app via `flutter create --platforms=android`; configure applicationId, `minSdk`, INTERNET + a scoped cleartext-HTTP network-security-config (so Phase 2 needn't re-touch the manifest); build the debug APK iteratively (let Flutter name any missing NDK version), then install on-device.

**Tech Stack:** Flutter 3.44.0 via fvm, Gradle (Kotlin DSL scaffold), Android SDK cmdline-tools + NDK, JDK 21 (system JDK 26 is too new for AGP), PowerSync 2.2.0 (Android min `minSdk 24`), `adb`.

**Spec:** `docs/superpowers/specs/2026-06-01-android-on-device-design.md`

**Branch:** `android-on-device` (branch off `main`).

> **Note on task style:** This is environment-setup + scaffold work, not feature code, so tasks are "action → verify with an exact command + expected output" rather than red/green unit tests. The existing Dart test suite is the regression guard (must stay green); the real proof is `build-apk` succeeding and the APK launching.

---

## Pre-flight (read before Task 1)

Current machine state (already confirmed):
- `fvm flutter` = 3.44.0; Flutter feature flag `enable-android` is ON.
- `adb` present (Android platform-tools 1.0.41 already on PATH).
- System JDK = **26** (too new for current Android Gradle Plugin → Task 1 pins JDK 21 for Gradle).
- **No Android SDK** (`flutter doctor`: "Unable to locate Android SDK"), `ANDROID_HOME`/`ANDROID_SDK_ROOT` unset.
- This machine (`blvcksmall`) is online on Tailscale; the Pixel 9 (`google-pixel-9`) is in the tailnet but currently offline. (Tailscale/phone reachability is Phase 2 — not used here. Phase 1 installs over USB.)

---

## Task 1: Install Android SDK + NDK + Gradle JDK (dev machine)

**Files:** none in repo (environment setup). May persist env vars to `~/.zshrc`.

This task has **no git commit** (no repo changes). Its deliverable is `flutter doctor` reporting the Android toolchain ✓.

- [ ] **Step 1: Install a Gradle-compatible JDK (21)**

System JDK is 26; AGP does not support it. Install JDK 21 alongside it (does not change the system default):

Run:
```bash
sudo pacman -S --needed jdk21-openjdk
ls -d /usr/lib/jvm/java-21-openjdk
```
Expected: the directory `/usr/lib/jvm/java-21-openjdk` exists. (If `pacman` reports it already installed, that's fine.)

- [ ] **Step 2: Download Android command-line tools**

Run:
```bash
mkdir -p "$HOME/Android/Sdk/cmdline-tools"
cd /tmp
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-11076708_latest.zip -d "$HOME/Android/Sdk/cmdline-tools"
mv "$HOME/Android/Sdk/cmdline-tools/cmdline-tools" "$HOME/Android/Sdk/cmdline-tools/latest"
ls "$HOME/Android/Sdk/cmdline-tools/latest/bin/sdkmanager"
```
Expected: the `sdkmanager` binary path prints (exists). If the URL 404s, get the current "Command line tools only / Linux" zip link from https://developer.android.com/studio#command-line-tools-only and substitute it.

- [ ] **Step 3: Set SDK env vars (persisted)**

Run:
```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
grep -q 'ANDROID_HOME' ~/.zshrc || cat >> ~/.zshrc <<'EOF'

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
EOF
echo "ANDROID_HOME=$ANDROID_HOME"
```
Expected: prints `ANDROID_HOME=/home/psy/Android/Sdk`. (The `export`s make it live in *this* shell; the `~/.zshrc` append makes it persist. Subsequent steps in the same shell session inherit the exports.)

- [ ] **Step 4: Install SDK packages (platform-tools, platform, build-tools, NDK, cmdline-tools)**

Run (must set `JAVA_HOME` to 21 so `sdkmanager` runs under a supported JDK):
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
yes | sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "platforms;android-35" "build-tools;35.0.0" "cmdline-tools;latest"
sdkmanager --sdk_root="$ANDROID_HOME" --list_installed
```
Expected: `--list_installed` shows `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`. (NDK is intentionally **deferred to Task 4** — Flutter will name the exact NDK version it wants during the first APK build, and we install precisely that, avoiding a version mismatch.)

- [ ] **Step 5: Accept SDK licenses**

Run:
```bash
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
yes | fvm flutter doctor --android-licenses
```
Expected: ends with "All SDK package licenses accepted." (or "All licenses already accepted").

- [ ] **Step 6: Point Flutter at the SDK and the Gradle JDK**

Run:
```bash
fvm flutter config --android-sdk "$ANDROID_HOME"
fvm flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk
```
Expected: each prints a "Setting ... value" confirmation.

- [ ] **Step 7: Verify the Android toolchain**

Run:
```bash
make -C app doctor 2>&1 | sed -n '/Android toolchain/,/^\[/p'
```
Expected: `[✓] Android toolchain - develop for Android devices` with the SDK location and "All Android licenses accepted." (NDK may still show as missing here — that's expected and fixed in Task 4. A ✓ on SDK + licenses is the pass condition for this task.)

---

## Task 2: Scaffold Android + add Makefile targets

**Files:**
- Create: `app/android/` (generated by `flutter create`)
- Modify: `app/Makefile` (add `scaffold-android`, `build-apk`, `run-android`)

- [ ] **Step 1: Add the Makefile targets**

Add these targets to `app/Makefile` (place after the existing `scaffold-linux` and `build` targets; mirror their style — tab-indented recipes):

```makefile
scaffold-android:
	$(FLUTTER) create --platforms=android --org dev.psy --project-name workout_tracker .

build-apk:
	$(FLUTTER) build apk --debug

run-android:
	$(FLUTTER) run -d android
```

Also add their help lines to the `help` target's `@echo` block, matching the existing format, e.g.:
```makefile
	@echo "  scaffold-android  Generate the Android platform folder"
	@echo "  build-apk         Build a debug APK"
	@echo "  run-android       Run on a connected Android device"
```

- [ ] **Step 2: Generate the Android scaffold**

Run:
```bash
make -C app scaffold-android
```
Expected: Flutter reports creating `android/...` files and "All done!". It is additive — it must NOT modify existing `lib/`, `test/`, or `linux/` files.

- [ ] **Step 3: Confirm applicationId and that nothing existing was clobbered**

Run:
```bash
grep -rn 'dev.psy.workout_tracker' app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml 2>/dev/null
git -C /home/psy/Documents/personal/projects/workout-tracker status --porcelain | grep -vE '^\?\? app/android/|^ M app/Makefile' || echo "NO_UNEXPECTED_CHANGES"
```
Expected: the `grep` shows `applicationId = "dev.psy.workout_tracker"` (and/or `namespace`); the status check prints `NO_UNEXPECTED_CHANGES` (only new `app/android/` files + the `Makefile` edit are present — no modifications to existing Dart/Linux files).

- [ ] **Step 4: Confirm the scaffold's .gitignore covers Android local/build artifacts**

Run:
```bash
cat app/android/.gitignore
git -C /home/psy/Documents/personal/projects/workout-tracker status --porcelain app/android | grep -iE 'local.properties|\.gradle|key.properties|\.jks|/build/' || echo "NO_LOCAL_ARTIFACTS_STAGED"
```
Expected: `app/android/.gitignore` lists at least `local.properties`, `.gradle`, `/build/`; the second command prints `NO_LOCAL_ARTIFACTS_STAGED` (no machine-local or secret files would be committed).

- [ ] **Step 5: Verify the existing build is still healthy**

Run:
```bash
make -C app analyze 2>&1 | grep -iE 'no issues|error'
make -C app test 2>&1 | grep -E '\+[0-9]+: All tests passed|failed'
```
Expected: "No issues found!" and "All tests passed!" (97 tests). The scaffold must not regress analyze or tests.

- [ ] **Step 6: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/Makefile app/android
git commit -m "feat(app): scaffold android platform (dev.psy.workout_tracker)"
```

---

## Task 3: Android config — minSdk, INTERNET, scoped cleartext

**Files:**
- Modify: `app/android/app/build.gradle.kts` (minSdk, app label is in manifest)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (label, INTERNET, networkSecurityConfig ref)
- Create: `app/android/app/src/main/res/xml/network_security_config.xml`

- [ ] **Step 1: Ensure `minSdk >= 24` (PowerSync's Android floor)**

Inspect the generated value:
```bash
grep -nE 'minSdk' app/android/app/build.gradle.kts
```
If it reads `minSdk = flutter.minSdkVersion` or any value `< 24`, replace that line with:
```kotlin
        minSdk = 24
```
(Leave `compileSdk`/`targetSdk` at the Flutter defaults.) If it is already `>= 24`, leave it and note so in the step.

- [ ] **Step 2: Set the app label**

In `app/android/app/src/main/AndroidManifest.xml`, set the `<application>` `android:label` to:
```xml
        android:label="Workout Tracker"
```
(Flutter generates `android:label="workout_tracker"` by default — change it to the human-readable form.)

- [ ] **Step 3: Confirm INTERNET permission, add it if absent**

Run:
```bash
grep -n 'android.permission.INTERNET' app/android/app/src/main/AndroidManifest.xml || echo "MISSING"
```
If it prints `MISSING`, add this line as a direct child of `<manifest>` (above `<application>`):
```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```
Expected after the fix: the permission line is present. (Flutter's default debug manifest usually includes it; this step guarantees it for the release manifest path too.)

- [ ] **Step 4: Create the scoped cleartext network-security-config**

The Phase-2 backend is `http://…` over Tailscale (no TLS); Android blocks cleartext by default. Permit it ONLY for the tailnet + localhost (not a blanket allow).

Create `app/android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Default: keep cleartext blocked everywhere else. -->
    <base-config cleartextTrafficPermitted="false"/>
    <!-- Allow plain HTTP only to the homelab over Tailscale and to localhost,
         since the self-hosted backend is served over http:// without TLS. -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">tail1552c5.ts.net</domain>
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```
(`10.0.2.2` is the Android emulator's alias for the host loopback — harmless to include and useful if an emulator is ever used.)

- [ ] **Step 5: Reference the config from the manifest**

In `app/android/app/src/main/AndroidManifest.xml`, add to the `<application>` tag:
```xml
        android:networkSecurityConfig="@xml/network_security_config"
```

- [ ] **Step 6: Verify analyze is still clean (config-only change)**

Run:
```bash
make -C app analyze 2>&1 | grep -iE 'no issues|error'
```
Expected: "No issues found!" (Dart analysis is unaffected by Android XML/Gradle; this just confirms nothing else broke.)

- [ ] **Step 7: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/res/xml/network_security_config.xml
git commit -m "feat(app): android minSdk 24, label, INTERNET, scoped cleartext for tailnet"
```

---

## Task 4: Build the debug APK (iterative NDK resolution)

**Files:** none committed unless an NDK pin is added to `app/android/app/build.gradle.kts`.

- [ ] **Step 1: First build attempt**

Run (JDK 21 for Gradle):
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
make -C app build-apk 2>&1 | tail -40
```
Two possible outcomes:
- **Success:** ends with `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. Skip to Step 3.
- **NDK error:** Gradle/Flutter fails naming a required NDK version, e.g. `No version of NDK matched the requested version <X.Y.Z…>` or `NDK not configured`. Proceed to Step 2.

- [ ] **Step 2: Install the exact NDK version Flutter named, then rebuild**

Read the version string from the Step-1 error (call it `<NDK_VERSION>`, e.g. `27.0.12077973`). Install it and pin it:
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
yes | sdkmanager --sdk_root="$ANDROID_HOME" "ndk;<NDK_VERSION>"
```
Then, in `app/android/app/build.gradle.kts`, inside the `android { }` block, set:
```kotlin
    ndkVersion = "<NDK_VERSION>"
```
Rebuild:
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
make -C app build-apk 2>&1 | tail -40
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. If a different SDK component is named missing instead (e.g. a `build-tools` or `platform` version), install that exact component the same way and rebuild. Repeat until the build succeeds.

- [ ] **Step 3: Confirm the APK artifact exists**

Run:
```bash
ls -lh app/build/app/outputs/flutter-apk/app-debug.apk
```
Expected: the file exists (tens of MB). This is the real proof the native (PowerSync) build wired correctly for Android.

- [ ] **Step 4: Commit (only if Task changed gradle)**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/android/app/build.gradle.kts
git commit -m "build(app): pin android ndkVersion for apk build" || echo "nothing to commit"
```
(If the build succeeded at Step 1 with no gradle edit, there is nothing to commit — skip.)

---

## Task 5: Install on the Pixel 9 and verify launch (on-device, user-assisted)

**Files:** none. This step needs the **physical Pixel 9 connected by USB** with USB debugging enabled — the user performs the physical/consent parts.

- [ ] **Step 1: Connect the device and authorize**

User action: plug the Pixel 9 in via USB, and on the phone enable Developer Options → USB debugging, then accept the "Allow USB debugging?" prompt.

Run:
```bash
adb devices
```
Expected: the Pixel appears as `<serial>	device` (not `unauthorized`). If `unauthorized`, re-accept the on-phone prompt.

- [ ] **Step 2: Install the APK**

Run:
```bash
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
```
Expected: `Success`.

- [ ] **Step 3: Launch and confirm**

User action: open "Workout Tracker" from the app drawer (or `adb shell monkey -p dev.psy.workout_tracker -c android.intent.category.LAUNCHER 1`).

Expected on-device: the app launches and renders the **login screen** without crashing. A login *attempt* failing (no reachable backend yet) is expected and acceptable — Phase 1 only proves the app boots and renders on real hardware.

- [ ] **Step 4: Capture any on-device issues**

Note (do not fix in this plan) any rendering/layout/jank problems observed on the real device — these feed the Phase-2/polish backlog (e.g. the still-unconfirmed set-row overflow + FAB straddle, now verifiable on hardware).

---

## Done / Hand-off to Phase 2

When Task 5 passes, Phase 1 is complete: the app builds and runs on the Pixel. **Phase 2** (separate spec/plan) decides backend reachability (expose local dev over Tailscale vs homelab deploy), sets a Tailscale-reachable `POWERSYNC_URL`, gets Tailscale onto the Pixel, sets the in-app server URL, and verifies a real login + sync round-trip on-device.

## Verification summary (Phase 1 "done")

1. `make -C app doctor` → Android toolchain ✓ (SDK + licenses).
2. `make -C app analyze` → 0 issues; `make -C app test` → 97 passing (scaffold didn't regress).
3. `make -C app build-apk` → `app-debug.apk` produced (NDK/native build wired).
4. `adb install` → Success; app launches to login screen on the Pixel; no crash.
