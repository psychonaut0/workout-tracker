# Reps — Android release runbook

The app id is `io.github.psychonaut0.reps`. Release APKs are **signed** and published
to **GitHub Releases** by `.github/workflows/android-release.yml` on every `v*` tag.
`make -C app build-apk` stays a *debug* build for local iteration; signed builds use
`key.properties` (below).

## One-time setup

### 1. Generate the release keystore (keep it OUT of git, BACK IT UP)
```bash
mkdir -p ~/.android-keystores
keytool -genkeypair \
  -keystore ~/.android-keystores/reps-release.jks \
  -alias reps -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS \
  -dname "CN=Reps, OU=psychonaut0, O=psychonaut0, C=IT" \
  -storepass "<PASSWORD>" -keypass "<PASSWORD>"
```
> ⚠️ **Back up the keystore + password** (password manager + offline copy). If you lose
> them you can never ship an in-place update again — only a fresh-id reinstall.

### 2. Local signing (`app/android/key.properties`, gitignored)
```properties
storeFile=/home/<you>/.android-keystores/reps-release.jks
storePassword=<PASSWORD>
keyAlias=reps
keyPassword=<PASSWORD>
```
Then `make -C app build-apk-release` builds a locally-signed release APK
(`app/build/app/outputs/flutter-apk/app-release.apk`). Verify the signer:
```bash
$ANDROID_HOME/build-tools/35.0.0/apksigner verify --print-certs \
  app/build/app/outputs/flutter-apk/app-release.apk | grep 'certificate DN'
# -> Signer #1 certificate DN: CN=Reps, OU=psychonaut0, ...
```

### 3. CI signing — GitHub Actions secrets (repo → Settings → Secrets → Actions)
The workflow decodes the keystore from `KEYSTORE_BASE64` and signs with it. Set the four
secrets once (via `gh`, needs a token with repo-secrets scope):
```bash
gh secret set KEYSTORE_BASE64 < <(base64 -w0 ~/.android-keystores/reps-release.jks)
gh secret set KEYSTORE_PASSWORD --body "<PASSWORD>"
gh secret set KEY_ALIAS        --body "reps"
gh secret set KEY_PASSWORD     --body "<PASSWORD>"
gh secret list   # confirm all four
```

## Cutting a release
```bash
git tag v1.2.3        # versionName = 1.2.3 (build number = the CI run number)
git push origin v1.2.3
```
CI builds + signs + publishes `reps-v1.2.3.apk` to the GitHub Release for that tag.
Download it to the phone and install (it's a new app id vs the old "Workout Tracker",
so it installs alongside until you uninstall the old one). On first run, set the server
URL to `http://workout.lan` (Tailscale must be on) and sign in — data syncs from the homelab.

## Notes
- `key.properties`, `*.jks`, `*.keystore` are gitignored — never commit them.
- Without `key.properties` (e.g. a contributor / PR CI), `flutter build apk --release`
  falls back to debug signing so it still builds; only the `v*`-tag release path on the
  main repo signs with the real key (it has the secrets).
- Distribution is GitHub Releases only; a LAN mirror (ct-mgmt) is deferred.
