# Productionize Android (Reps) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (INLINE recommended) — this involves generating a keystore + an on-device install + a real git tag that triggers a GitHub release, plus GitHub secrets only the user can add. Steps use checkbox (`- [ ]`).

**Goal:** Rename the app to **Reps** (`io.github.psychonaut0.reps`), add a real release keystore + signing config (no more debug banner), and a `v*`-tag CI workflow that publishes a signed APK to GitHub Releases.

**Architecture:** Android-identity rename (namespace/applicationId/label + MainActivity package). `build.gradle.kts` loads `key.properties` and signs `release` with it (debug fallback if absent). New `android-release.yml` workflow (Flutter 3.44.0 + JDK 21) decodes the keystore from a GitHub secret and `softprops/action-gh-release` publishes the signed APK on `v*` tags — mirroring the homelab's infra `release.yml` convention.

**Tech Stack:** Flutter 3.44 (fvm locally / subosito flutter-action in CI), Android Gradle (Kotlin DSL), `keytool`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-06-01-android-release-reps-design.md`.

**Branch:** `android-release` (off `main`).

**Grounding facts (verified):**
- `app/android/app/build.gradle.kts`: `namespace`/`applicationId` = `dev.psy.workout_tracker`; `buildTypes.release.signingConfig = signingConfigs.getByName("debug")` (current debug-signed default).
- MainActivity: `app/android/app/src/main/kotlin/dev/psy/workout_tracker/MainActivity.kt`, `package dev.psy.workout_tracker`. `AndroidManifest.xml` uses `android:name=".MainActivity"` (resolves against namespace).
- `app/.gitignore` already ignores `key.properties`, `**/*.keystore`, `**/*.jks` — no change needed.
- `keytool` is at `/usr/bin/keytool`. Local JDK 21 at `/usr/lib/jvm/java-21-openjdk`.
- `make -C app build-apk` = `flutter build apk --debug`.

---

## Task 1: Rename to Reps (`io.github.psychonaut0.reps`)

**Files:**
- Modify: `app/android/app/build.gradle.kts` (namespace + applicationId)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (label)
- Move: `MainActivity.kt` → new package dir

- [ ] **Step 1: applicationId + namespace**

In `app/android/app/build.gradle.kts`, change both occurrences:
```kotlin
    namespace = "io.github.psychonaut0.reps"
```
```kotlin
        applicationId = "io.github.psychonaut0.reps"
```

- [ ] **Step 2: Display label**

In `app/android/app/src/main/AndroidManifest.xml`, set:
```xml
        android:label="Reps"
```

- [ ] **Step 3: Move + repackage MainActivity**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker/app/android/app/src/main/kotlin
mkdir -p io/github/psychonaut0/reps
git mv dev/psy/workout_tracker/MainActivity.kt io/github/psychonaut0/reps/MainActivity.kt
rmdir -p dev/psy/workout_tracker 2>/dev/null || true
```
Then edit the moved file's first line:
```kotlin
package io.github.psychonaut0.reps
```
(The rest of `MainActivity.kt` — `class MainActivity : FlutterActivity()` — is unchanged.)

