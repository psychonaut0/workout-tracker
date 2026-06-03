# Reps — Flutter App Icon

The **Plate** mark (lime weight-plate ring + ascending top-set line) on a near-black tile. Two ways to use this — pick one.

---

## Option A — `flutter_launcher_icons` (recommended)
Lets the package generate/refresh every native size from one source.

1. Add the dev dependency:
   ```yaml
   dev_dependencies:
     flutter_launcher_icons: ^0.14.1
   ```
2. Copy the source images into your app:
   ```
   source/reps-icon-1024.png       ->  assets/icon/reps-icon-1024.png
   source/reps-foreground-1024.png ->  assets/icon/reps-foreground-1024.png
   ```
3. Paste the `flutter_launcher_icons:` block from `flutter_launcher_icons.yaml` into your `pubspec.yaml`.
4. Generate:
   ```bash
   dart run flutter_launcher_icons
   ```

`reps-icon-1024.png` is full-bleed (no rounded corners — the OS masks it). `reps-foreground-1024.png` is the transparent adaptive foreground (mark inside the Android safe zone); the background is the solid `#0B0B0C` set in the config.

---

## Option B — drop in the pre-generated native files
Already rendered at every required size. Merge these into your Flutter project, replacing the defaults:

**iOS** → copy over `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
(15 PNGs + `Contents.json`, covers iPhone/iPad/marketing).

**Android** → merge into `android/app/src/main/res/`
- `mipmap-<dpi>/ic_launcher.png` — legacy launcher icons (mdpi→xxxhdpi)
- `mipmap-<dpi>/ic_launcher_foreground.png` — adaptive foreground layer
- `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon (foreground + background)
- `values/ic_launcher_background.xml` — defines `ic_launcher_background` = `#0B0B0C`

  Ensure `android/app/src/main/AndroidManifest.xml` has `android:icon="@mipmap/ic_launcher"` on `<application>` (default).

**Web** → copy `web/favicon.png` and `web/icons/` (Icon-192/512 + maskable) into your app's `web/`, and confirm `web/manifest.json` references them.

---

## Brand reference
- Accent (lime): `#C2F53A`  ·  Tile / ink: `#0B0B0C`
- Wordmark: Space Grotesk Bold — “Reps.” (lime accent period)
- Mark is fully regenerable from `logos.jsx` (`MarkPlate`) at any size.
