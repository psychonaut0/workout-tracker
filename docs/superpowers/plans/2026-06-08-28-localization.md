# Localization (en/it/de/es) + Profile Overscroll Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the whole UI into English/Italian/German/Spanish via Flutter's official ARB + gen_l10n, with device-locale + manual override, and fix the Profile overscroll gray-box artifact. Per `docs/superpowers/specs/2026-06-08-localization-design.md`. Ships as v0.11.0.

**Architecture:** ARB files under `app/lib/l10n/` (`app_en.arb` template + it/de/es), generated `AppLocalizations` (synthetic-package off → a real file in `lib/l10n/`). Strings are extracted to ARB cluster-by-cluster; the app stays green throughout because EN is always complete and missing keys in other locales fall back to EN at runtime. A shared `wrapL10n` test harness registers the delegates. Translations for it/de/es are authored in one pass after EN is finalized. The notification layer (no BuildContext / background isolate) localizes its ~3 strings via a small locale-keyed map.

**Tech Stack:** Flutter 3.44 (fvm), `flutter_localizations` (SDK) + `intl`, gen_l10n.

**Conventions:**
- Branch: `git checkout -b localization` off `main` first.
- Makefile only: `make -C app analyze`, `make -C app test`, `make -C app get` (regenerates AppLocalizations), `make -C app build`, `make -C app test TEST=...`. NEVER run flutter directly.
- Baseline: 220 tests green, analyze clean.
- Commit style: Conventional Commits, subject only.
- **ARB key naming:** camelCase, grouped by feature prefix (e.g. `todayGreeting`, `planAddExercise`, `sessionFinish`, `commonCancel`, `commonDelete`). Reuse `common*` keys for repeated words (Cancel/Delete/Save/Done/OK). Every key gets an `@key` entry with a `description` (and `placeholders`/plural syntax where needed) in the TEMPLATE (`app_en.arb`) only.
- **Placeholders:** `"sessionSaveFailed": "Failed to save session: {error}"` with `"@sessionSaveFailed": {"placeholders": {"error": {"type": "String"}}}`.
- **Plurals (ICU):** `"todayExerciseCount": "{count, plural, =1{1 exercise} other{{count} exercises}}"` with `"@todayExerciseCount": {"placeholders": {"count": {"type": "int"}}}`. Use this for every count (exercises, sets, PRs, "Xm ago", "X muscles", etc.) — never hand-roll `${n>1?'s':''}`.
- **Call sites:** read `final l = AppLocalizations.of(context);` then `l.someKey` / `l.someKey(count)`. (`nullable-getter: false` → no `!`.)
- **Keep app green after every task:** EN complete at all times; it/de/es authored in Task 9 (gen_l10n falls back to the template for any not-yet-translated key, so intermediate builds work).

---

### Task 1: Profile overscroll fix (independent — ship the bugfix cleanly)

**Files:** Modify `app/lib/ui/profile_screen.dart`.

- [ ] **Step 1:** In `profile_screen.dart` `build()` (~:481), the `Scaffold(body: Column(children: [header, Expanded(ListView...)]))` — wrap the `Column` in a `ColoredBox` so the transparent Scaffold (ambient layer) has a solid backing layer for Android's stretch-overscroll to sample:
```dart
    return Scaffold(
      body: ColoredBox(
        color: tokens.bg,
        child: Column(
          children: [
            // ── Header ──
            ...
          ],
        ),
      ),
    );
```
(Only wrap; do not change the header/ListView. `tokens` is already in scope from `context.tokens`.)

- [ ] **Step 2: Verify** — `make -C app analyze` clean; `make -C app test` green (no test asserts the artifact; this is a render fix the user confirms on-device).

- [ ] **Step 3: Commit**
```bash
git add app/lib/ui/profile_screen.dart
git commit -m "fix(app): opaque Profile body so overscroll stops surfacing a gray box"
```

---

### Task 2: l10n machinery + locale setting + language picker + harness (TDD)