- [ ] **Step 4: Verify analyze + a debug build still links (rename didn't break anything)**
```bash
make -C app analyze 2>&1 | grep -iE 'no issues|error'   # "No issues found!"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk; export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
make -C app build-apk 2>&1 | tail -3   # expect: ✓ Built ...app-debug.apk  (applicationId is now io.github.psychonaut0.reps)
```
Expected: analyze clean; debug APK builds. (Optional sanity: `unzip -p app/build/app/outputs/flutter-apk/app-debug.apk AndroidManifest.xml | strings | grep -i reps` shows the new id.)

- [ ] **Step 5: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker && git checkout -b android-release
git add app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/kotlin
git commit -m "feat(app): rename Android app to Reps (io.github.psychonaut0.reps)"
```

---

## Task 2: Release signing config + local keystore

**Files:**
- Modify: `app/android/app/build.gradle.kts` (load key.properties; release signingConfig)
- Create (local, gitignored): `app/android/key.properties`, the keystore
- Modify: `app/Makefile` (add `build-apk-release`)

- [ ] **Step 1: Add key.properties loading + release signingConfig**

In `app/android/app/build.gradle.kts`, add imports at the very top (above `plugins {`):
```kotlin
import java.util.Properties
import java.io.FileInputStream
```
After the imports / before `android {`, load the properties:
```kotlin
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```
Inside `android { }`, add a `signingConfigs` block (before `buildTypes`):
```kotlin
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
```
And change the `release` buildType to use it (with debug fallback if no key.properties):
```kotlin
    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
```
(`rootProject.file("key.properties")` = `app/android/key.properties`. `file(storeFile)` resolves relative to the app module dir `app/android/app/`, or accepts an absolute path.)

- [ ] **Step 2: Add the `build-apk-release` Make target**

In `app/Makefile`, after `build-apk`, add:
```makefile
build-apk-release:
	$(FLUTTER) build apk --release
```
Add a help line matching the format: `@echo "  build-apk-release  Build a signed release APK (needs android/key.properties)"`.

- [ ] **Step 3: Generate the release keystore (local, kept OUT of the repo)**
```bash
mkdir -p ~/.android-keystores
/usr/lib/jvm/java-21-openjdk/bin/keytool -genkeypair \
  -keystore ~/.android-keystores/reps-release.jks \
  -alias reps -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype JKS \
  -dname "CN=Reps, OU=psychonaut0, O=psychonaut0, C=IT" \
  -storepass "$REPS_KS_PASS" -keypass "$REPS_KS_PASS"
```
Use a strong password (e.g. generate one: `REPS_KS_PASS=$(openssl rand -base64 24)` and SAVE it in your password manager — losing it = can't update-in-place ever). Confirm: `keytool -list -keystore ~/.android-keystores/reps-release.jks -storepass "$REPS_KS_PASS"` shows alias `reps`.

- [ ] **Step 4: Write local `app/android/key.properties` (gitignored)**
```bash
cat > /home/psy/Documents/personal/projects/workout-tracker/app/android/key.properties <<EOF
storeFile=$HOME/.android-keystores/reps-release.jks
storePassword=$REPS_KS_PASS
keyAlias=reps
keyPassword=$REPS_KS_PASS
EOF
chmod 600 /home/psy/Documents/personal/projects/workout-tracker/app/android/key.properties
```
Confirm git ignores it: `git -C /home/psy/Documents/personal/projects/workout-tracker check-ignore app/android/key.properties` → prints the path (ignored).

- [ ] **Step 5: Build a signed release APK — verify it's signed + release-mode**
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk; export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
make -C app build-apk-release 2>&1 | tail -4
ls -lh app/build/app/outputs/flutter-apk/app-release.apk
# verify it's signed by OUR key (not the debug key):
"$ANDROID_HOME"/build-tools/35.0.0/apksigner verify --print-certs app/build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | grep -i 'Signer #1 certificate DN' || keytool -printcert -jarfile app/build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | grep -i 'Owner'
```
Expected: `app-release.apk` built; the signer DN shows `CN=Reps` (our key), not "Android Debug". (apksigner path may be `build-tools/<ver>/apksigner` — adjust to the installed build-tools version.)

- [ ] **Step 6: Commit (gradle + Makefile only — NOT key.properties/keystore)**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git status --porcelain | grep -iE 'key.properties|\.jks' && echo "!!! SECRET WOULD BE COMMITTED — STOP" || echo "no secrets staged"
git add app/android/app/build.gradle.kts app/Makefile
git commit -m "feat(app): release signing config (key.properties) + build-apk-release target"
```

---

## Task 3: Signed-release CI workflow

**Files:**
- Create: `.github/workflows/android-release.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/android-release.yml`:
```yaml
name: android-release

on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          channel: stable

      - name: Decode keystore + write key.properties
        working-directory: app/android
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 -d > app/reps-release.jks
          cat > key.properties <<EOF
          storeFile=reps-release.jks
          storePassword=$KEYSTORE_PASSWORD
          keyAlias=$KEY_ALIAS
          keyPassword=$KEY_PASSWORD
          EOF

      - name: Build signed release APK
        working-directory: app
        run: |
          flutter pub get
          TAG="${GITHUB_REF_NAME}"
          flutter build apk --release \
            --build-name="${TAG#v}" \
            --build-number="${{ github.run_number }}"

      - name: Stage the artifact
        run: cp app/build/app/outputs/flutter-apk/app-release.apk "reps-${GITHUB_REF_NAME}.apk"

      - name: Publish to GitHub Releases
        uses: softprops/action-gh-release@v2
        with:
          files: reps-${{ github.ref_name }}.apk
          fail_on_unmatched_files: true
```
Notes baked in: `storeFile=reps-release.jks` resolves to `app/android/app/reps-release.jks` (where the decode writes it, since the app module dir is `app/android/app`); the key.properties lives at `app/android/key.properties` (rootProject), matching Task 2's gradle loader.

- [ ] **Step 2: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add .github/workflows/android-release.yml
git commit -m "ci(app): signed Android release APK to GitHub Releases on v* tags"
```

---

## Task 4: RELEASE.md (manual one-time steps)

**Files:**
- Create: `app/android/RELEASE.md`

- [ ] **Step 1: Document the keystore + secrets + release flow**

Create `app/android/RELEASE.md` with: the keytool command (Task 2 Step 3), the local `key.properties` shape, the **four GitHub Actions secrets** to add (`KEYSTORE_BASE64` = `base64 -w0 ~/.android-keystores/reps-release.jks`, `KEYSTORE_PASSWORD`, `KEY_ALIAS=reps`, `KEY_PASSWORD`), the release procedure (`git tag vX.Y.Z && git push --tags` → CI publishes `reps-vX.Y.Z.apk` to GitHub Releases), and a **BACKUP THE KEYSTORE** warning (losing it = no in-place updates ever). Include the `gh secret set` shortcut:
```bash
gh secret set KEYSTORE_BASE64 < <(base64 -w0 ~/.android-keystores/reps-release.jks)
gh secret set KEYSTORE_PASSWORD --body "$REPS_KS_PASS"
gh secret set KEY_ALIAS --body "reps"
gh secret set KEY_PASSWORD --body "$REPS_KS_PASS"
```

- [ ] **Step 2: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/android/RELEASE.md
git commit -m "docs(app): Android release runbook (keystore, secrets, tagging)"
```

---

## Task 5: Verify on-device + cut the first release (INLINE, some user steps)

- [ ] **Step 1: Install the locally-built signed release APK + confirm NO debug banner**
With the phone on USB:
```bash
export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/platform-tools:$PATH"
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
adb shell monkey -p io.github.psychonaut0.reps -c android.intent.category.LAUNCHER 1
```
User confirms on-device: launcher icon labelled **"Reps"**, **no red DEBUG ribbon**, app runs (release-mode = AOT, snappier). Then in-app set server URL `http://workout.lan` + sign in (`homeserver.config@pm.me`) → data syncs from the homelab. (This is a new app id, so it installs alongside the old "Workout Tracker"; uninstall that one when satisfied.)

- [ ] **Step 2: Add the GitHub secrets** (user; needs repo admin / `gh` with `admin:repo_hook`/secrets scope)
Run the four `gh secret set` commands from `RELEASE.md` (or add them in the GitHub UI: repo → Settings → Secrets and variables → Actions). Verify: `gh secret list` shows `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

- [ ] **Step 3: Merge the branch, then cut a release tag**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git checkout main && git merge --no-ff android-release && git push origin main
git tag v0.1.0 && git push origin v0.1.0
```

- [ ] **Step 4: Verify the CI release**
```bash
gh run watch "$(gh run list --workflow=android-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh release view v0.1.0 --json assets --jq '.assets[].name'   # expect reps-v0.1.0.apk
```
Download the release APK and confirm it installs + signature matches the local one (same `CN=Reps`).

---

## Verification summary
1. `flutter analyze` clean; debug + signed-release APKs both build; rename → `io.github.psychonaut0.reps`, label "Reps".
2. Local signed release APK: signed by our keystore (not debug), **no DEBUG banner**, installs + syncs from the homelab on-device.
3. `v*` tag → `android-release.yml` publishes a signed `reps-vX.Y.Z.apk` to GitHub Releases.
4. No secrets committed (`key.properties`/`.jks` gitignored).

## Out of scope
LAN mirror of the APK; `.aab`/Play Store; Dart-package rename; the remaining deferred odds-and-ends.
