# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Flutter client for Reps. Android is the product target; Linux desktop is the dev loop.

## Commands

Flutter is pinned via **fvm** (`.fvmrc`) — NEVER run `flutter` directly; every target goes through the Makefile from the repo root (`make -C app <target>`, which sets cwd so fvm resolves the pin):

- `make -C app analyze` — must stay at "No issues found" (deprecation warnings count as failures)
- `make -C app test` — full suite (~25s); single file: `make -C app test TEST=test/session/set_row_overflow_test.dart`
- `make -C app build` — Linux desktop bundle (compiles PowerSync native libs; good smoke test)
- `make -C app build-apk` / `build-apk-release` — debug / signed release APK (release needs gitignored `android/key.properties`; falls back to debug signing without it)
- `make -C app run` / `run-android`, `fmt`, `get`, `doctor`

Toolchain gotchas: Android needs JDK 21 (`flutter config --jdk-dir` already set — system JDK is too new for AGP) and `ANDROID_HOME=$HOME/Android/Sdk`. This host's Clang 22 breaks `flutter_secure_storage_linux` under `-Werror`; the fix lives in `linux/CMakeLists.txt` (`-Wno-error=deprecated-literal-operator`) — expect the same remedy for future vendored-header errors. `flutter_local_notifications` requires core-library desugaring (already configured in `android/app/build.gradle.kts`).

## Architecture

State management is `provider`; app-wide ChangeNotifiers are created in `main.dart` and provided ABOVE MaterialApp (so any route context can read them): `SettingsService`, `UnitService`, `IdentityService`, `SessionManager`, `AmbientController`.

- `lib/sync/` — PowerSync: `db.dart` exposes the single global `db` (`PowerSyncDatabase`); `schema.dart` mirrors the server tables; `connector.dart` builds `/sync/upload` batches. Boot order in `main()` matters: settings → openDatabase → identity → `backfillTopSets` → `absorbTemplates` → SessionManager/notification → resume draft → optional connectSync.
- `lib/data/` — repositories (plain classes over `db`) + pure op-builders (`(sql, args)` records) that the repos execute in `db.writeTransaction`. Boot migrations: `top_set_backfill.dart`, `template_absorb.dart`.
- `lib/session/` — active workout: `ActiveSessionController` (draft + rest timer + debounced autosave to `DraftStore`), owned app-wide by `SessionManager` (minimize/resume, drives the ongoing notification via `workout_notification.dart`). The session screen is a pushed route that renders `manager.active`; popping it = minimize, not discard.
- `lib/shell/` — `AppShell` (IndexedStack tabs + WTabBar + FAB + mini-bar), back-nav (`back_dispatch.dart`), `session_launcher.dart` (`startSession`/`openActiveSession`).
- `lib/ui/` — screens; `lib/widgets/` — design-system widgets; `lib/theme/` — tokens (`context.tokens`), typography (`WorkoutType`), icons (`WIcons`), motion.
- `lib/export/` — JSON export (pure builders + IO service). `lib/identity/`, `lib/settings/`, `lib/units/` — small services.

Visual source of truth: `../docs/design_handoff_workout_tracker/` (README + `.jsx` prototypes). Match its exact control sizes; make rows flex for narrow phones.

## Hard-won rules (violating these reintroduces shipped bugs)

**Data:**
- `weight_kg` columns are TEXT (NUMERIC arrives as string — parse at the edges); booleans are INTEGER 0/1; `sessions.date`/`bodyweight_logs.date` are date-only `YYYY-MM-DD` (`isoDate()` in `util/dates.dart` — inclusive string-compare ranges are exact); `created_at` is full ISO.
- The client NEVER writes `user_id`/`created_by`/`is_top_set`/`is_pr` upstream — server stamps/computes. Locally, `is_top_set` is ALSO computed client-side (`session_writer.topSetIndex`, `_recomputeTopSet` after History edits) because offline users have no server recompute.
- Server PATCH handlers apply explicit column allowlists; a local `UPDATE` on a column outside that list silently diverges (e.g. `sets.exercise_id`). Re-point such columns via DELETE+INSERT with the same id (PowerSync emits DELETE+PUT, no coalescing; PUT recomputes server flags).
- `is_template=1` rows are filtered out of every list query (`watchDays`, `watchCatalog`, `all()`); `byId` stays unfiltered for stray references. Don't reintroduce clone-on-edit.
- `uuid` singleton comes from `package:powersync/powersync.dart`; deterministic ids use `package:uuid` v5 (see `template_absorb.dart`). Importing `package:powersync/powersync.dart` into widget files needs `show` (it re-exports `Column`).
- Custom-exercise slugs: `uniqueSlug(name, id)` = slugify + `-id8` suffix (local dedup can't see other users' slugs).

**UI/motion:**
- Confirm dialogs: ALWAYS `showWConfirm`/`showWDialog` (`widgets/w_dialog.dart`) — never `AlertDialog`.
- Motion: `theme/motion.dart` is the single source (fast/base/slow, easeOutCubic, zero bounce); every duration goes through `Motion.of(context, d)` (reduced-motion → zero); repeating controllers are skipped entirely under reduced motion. One-shot entrance widgets (`Reveal`, `StaggeredEntrance`, `MountProgress`) must keep stable keys so stream rebuilds don't replay them.
- `late final AnimationController` fields must be constructed/started in `initState`, NOT via `..forward()` in the initializer — a reduced-motion build path that never touches the field makes `dispose()` lazily create a ticker on a deactivated element and crash. This bug shipped three times.
- Flex widgets (`Expanded`) must be DIRECT children of their Row/Column — wrappers like `UnitSwap`/`AnimatedSwitcher` go inside the `Expanded`, never around it (ParentDataWidget crash that passes CI because no test renders the row).
- Raw image pixels for `ui.ImageDescriptor.raw`/`decodeImageFromPixels` are PREMULTIPLIED alpha — color channels must be ≤ alpha (see `grainPixels`).
- Scaffolds are transparent by theme; `AmbientLayer` (wrapped via `MaterialApp.builder`) paints the background. Don't give screens opaque `backgroundColor`.
- Steppers (`WStepper`) hold values in the CALLER's space (kg); `format` converts to display units; typed input converts back via `parseDisplay`.

**Tests:**
- Widget-test theme harness: `MaterialApp(theme: buildTheme(Brightness.dark, accents[0]))`; `context.tokens` has a theme-less fallback.
- Perpetual-ticker widgets (ambient, mini-bar): use `pump(duration)` not `pumpAndSettle`, and end the test by pumping a replacement widget so tickers dispose. Reduced motion in tests: `tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures.allOn`.
- CI runs analyze + tests but renders no pixels — visual output (painters, layouts no test pumps) is only verified on-device.