**Files:** Modify `app/pubspec.yaml`, `app/.gitignore`; Create `app/l10n.yaml`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_it.arb`, `app/lib/l10n/app_de.arb`, `app/lib/l10n/app_es.arb`, `app/test/support/l10n_harness.dart`, `app/test/l10n/arb_parity_test.dart`; Modify `app/lib/main.dart`, `app/lib/settings/settings_service.dart`, `app/lib/ui/profile_screen.dart`. Test: `app/test/settings/locale_override_test.dart`.

- [ ] **Step 1: pubspec + l10n.yaml.**
- `app/pubspec.yaml`: under `dependencies`, add:
  ```yaml
    flutter_localizations:
      sdk: flutter
    intl: any
  ```
  (`intl: any` lets Flutter pin the version it requires.) Under the `flutter:` section add `generate: true`.
- Create `app/l10n.yaml`:
  ```yaml
  arb-dir: lib/l10n
  template-arb-file: app_en.arb
  output-localization-file: app_localizations.dart
  output-class: AppLocalizations
  output-dir: lib/l10n
  synthetic-package: false
  nullable-getter: false
  ```
- `app/.gitignore`: add the generated files so they're not committed (regenerated on get/build):
  ```
  /lib/l10n/app_localizations*.dart
  ```

- [ ] **Step 2: Starter ARB files** with the locale-picker + common keys (the migration tasks append the rest). `app/lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "languageEnglish": "English",
  "languageItalian": "Italiano",
  "languageGerman": "Deutsch",
  "languageSpanish": "Español",
  "languageSystem": "System default",
  "settingsLanguage": "Language",
  "commonCancel": "Cancel",
  "commonOk": "OK"
}
```
`app/lib/l10n/app_it.arb` (`"@@locale": "it"`): languageEnglish→"Inglese", languageItalian→"Italiano", languageGerman→"Tedesco", languageSpanish→"Spagnolo", languageSystem→"Predefinita di sistema", settingsLanguage→"Lingua", commonCancel→"Annulla", commonOk→"OK". `app_de.arb` (`de`): "Englisch"/"Italienisch"/"Deutsch"/"Spanisch"/"Systemstandard"/"Sprache"/"Abbrechen"/"OK". `app_es.arb` (`es`): "Inglés"/"Italiano"/"Alemán"/"Español"/"Predeterminado del sistema"/"Idioma"/"Cancelar"/"OK". (NOTE: language NAMES are shown in the CURRENT UI language, so each file translates all four names.)
Run `make -C app get` to generate `lib/l10n/app_localizations.dart` (+ per-locale). Confirm the file appears and `AppLocalizations` is importable as `package:workout_tracker/l10n/app_localizations.dart`.

- [ ] **Step 3: SettingsService locale override (TDD).** Failing test `app/test/settings/locale_override_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('locale override: null=system default, set persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.load();
    expect(s.localeOverride, isNull);
    expect(s.locale, isNull);

    await s.setLocaleOverride('it');
    expect(s.locale, const Locale('it'));
    final s2 = SettingsService();
    await s2.load();
    expect(s2.localeOverride, 'it');
    expect(s2.locale, const Locale('it'));

    await s.setLocaleOverride(null);
    expect(s.locale, isNull);
  });
}
```
Implement in `settings_service.dart` (mirror the existing field/getter/setter/load pattern; import `package:flutter/widgets.dart` for `Locale` — it likely already imports material):
```dart
  String? _localeOverride;
  String? get localeOverride => _localeOverride;
  Locale? get locale =>
      _localeOverride == null ? null : Locale(_localeOverride!);

  Future<void> setLocaleOverride(String? code) async {
    _localeOverride = code;
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove('settings.locale');
    } else {
      await prefs.setString('settings.locale', code);
    }
    notifyListeners();
  }
```
In `load()`: `_localeOverride = prefs.getString('settings.locale');`.

- [ ] **Step 4: MaterialApp wiring.** In `main.dart`, the `Builder` that builds `MaterialApp` (watches `SettingsService` as `s`): add imports `package:flutter_localizations/flutter_localizations.dart` and `l10n/app_localizations.dart`. Add to the MaterialApp:
```dart
            locale: s.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
