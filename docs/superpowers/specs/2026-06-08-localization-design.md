# v0.11.0 — localization (en/it/de/es) + profile overscroll fix

**Date:** 2026-06-08
**Status:** Approved (design)
**Scope:** Add full UI localization for English (baseline), Italian, German, and Spanish using Flutter's official ARB + `gen_l10n` toolchain, with device-locale selection plus a manual in-app override. Plus one bundled bugfix: the Profile screen's gray overscroll artifact. User verifies Italian; de/es are best-effort. Ships as v0.11.0.

---

## 1. Localization

### Toolchain (official ARB / gen_l10n — no third-party dependency)
- `pubspec.yaml`: add `flutter_localizations` (SDK) and `intl`; set `flutter: generate: true`.
- `app/l10n.yaml`:
  ```yaml
  arb-dir: lib/l10n
  template-arb-file: app_en.arb
  output-localization-file: app_localizations.dart
  output-class: AppLocalizations
  nullable-getter: false
  ```
  (`nullable-getter: false` → `AppLocalizations.of(context)` returns non-null when the delegate is registered, so call sites read `AppLocalizations.of(context).foo` — no `!`.)
- `lib/l10n/app_en.arb` is the template carrying every key (+ `@key` metadata: description, placeholders, ICU plurals). `app_it.arb`, `app_de.arb`, `app_es.arb` mirror its keys.
- Generated `AppLocalizations` is consumed via `AppLocalizations.of(context)`.

### Locale wiring
- `MaterialApp` (built in the `Builder` under MultiProvider in `main.dart`) gains:
  - `localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]`
  - `supportedLocales: AppLocalizations.supportedLocales`
  - `locale: settingsService.locale` (null → follow the device; Flutter falls back to `en` for unsupported device locales).
- `SettingsService`: add `String? _localeOverride` (null = system; else `'en'|'it'|'de'|'es'`) persisted under `settings.locale`, with `localeOverride` getter, `setLocaleOverride(String?)`, and `Locale? get locale => _localeOverride == null ? null : Locale(_localeOverride!)`. Loaded in `load()`. Because the MaterialApp `Builder` watches `SettingsService`, changing it rebuilds with the new locale live.

### Language picker (Profile)
A new row in Profile's Appearance group (or a dedicated "Language" group): a `_Row` showing the current language label, tapping opens a chooser in the app's `showWDialog` style with: **System default**, **English**, **Italiano**, **Deutsch**, **Español** (each in its own language). Selecting calls `settings.setLocaleOverride(code-or-null)`. The current selection shows a check/accent.

### String scope
- **Localize**: all UI chrome across `lib/ui`, `lib/shell`, `lib/session`, `lib/widgets`, onboarding, dialogs, buttons, labels, empty states, error/snackbar text, stat-tile labels, etc.
- **Muscle-group labels** (`lib/data/muscles.dart`): the 8 display labels become ARB keys. Add `localizedMuscle(BuildContext, String key)` that maps the stable DB key (`chest`…) to an ARB string for DISPLAY; keep `muscleLabel`/`orderedMuscles`/the keys themselves as data (ordering + storage unchanged). Replace display call sites with the context-aware version.
- **Dates/weekdays/numbers**: route through `intl` `DateFormat` with the active locale. `util/dates.dart`'s `fmtDate`/weekday-short helpers become locale-aware (take a `BuildContext`/locale, or callers pass `Localizations.localeOf(context)`). Relative-time strings ("just now", "Xm ago", "Xh ago") become ARB plurals.
- **ICU plurals/placeholders**: counts use ICU plural in ARB — e.g. `"{count, plural, =1{1 exercise} other{{count} exercises}}"`, same for sets/PRs. Interpolations (`$equip · compound`, `$work×$repLow–$repHigh · RIR …`, `Failed to save session: $e`) become placeholder'd messages. The `PR${n>1?'s':''}` hand-pluralization is replaced by a proper ICU plural.
- **Do NOT localize**: user-owned data (exercise names, day names, notes), the English seed catalog (`catalog_seed.dart` stays English — the seeded rows are owned, editable data; an it/de/es user gets localized UI with English exercise names until they rename). Stable enum/DB keys.

### Notifications (the one non-ARB place)
`workout_notification.dart` builds notification text ("Rest", "Workout in progress") with NO `BuildContext` — and the +30s path runs in a **background isolate** where `AppLocalizations` is unreachable. So those ~3 strings are localized via a small standalone `Map<String, Map<String,String>>` (locale → key → string) in the notification layer, resolving the locale from the persisted `settings.locale` (read from SharedPreferences; fall back to the system locale via `PlatformDispatcher.instance.locale`, then `en`). The background isolate reads the same persisted locale. This is the only user-facing text not flowing through ARB; keep it to the notification literals.

### Test-harness migration
No widget currently uses `AppLocalizations`; after migration every localized widget calls `AppLocalizations.of(context)`. Widget tests that pump `MaterialApp(theme: buildTheme(...))` without the localization delegates would get no `AppLocalizations` (build error), and tests asserting English literals via `find.text('…')` must run under English. Add a shared test helper (e.g. `app/test/support/l10n_harness.dart` exposing `wrapL10n(Widget child, {Locale locale = const Locale('en')})` that wraps in a `MaterialApp` with `buildTheme` + the delegates + `supportedLocales` + the locale). Migrate the affected widget tests to it. Tests asserting specific English strings keep passing under `Locale('en')`.

### Translations
EN is extracted verbatim from the current strings. IT/DE/ES authored as faithful translations (concise, gym-domain-appropriate; preserve placeholders/plural categories — German/Italian/Spanish plural rules are `one`/`other`, same as English for these counts). A test asserts the four ARB files have an **identical key set** (catches any missing/extra translation key).

---

## 2. Profile overscroll gray-box fix

**Root cause (high confidence):** v0.8.2 made all Scaffolds transparent (the ambient layer paints the app background via a backmost `ColoredBox(tokens.bg)` in `AmbientLayer`). Profile's body is `Column[opaque header, Expanded(ListView)]` over that transparent Scaffold; on Android, the stretch-overscroll indicator (triggered by scroll-down-then-up) samples/composites the transparent region under the scrollable, surfacing a gray artifact pinned to the top.

**Fix:** wrap Profile's Scaffold `body` in `ColoredBox(color: tokens.bg, child: Column(...))` so the scroll area has a solid backing layer for the overscroll effect to sample. Profile is a pushed full-screen settings overlay, so an opaque background is appropriate (the ambient need not show behind it; the header was already opaque `tokens.bg`). Low-risk, definitively removes the transparent-region-under-overscroll condition regardless of the exact compositing path. Confirmed on-device by the user post-build (it's a render-time artifact CI can't reproduce).

---

## Testing
- ARB key-parity test (en/it/de/es identical key sets).
- Locale override: `SettingsService.locale` null→system, set→`Locale(code)`, persisted.
- `localizedMuscle` returns the localized label per locale and falls back for unknown keys.
- A widget smoke under `Locale('it')` asserting a known screen renders Italian (e.g. a button label).
- Plural messages resolve singular/plural correctly (e.g. `1 exercise` vs `2 exercises`, and the IT equivalents).
- Existing 220 tests pass after harness migration.
- On-device (user): switch language (system + each override), verify Italian across screens, notification text localized, and the Profile overscroll artifact is gone.

## Out of scope
Localizing the seed exercise catalog / user data; RTL (none of en/it/de/es is RTL); server-side / API message localization; localized number formatting beyond what `intl` gives for free (weight values stay as-is).