```

- [ ] **Step 5: Language picker in Profile.** In `profile_screen.dart`, add a "Language" `_Row` in the Appearance group (icon e.g. `WIcons.gear` or a globe — use an existing WIcons glyph; `WIcons.user`→no, pick something neutral like `WIcons.gear`). The row's `sub`/right shows the current language; tapping opens a chooser. Implement a `_pickLanguage(BuildContext, SettingsService)` using `showWDialog<String?>` with actions for System/English/Italiano/Deutsch/Español (labels via `l.languageSystem` etc.), each returning the code (`null`/`'en'`/`'it'`/`'de'`/`'es'`), then `settings.setLocaleOverride(code)`. The current label: map `settings.localeOverride` → the matching `l.language*` (null → `l.languageSystem`). `_Row(icon: WIcons.gear, title: l.settingsLanguage, sub: <current language label>, onTap: () => _pickLanguage(context, settings))`. (`showWDialog` actions are `WDialogAction<String?>`; if a 5-action dialog is too tall, a simple `showModalBottomSheet` list is an acceptable alternative — match the app's sheet style.)

- [ ] **Step 6: ARB key-parity test.** `app/test/l10n/arb_parity_test.dart` — guards that every locale has the template's keys:
```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all ARB locales have the same keys as the template', () {
    Set<String> keysOf(String path) {
      final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      // Data keys only: drop @@locale and @-metadata entries.
      return json.keys
          .where((k) => !k.startsWith('@'))
          .toSet();
    }

    const dir = 'lib/l10n';
    final en = keysOf('$dir/app_en.arb');
    for (final loc in ['it', 'de', 'es']) {
      final k = keysOf('$dir/app_$loc.arb');
      expect(k.difference(en), isEmpty, reason: '$loc has extra keys: ${k.difference(en)}');
      expect(en.difference(k), isEmpty, reason: '$loc is missing keys: ${en.difference(k)}');
    }
  });
}
```
(CWD for `make -C app test` is `app/`, so the relative `lib/l10n` path resolves. Verify by running it.)

- [ ] **Step 7: Verify** — `make -C app get` (regenerate), `make -C app analyze` clean, `make -C app test` green (222: +locale, +parity). The picker shows in Profile; switching language rebuilds (the Builder watches settings).

- [ ] **Step 8: Commit**
```bash
git add app/pubspec.yaml app/pubspec.lock app/l10n.yaml app/.gitignore app/lib/l10n/*.arb app/lib/main.dart app/lib/settings/settings_service.dart app/lib/ui/profile_screen.dart app/test/support/l10n_harness.dart app/test/l10n/arb_parity_test.dart app/test/settings/locale_override_test.dart
git commit -m "feat(app): l10n machinery, locale override + language picker"
```

- [ ] **Step 0 (do this within Step 1–7, before migrating any cluster): the shared test harness.** Create `app/test/support/l10n_harness.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

/// Wraps [child] in a MaterialApp with the app theme + localization delegates,
/// for widget tests that render localized widgets.
Widget wrapL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: buildTheme(Brightness.dark, accents[0]),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
```

---

### Tasks 3–7: String migration by cluster

Each cluster task follows the SAME procedure (repeated here, not cross-referenced):
1. **Inventory** every user-facing literal string in the cluster's files (Text/labels/titles/hints/button text/snackbars/dialog titles+messages/empty states/tooltips). Skip: stable enum/DB-key strings, debug `assert` text, and user-data fields.
2. **Add keys** to `app/lib/l10n/app_en.arb` (camelCase, feature-prefixed; `@`-metadata with description; ICU plural for counts; placeholders for interpolations — see Conventions). Reuse existing `common*` keys; add new ones as needed.
3. **Swap call sites** to `AppLocalizations.of(context)` — add `final l = AppLocalizations.of(context);` near the top of the relevant `build`/method and replace literals with `l.key` / `l.key(count, ...)`. Where a string is built outside a widget with context (e.g. a model/util), thread the localized string in from the caller or move the literal into the widget.
4. **Migrate that cluster's tests** to `wrapL10n(...)` (replace bespoke `MaterialApp(theme: buildTheme(...))` wrappers). Tests asserting English literals still pass under the default `Locale('en')`. If a test asserts a string that became a plural/placeholder, assert the resolved English text.
5. Run `make -C app get && make -C app analyze && make -C app test` — green before commit.
6. Commit `feat(app): localize <cluster>`.

Known ICU/placeholder cases to handle as you encounter them (do NOT hand-roll):
- `'$exCount exercises'`, `'$muscles muscles'`, `'$count'` set counts, `' · $prCount PR…'`, `'$doneWork/$totalWork sets'` → ICU plurals.
- `'$work×$repLow–$repHigh · RIR $rirStr$warmSuffix'`, `'$equip · compound'`, `'No exercises match "$query".'`, `'Failed to save session: $error'` → placeholders.
- `'$mm:${ss…}'` clock strings stay as `fmtClock`/number formatting (NOT ARB — pure numeric).
- Relative time "just now / Xm ago / Xh ago" (sync status row) → ICU plural keys.

- [ ] **Task 3 — Home surface.** Files: `app/lib/ui/today_screen.dart` (+ its `_ResumeHero`, greeting, section labels, stat-tile labels, weekly-volume header), `app/lib/shell/session_indicator.dart`, `app/lib/widgets/split_card.dart`, `app/lib/widgets/week_strip.dart`, `app/lib/widgets/stat_tile.dart` (labels passed in). Tests: today widget tests. Commit `feat(app): localize home/today surface`.

- [ ] **Task 4 — Active session.** Files: `app/lib/session/active_session_screen.dart`, `exercise_block.dart`, `set_row.dart`, `rest_timer.dart`, `exercise_picker_sheet.dart`, `session_summary_screen.dart`. Includes the RIR/prescription line placeholders, Discard/Remove/Finish dialog text (reuse `common*`), summary stat labels + PR-count plural. Tests: `set_row_overflow_test`, `session_indicator_test` (if it touches session), summary tests. Commit `feat(app): localize active session + summary`.

- [ ] **Task 5 — Plan editors.** Files: `app/lib/ui/plan_screen.dart`, `split_tab.dart`, `day_editor.dart`, `exercise_editor.dart`, `exercise_library_tab.dart`, `targets_tab.dart`, `exercise_sheet.dart`, `app/lib/widgets/plan_form.dart` (field labels passed in). Includes the delete-day/delete-exercise dialog text, the "Rest"/"Default" stepper labels, weekday names (use `intl` `DateFormat.E`/`EEEE` with locale, NOT hand lists). Tests: plan write/editor tests. Commit `feat(app): localize plan editors`.

- [ ] **Task 6 — History / Progress / Bodyweight / Export.** Files: `app/lib/ui/history_screen.dart`, `progress_screen.dart`, `bodyweight_view.dart`, `add_weight_sheet.dart`, and the export rows in `profile_screen.dart` (Export all / Export history / "No sessions in that range" / "Export failed"). Metric-tab labels, summary stat labels, "Sessions/PRs/Volume" plurals. Tests: history/progress tests. Commit `feat(app): localize history/progress/bodyweight/export`.

- [ ] **Task 7 — Profile / onboarding / login / dialogs / sync status.** Files: `app/lib/ui/profile_screen.dart` (remaining: group labels, units/appearance/sync/account rows, sign-out/switch-server dialogs, reconcile prompt, quick-stat labels), `onboarding_screen.dart`, `login_screen.dart`, `app/lib/sync/sync_status_ui.dart` (syncing/synced/offline/error + relative-time plurals — note this is a pure file: thread the localized strings in from `_SyncStatusRight` in profile, OR have it return enum+data and localize at the widget). Tests: profile/onboarding/login/sync_status tests → migrate to `wrapL10n`; `sync_status_ui_test` asserts the pure mapping (keep it testing the enum/relative-bucket, move the string to the widget). Commit `feat(app): localize profile/onboarding/login/sync status`.

(If a cluster is large, split its commit per-file — but keep each commit green.)

---

### Task 8: Muscle labels + locale-aware dates

**Files:** Modify `app/lib/data/muscles.dart`, `app/lib/util/dates.dart`, and their call sites; ARB keys.

- [ ] **Step 1: Muscle labels.** Add 8 ARB keys `muscleChest`…`muscleTriceps` (en + it/de/es in Task 9). Add to `muscles.dart` a context-aware display function:
```dart
String localizedMuscle(AppLocalizations l, String key) {
  switch (key) {
    case 'chest': return l.muscleChest;
    case 'back': return l.muscleBack;
    case 'shoulders': return l.muscleShoulders;
    case 'quads': return l.muscleQuads;
    case 'hamstrings': return l.muscleHamstrings;
    case 'calves': return l.muscleCalves;
    case 'biceps': return l.muscleBiceps;
    case 'triceps': return l.muscleTriceps;
    default: return muscleLabel(key); // unknown custom key → title-cased fallback
  }
}
```
(Import `AppLocalizations`. Keep `muscleLabel`/`orderedMuscles`/`kMuscleLabels` for ordering + storage + fallback.) Replace DISPLAY call sites (targets tab, exercise library grouping headers, volume bars labels, anywhere `muscleLabel(...)` feeds a `Text`) with `localizedMuscle(AppLocalizations.of(context), key)`. Leave ordering/data uses of `muscleLabel`/keys alone.

- [ ] **Step 2: Locale-aware dates.** In `util/dates.dart`, the human-facing formatters (`fmtDate`, weekday-short) take a `Locale` (or `BuildContext`) and use `intl` `DateFormat(..., localeName)`: e.g. weekday short = `DateFormat.E(localeName).format(date)`, date label = an appropriate `DateFormat`. Keep `isoDate` (machine format `YYYY-MM-DD`) UNCHANGED — it's storage, not display. Update call sites to pass `Localizations.localeOf(context).toLanguageTag()`. Relative-time ("Xm ago") moves to ARB plurals (handled in the sync-status cluster). `intl` `DateFormat` needs `initializeDateFormatting` only for non-default locales — call `await initializeDateFormatting()` once in `main()` before runApp (import `package:intl/date_symbol_data_local.dart`).

- [ ] **Step 3: Verify + commit** — `make -C app analyze && make -C app test` green. `git commit -m "feat(app): localize muscle labels and dates"`.

---

### Task 9: Author it/de/es translations + notification locale strings

**Files:** Modify `app/lib/l10n/app_it.arb`, `app_de.arb`, `app_es.arb` (translate ALL keys now present in `app_en.arb`); Modify `app/lib/session/workout_notification.dart`.

- [ ] **Step 1: Translate the full key set.** For every key in the finalized `app_en.arb`, add the it/de/es translation (faithful, concise, gym-domain terms; preserve ALL placeholders `{name}` and the ICU plural structure `{count, plural, one{…} other{…}}` — it/de/es use `one`/`other` like English). Do NOT translate placeholder names or change the ICU syntax. After this, the ARB-parity test (Task 2) must pass for all three.

- [ ] **Step 2: Notification locale strings.** `workout_notification.dart` builds "Rest" / "Workout in progress" with no context (and in a background isolate). Add a small standalone map + resolver (NOT ARB):
```dart
const _notifStrings = <String, Map<String, String>>{
  'en': {'rest': 'Rest', 'inProgress': 'Workout in progress'},
  'it': {'rest': 'Recupero', 'inProgress': 'Allenamento in corso'},
  'de': {'rest': 'Pause', 'inProgress': 'Training läuft'},
  'es': {'rest': 'Descanso', 'inProgress': 'Entrenamiento en curso'},
};

/// Resolve a notification string for the active locale, readable without a
/// BuildContext (works in the background isolate). Reads the persisted locale
/// override, else the platform locale, else en.
String _notifString(SharedPreferences prefs, String key) {
  final code = prefs.getString('settings.locale') ??
      PlatformDispatcher.instance.locale.languageCode;
  return (_notifStrings[code] ?? _notifStrings['en']!)[key] ??
      _notifStrings['en']![key]!;
}
```
Use `_notifString(prefs, 'rest')` / `'inProgress'` everywhere the notification body literals are built (`showFor`, the scheduled revert body, and the background handler — each already obtains a `SharedPreferences` instance or can; pass it in). Import `dart:ui` for `PlatformDispatcher`. (Title is the session name — user data, unchanged.)

- [ ] **Step 3: Verify + commit** — `make -C app analyze`, `make -C app test` (parity test green for all locales), `make -C app build` (Linux). `git commit -m "feat(app): it/de/es translations + localized notification strings"`.

---

### Task 10: Verify + ship v0.11.0 (INLINE — orchestrating session)

- [ ] `make -C app analyze` + `make -C app test` (all green, ~224) + `make -C app build-apk-release` → green. Add a quick smoke widget test under `Locale('it')` asserting a known screen renders an Italian string (e.g. the Today greeting or a button), proving the delegate chain resolves a non-en locale end to end.
- [ ] Final adversarial review subagent over `git diff main...localization`, focused on: any remaining hardcoded user-facing literal (`grep` for `Text('`/`Text("` with non-key content across lib/ui, lib/session, lib/shell, lib/widgets), ARB key parity + placeholder/plural-syntax validity across all 4 files, every widget test pumping a localized widget uses `wrapL10n` (no null-AppLocalizations crashes), the notification locale resolver works in the background isolate (reads prefs, no context), dates: `isoDate` storage UNCHANGED (range queries/absorb depend on `YYYY-MM-DD`), `initializeDateFormatting` called before any non-en DateFormat, and the Profile overscroll fix present. Confirm the generated `lib/l10n/app_localizations*.dart` is gitignored (not committed).
- [ ] Merge `--no-ff` → main, push, tag `v0.11.0` → CI publishes `reps-v0.11.0.apk`. User gate: set language to Italiano (and System) and verify Italian across Today/Plan/Session/Profile, plurals read right ("1 exercise"/"2 esercizi"), dates/weekdays localize, notification text localized, de/es render without layout breakage, and the Profile overscroll gray box is gone.

### Out of scope
Seed catalog / user-data translation; RTL; server/API message localization.
