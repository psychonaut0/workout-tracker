# Stop showing wrong things: design

Date: 2026-09-30
Status: approved (decisions confirmed in session)
Origin: the post-0.16.0 critique (`.impeccable/critique/2026-09-29T11-38-39Z__app-lib.md`), the P2 items that 0.17.0 left open: #5 (the Profile placeholder), #6 (lb correctness, the language dialog), #8 (brand fonts) and #10 (unsaved Plan edits). Every item was re-checked on main at 4215c1d before this design was written. Line numbers below are from that commit.

## Goal and success

Every number, name and label the app shows is true and consistent, in kg and in lb, in all four languages, and edits are not lost without a word. The increment adds no features.

The work is done when:
- the automated tests below pass, `make -C app analyze` reports no issues and the layout sweep in `app/test/layout/` stays green;
- the device checks at the end hold on a preview build.

## Decisions

- **Profile line:** computed, in the design's wording: "Training since Mar 2026 · 4-day split". "Since" is the date of the first logged workout, and the day count is the number of the user's own training days (Plan → Split). A part without data is dropped. With no data at all, the line is hidden.
- **Brand fonts:** Material text and the chart labels go through the same `google_fonts` helpers as every other style. No pubspec font families are declared.
- **One formatter per quantity:** set weights keep today's rule, bodyweight uses 1 dp everywhere, and one volume formatter serves Summary and History. Progress shows lb as whole pounds, like every other screen. Deltas are computed from the displayed, rounded values.
- **RIR is 0–5 everywhere.** The picker shows one row of six chips when each chip fits 48dp, and two rows of three otherwise.
- **Language picker:** the shared action sheet gains a selected state. Language names are endonyms, and the current choice is checked.
- **Discard prompt** on two exits: back from a Plan editor (the back chevron, system back, predictive back) and exit from Today while a Plan editor holds unsaved edits. A tab switch, minimize and process death do not prompt. Nothing is lost on a tab switch, and Android cannot show a prompt on minimize.

## Design

### 1. Profile training line (critique #5)

**Today:** `profileTrainingSince` is a fixed string in all four ARBs (app_en.arb:565; it/de/es:269), rendered as a plain `Text` in `_buildProfileHeader` (profile_screen.dart:1099-1104). Every user sees "Training since Mar 2026 · 4-day split", including on a fresh install.

**Data (`data/stats_repository.dart`):** a new re-listenable watch:

```dart
/// First logged session date (YYYY-MM-DD, or null with no sessions) and the
/// number of the user's own training days.
Stream<({String? firstSessionDate, int dayCount})> watchTrainingSummary();
```

It runs one light query and passes `triggerOnTables: ['sessions', 'day_templates']`:

```sql
SELECT (SELECT MIN(date) FROM sessions) AS first,
       (SELECT COUNT(*) FROM day_templates WHERE is_template IS NOT 1) AS days
```

It must filter `is_template IS NOT 1`. Synced template days sit in the local DB next to their absorbed copies, so a raw count doubles them. The query stays light on purpose: sharing `_QuickStats`' stream object would not share its SQL, because `reListenable` creates one upstream per listener.

**Wording (pure, in `ui/profile_screen.dart` or a small sibling file):**

```dart
/// The Profile header's second line, or null to hide it.
String? profileTrainingLine(AppLocalizations l, String localeName,
    {String? firstSessionDate, int? dayCount});
```

- The "since" part is `l.profileTrainingSince(fmtMonthYear(firstSessionDate, localeName))`. It is dropped when the date is null or doesn't parse.
- The split part is `l.profileSplitDays(dayCount)`. It is dropped when the count is null or 0.
- Both parts are joined with ` · `. The function returns null when neither part exists, and also while the data is still loading. A transient "0-day split" never shows.

**Month (`util/dates.dart`):** `String? fmtMonthYear(String? iso, String localeName)`:
- It uses `DateFormat.yMMM(localeName)` on `DateTime.tryParse('${iso}T00:00:00')`, which is local midnight, so no timezone shift can move the month.
- It returns null for a bad or empty date. It must never use `DateTime.parse`: a throw during build renders the gray ErrorWidget.
- Real output (intl on the pinned SDK): en "Mar 2026", it "mar 2026", de "März 2026", es "mar 2026". The quirks are real and accepted: de "Jan." / "Sept." / "Dez.", es "ene", it "set".

**Rendering:**
- A new `_TrainingLine` StatefulWidget holds the stream in a `late final` field, as `_QuickStats` does. It renders the 3dp gap plus the text, or `SizedBox.shrink()` when the line is null, including on stream error.
- The style is unchanged: `WorkoutType.mono(size: 11, color: tokens.faint)`, wrapping, not a FitLabel. No word in any candidate string exceeds the 207dp column at 320dp and 2.0×.
- It still shows only when the name is not being edited, as today.
- The locale comes from `Localizations.localeOf(context).toLanguageTag()`.

**Strings.** `profileTrainingSince` becomes a message with a String `month` placeholder, and a new ICU plural `profileSplitDays` is added:

| | profileTrainingSince | profileSplitDays (=1 / other) |
|---|---|---|
| en | Training since {month} | 1-day split / {count}-day split |
| it | Ti alleni da {month} | split di 1 giorno / split di {count} giorni |
| de | Training seit {month} | 1-Tag-Split / {count}-Tage-Split |
| es | Entrenando desde {month} | rutina de 1 día / rutina de {count} días |

Spanish says "rutina" because the Plan tab calls the split "Rutina". Plurals use the `=1{…}` form, like most existing messages.

**Known behaviour:**
- A live, unfinished workout is not in `sessions`, so it doesn't set "since" until it is finished.
- Deleting the oldest session moves "since" forward.
- For a synced user, absorbed template days appear on the first restart after sync attach, because absorb runs only at boot.

### 2. Brand fonts resolve everywhere (critique #8)

**Today:**
- `WorkoutType.hankenTextTheme` (typography.dart:72-91) builds 15 const styles with `fontFamily: 'HankenGrotesk'`.
- `line_chart.dart` uses `fontFamily: 'JetBrainsMono'` in three `TextStyle`s (298-302 y-labels, 376-380 month labels, 427-432 value chip).
- google_fonts 6.3.3 registers only per-weight families (`HankenGrotesk_regular`, `JetBrainsMono_700`, …; google_fonts_base.dart:114-117, 224). Nothing registers the plain names, because pubspec has no `fonts:` section.
- Everything that falls back to the theme's text styles therefore draws in Roboto on Android: onboarding (the only direct `textTheme` reader), login, every SnackBar, the export `showDateRangePicker` (profile_screen.dart:568), and both charts' labels (Progress and Bodyweight). `WDialog` and the update dialog set `WorkoutType` styles themselves and are not affected.

**Fix:**
- `hankenTextTheme` returns `GoogleFonts.hankenGroteskTextTheme(_hankenSizes)`, where `_hankenSizes` is today's size/weight table without the family.
  - It must **never** be called with no argument. Its default base is `ThemeData.light().textTheme`, which would put dark text on the dark theme.
  - The theme's weights (400/500/600) are all bundled, so no network fetch happens.
- The chart's label styles come from two top-level helpers in `line_chart.dart`: `chartLabelStyle(Color)`, which is `WorkoutType.mono(size: 9, color: …)`, and `chartChipStyle(Color)`, which is `WorkoutType.mono(size: 12, weight: FontWeight.w700, color: …)`. They are built once per `paint()`, not per gridline.
- `_LineChartPainter` passes `repaint: PaintingBinding.instance.systemFonts` to `super`, so labels painted before a face finished loading repaint when it arrives. This matters under reduced motion, where the chart paints exactly once.
- Two stale comments are fixed: typography.dart:65-71, which justified the literal name, and app_theme.dart:6, which refers to a `_buildTextTheme` that doesn't exist.
- `test/theme/tokens_test.dart` gains `TestWidgetsFlutterBinding.ensureInitialized()`. Once `buildTheme` goes through google_fonts, its asset-manifest load needs the binding.

**Known trade-off:** google_fonts families are per weight. A future `textTheme.x!.copyWith(fontWeight: …)` would get a synthetic bold of the wrong face. No code does this today; the typography doc comment says so.

### 3. lb correctness: one formatter set (critique #6)

**Today:** four unrelated weight rules, and every critique example reproduces from the harness's `seedLong` data:

| Screen | Rule | What goes wrong |
|---|---|---|
| Summary volume (session_summary_screen.dart:384-392) | ≥1000 → `x.yt` in both units | 3268 lb reads "3.3t", and 999.6 kg reads "1000kg" |
| History 4-week volume (history_screen.dart:152-156) | always ÷1000, `toStringAsFixed(1)`, "t" for kg / bare "k" for lb | 12961 lb reads "13.0k" |
| Progress (progress_screen.dart:252-253) | `fmtPlain`, 1 dp | lb 100 kg reads "220.5" next to "226", and every other screen shows "220" |
| Today tile and Profile stat (today_screen.dart:466, profile_screen.dart:237) vs the bodyweight view (bodyweight_view.dart:220/251/357) | `fmtWt`, whole lb / ≤2 dp kg, vs `fmtPlain`, 1 dp | "182" vs "181.7", and "82.37" vs "82.4" |

**New file `app/lib/units/unit_format.dart`** (pure functions):

| Function | Rule | kg | lb |
|---|---|---|---|
| `fmtLoad(double display, Unit)` | the set-weight rule, **byte-identical** to today's `UnitService.fmtDisplay`; `fmtDisplay` delegates to it | `102.5`, `60.25` (≤2 dp trimmed) | `226`, `220` (whole) |
| `fmtBodyweight(double display)` | 1 dp, `.0` trimmed | `82.4`, `82` | `181.7` |
| `fmtVolume(double kg, Unit)` | round first; `< 1000` → whole with unit; else thousands at ≤1 dp trimmed | `850kg`, `1t`, `1.5t`, `5.9t` | `850lb`, `1k lb`, `3.3k lb`, `13k lb` |
| `fmtCount(double v)` | grouped whole number (today's `fmtThousands`) | `1,483` | `3,268` |

- Each formatter has a matching `round…` helper that returns the displayed precision as a double. It is derived from the formatter's own string, so the formatter and the rounding can never disagree at binary half-cases.
- `UnitService` gains `fmtBw(double kg)` and `fmtVol(double kg)`. `fmtWt(kg)` and `fmtDisplay` keep their behaviour exactly. The ruler's echo detection and the typed-entry untouched-seed check compare display strings, so the set-weight rule must not change.
- `fmtPlain`, `fmtSigned` (dead) and `fmtThousands` are deleted once every call site has moved. Their tests move to `unit_format_test.dart`.

**Call sites:**
- Summary and History volume tiles → `fmtVol`.
- Progress `_fmtVal`:
  - top set and e1RM → `fmtLoad(v, unit)`;
  - the volume metric → `fmtCount`.
- Today bodyweight tile and Profile bodyweight stat → `fmtBw`.
- Bodyweight view Current, Lowest and history rows → `fmtBodyweight`.
- The LineChart value chip: `LineChart` gains a required `String Function(double) formatValue`. Progress passes `_fmtVal` and BodyweightView passes `fmtBodyweight`, so the chip matches the cards. The volume chip showed "1482.5kg" against the card's "1,483".
- The exercise editor start weight (exercise_editor.dart:493/498) → `fmtLoad` for `format` and `formatForEdit`. That makes 1.25 kg "1.25", not "1.3", and 20 kg in lb "44", matching the live set, not "44.1". It stays in DISPLAY units and must **not** gain `parseDisplay` (app/AGENTS.md).

**Deltas from displayed values:**
- Progress per-row deltas (progress_screen.dart:534), the 12-week stat (`progressDeltaStat`), `topSetChange` / `changeLabel` (progress_change.dart) and the bodyweight deltas (bodyweight_view.dart:208, :326) subtract the **rounded** endpoints.
- The delta's colour and the goal tone (`displayedBodyweightDelta`) come from that same rounded difference.
- A change below display precision reads "same", never "+0".
- `changeLabel`'s `WeightChange` branch gains the same "same" guard `signedChange` has.
- The stale doc at bodyweight_goal.dart:16 is corrected.

**Unchanged on purpose:**
- Storage strings: every `toStringAsFixed(2)` write, which stays dot-decimal.
- The add-weight sheet's input display (fixed 1 dp).
- The chart's y-axis ticks.
- `est1rm`.
- Localised decimal and grouping separators, deferred (see Out of scope). No formatter may ever produce a grouping separator in an edit seed: in it/de/es "1.102" would parse as 1.102.

**Departures from the design handoff (recorded deliberately):** the handoff has the bare lb "k" (screen-history.jsx:72) and 1 dp everywhere on Progress (ui.jsx `fmtKg`). This app already departed once: kg set weights moved to ≤2 dp in the ruler-zoom increment.

### 4. RIR 0–5 everywhere (critique #6)

**Today:**
- `RirPicker` hard-codes four chips, 0–3 (rir_picker.dart:43-55).
- The day- and exercise-editor steppers hard-code `min: 0, max: 5` (day_editor.dart:729-747, exercise_editor.dart:642-666).
- `rirMin` / `rirMax` (models.dart:36-38) are used only by the clamp helpers.
- A prescribed 4–5 can't be logged in the live strip, the live card or History.
- At 320dp and 2.0× text, the live screen's four chips are already under 48dp wide: about 47dp in the post-log strip and 45dp in the live card.

**Fix:**
- `rirMin` / `rirMax` become the single range for pickers and editors. The doc comment changes from "the editors' bounds" to "the RIR range".
- `RirPicker` iterates `rirMin..rirMax`, and all four steppers pass `min: rirMin.toDouble(), max: rirMax.toDouble()`.
- **Layout:** a `LayoutBuilder` picks one row of six when `maxWidth / 6 ≥ 48`, otherwise two rows of three with a 3dp row gap. Rows are always balanced, never 5+1.
  - At 412dp and 1.0× that gives one row in all three hosts: the post-log strip (set_line.dart:150-167), the live card (live_set_card.dart:91-109) and History (set_editor_sheet.dart:598-615). At 320dp, or at 2.0×, it gives two rows.
  - Each chip's tappable slot (`rir-$n`, `HitTestBehavior.opaque`) is ≥48×48dp in every case.
- **Values:**
  - A stored value outside the range (possible from the old free-text editor, a restore or the server, none of which clamp) selects no chip and is never rewritten.
  - `null` stays a valid "no RIR" state.
  - The editors keep today's clamp-on-touch behaviour for out-of-range prescriptions.
- The doc comments on `RirPicker` say 0–5.

### 5. Language picker (critique #6)

**Today:** `_pickLanguage` (profile_screen.dart:412-432) is a `showWDialog` with five `WDialogAction`s and an empty message:
- it renders as a wrapped row of text buttons, with the last one (Español) always in the accent colour;
- nothing marks the current language;
- the names are translated ("Tedesco", "Englisch").

**Shared sheet (`widgets/w_action_sheet.dart`):**
- `WSheetAction` gains `bool selected = false`, and `icon` becomes optional.
- A selected row draws a trailing `Icon(WIcons.check, size: 20, color: tokens.accentText)`. It is a thin mark, so `accentText`, never `accent`. The row gets `Semantics(selected: true)`, as the exercise sheet does.
- Row labels wrap to at most two lines (`FitLabel`) instead of ellipsizing, so "Predeterminado del sistema" survives 320dp at 2.0×.
- The rows scroll inside the modal's 9/16 height cap. The six-row live-workout menu already reaches that cap.
- Rows stay ≥56dp, and the keys (`sheet-action-$i`) and the destructive/disabled colours are unchanged.
- A row may carry `Locale? labelLocale`. The row then wraps its label in `Semantics(localeForSubtree: labelLocale)`, so TalkBack reads "Deutsch" in German. Never `Localizations.override`: it resets the app-wide TalkBack locale.

**Language sheet:**
- It opens with `showWActionSheet<String>(title: l.settingsLanguage, …)`.
- Rows, in order: `l.languageSystem` (value `'system'`; a non-null sentinel, because null means dismissed), English, Italiano, Deutsch, Español.
- The row for the current override is selected, or the system row when the override is null. An unknown stored override selects nothing.
- The locale is applied after the sheet pops, as today.
- The endonyms live in one const table, `app/lib/settings/app_languages.dart`: `[(code: 'en', name: 'English'), (code: 'it', name: 'Italiano'), (code: 'de', name: 'Deutsch'), (code: 'es', name: 'Español')]`.
- The Profile row's sub-label (`_languageLabel`) reads the same table, so an Italian UI shows "Deutsch", not "Tedesco".
- `languageEnglish`, `languageItalian`, `languageGerman` and `languageSpanish` are deleted from all four ARBs. `languageSystem` and `settingsLanguage` stay.

**Goal picker (profile_screen.dart:442-455):** moves to `selected:`, replacing the swap of its leading icon for a check. The chart-correctness spec's "current one marked by a check" still holds.

**Fallback bug:**
- gen_l10n orders `supportedLocales` alphabetically, so it starts [de, en, es, it], and Flutter falls back to `supportedLocales.first`.
- So "System default" on an unsupported phone language, such as French, shows German, while the notifications fall back to English.
- `app/l10n.yaml` gains `preferred-supported-locales: [en]`. Unsupported languages then fall back to English everywhere. That corrects the localization spec's assumption (2026-06-08, line 29).

### 6. Unsaved Plan edits (critique #10)

**Today:** the day and exercise editors are in-tab sub-views of `PlanScreen` (plan_screen.dart:36-38, 171-176), not routes. `_onBack` clears `_editor` with no check (:70), and both the header chevron (:109) and `handleBack` (:73-77, reached by system and predictive back through AppShell's root `PopScope`) call it. Neither editor has a Cancel or a snapshot. The critique's "tab switch discards" is wrong on main: IndexedStack keeps the editor alive, and a typed stepper value commits when the hidden tab drops focus. The real silent losses are:
- the chevron;
- system or predictive back;
- back on Today, which calls `SystemNavigator.pop()` (app_shell.dart:160), finishes the Activity and destroys the engine while a dirty editor sits on the hidden Plan tab.

**Guard handle (`ui/editor_guard.dart`):**

```dart
/// Lets PlanScreen ask the open editor whether leaving would lose edits.
/// One instance per open editor: never reused across opens.
class EditorGuard {
  bool Function() isDirty = _never;
}
```

- `_EditorRoute` gains a `guard`, and `_openEditor` creates a fresh one for every open. A fresh handle also avoids a duplicate GlobalKey during the 220ms `AnimatedSwitcher` overlap.
- `DayEditor` and `ExerciseEditor` take an optional `EditorGuard? guard` and set `guard.isDirty` in `initState`.

**Dirty rule:** an editor is dirty when a value snapshot of what Save would write differs from the snapshot taken right after `_loadData` finishes normalising. That normalisation:
- fills slot defaults via `resolveSlot`;
- orders RIR via `rirOrdered`;
- turns a half-set RIR into null;
- skips orphan slots;
- uses 0 as the rest sentinel.

Each editor extracts its draft-building code from `_save` into one `_currentDraft()`, which Save and the snapshot both use.
- **Day snapshot:** trimmed name, focus (empty → null), weekday, and the slots as value records (item id, exercise id, work, warm-up, rep low/high, RIR low/high). `DaySlotRow` mutates `SlotDraft` in place, so the snapshot must copy values and compare the list element-wise.
- **Exercise snapshot:** the `ExerciseDraft` fields, with start weight and plate step as kg `toStringAsFixed(2)` (the persisted form, so an lb +/− round trip is not a change) and rest 0 → null.
- **Not dirty:** before loading finishes, and while a save is in flight (back then closes as today and the save still lands). An untouched new day or exercise is not dirty.
- **Accepted as dirty,** because they would persist differently: touching an RIR stepper that was unset; removing and re-adding the same exercise (new item id); Compound on → off after it seeded warm-ups.

**Close flow (`PlanScreenState`):**

```dart
/// Closes the open editor, asking first if it holds unsaved edits.
/// Returns true if the editor closed.
Future<bool> requestClose();

/// Whether the open editor would lose edits if closed now.
bool get hasUnsavedEdits;
```

`requestClose`:
1. It is re-entrant-safe: a second call while one is running returns false.
2. It calls `commitPendingInput()`, so a focused stepper's typed value counts.
3. Not dirty → close.
4. Dirty → `showWConfirm(title: l.planDiscardTitle, message: <day or exercise message>, cancelLabel: l.commonKeepEditing, confirmLabel: l.commonDiscard, destructive: true)`. Only `true` closes; `false` and `null` (barrier or back) mean keep editing. It closes only if the same editor is still open.

Wiring:
- The header `_BackButton`, including its `Semantics.onTap`, calls `requestClose`.
- `handleBack()` returns true synchronously and runs `requestClose()` unawaited.
- Save and Delete close **only their own editor** (`onBack` becomes a closure bound to the route that checks `identical(_editor, route)`). A late save can no longer close a different editor opened during the fade.

**Exit from Today:**
- `decideBack` gains `bool planEditsAtRisk`. On tab 0 with edits at risk it returns a new `BackAction.confirmExit`; otherwise it behaves as today.
- AppShell handles `confirmExit` in three steps:
  1. switch to Plan (`_index = 3`);
  2. `await requestClose()`;
  3. if the editor closed (Discard), call `SystemNavigator.pop()`, completing the exit the user asked for. On Keep editing, stay in the editor.
- `planEditsAtRisk` is `_planKey.currentState?.hasUnsavedEdits ?? false`. The hidden tab's typed values are already committed, because the tab lost focus.

**Strings (en/it/de/es):**

| key | en | it | de | es |
|---|---|---|---|---|
| planDiscardTitle | Discard changes? | Scartare le modifiche? | Änderungen verwerfen? | ¿Descartar los cambios? |
| planDiscardDayMessage | Your changes to this training day will be lost. | Le modifiche a questo giorno di allenamento andranno perse. | Deine Änderungen an diesem Trainingstag gehen verloren. | Se perderán los cambios de este día de entrenamiento. |
| planDiscardExerciseMessage | Your changes to this exercise will be lost. | Le modifiche a questo esercizio andranno perse. | Deine Änderungen an dieser Übung gehen verloren. | Se perderán los cambios de este ejercicio. |
| commonKeepEditing | Keep editing | Continua a modificare | Weiter bearbeiten | Seguir editando |

`commonDiscard` already exists.

## Testing

Every behaviour gets a failing test first. Run tests only as `timeout 900 make -C app test [TEST=<file>] > /tmp/claude-1000/<name>.log 2>&1; echo EXIT=$?`. Never run `make -C app fmt` or `dart format` on a directory. Run `make -C app get` after ARB changes.

**Pure tests:**
- `profileTrainingLine` in en/it/de/es: both parts; the singular; each part alone; neither → null; loading → null; a bad date drops "since".
- `fmtMonthYear` with real intl output, including de "Sept. 2026".
- `unit_format_test.dart`:
  - every rule and boundary: 850, 999.6 (→ "1t", never "1000kg"), 1000, 1482.5 kg → "1.5t", 3268.35 lb → "3.3k lb", 12960.98 lb → "13k lb", 5879 kg → "5.9t";
  - `fmtLoad` byte-identical to today's `fmtDisplay` over a sweep;
  - no grouping in `fmtLoad` at 1102 lb;
  - round/format agreement at half-cases.
- Rounded-first deltas: 100 vs 100.1 kg in lb reads "same"; the colour follows the label.
- The edit snapshots:
  - untouched equals initial; reorder-then-back equals initial;
  - remove + re-add is a change;
  - whitespace is ignored;
  - an lb round trip is not a change;
  - rest 0 equals default.
- `decideBack` with the new input.
- The endonym table's codes equal `AppLocalizations.supportedLocales`.
- `basicLocaleListResolution([Locale('fr', 'FR')], AppLocalizations.supportedLocales) == Locale('en')`.

**Widget tests over the real DB (`test/support/screen_harness.dart`):** use `settleReal` / `settleUntilFound`, never `pumpAndSettle`. End every test with `harness.unmount(tester)` and `tearDown(harness.close)`.
- **Profile line:**
  - fixed-date seeds (e.g. `DateTime(2026, 3, 14)`) render "Training since Mar 2026 · 2-day split" in en and de;
  - a fresh DB shows no line, and the old placeholder text is found nowhere;
  - days-only and sessions-only cases;
  - deleting the earliest session updates the month.
- **lb screens** (`prefs: {'unit': 'lb'}`, seedLong):
  - Summary no longer shows "3.3t" and shows "3.3k lb";
  - History no longer shows "13.0k" and shows "13k lb";
  - Progress has no "220.5";
  - Today and the bodyweight view show the same bodyweight string.
  - The kg counterparts are pinned too ("1.5t", "5.9t", "82.4").
- **Fonts** (`setUpAll(preloadAppFonts)`): proportional-width checks (`'iiii'` < `'MMMM'`/2) and mono advance checks (`'0000000000'` at 20px ≈ 120):
  - a default `Text` and a `FilledButton` label under `buildTheme`;
  - all 15 `textTheme` slots;
  - `chartLabelStyle` / `chartChipStyle`.

  They fail on main today. The no-network test calls `buildTheme` before `pendingFonts`, so an unbundled theme weight fails. A source guard fails on any `fontFamily: '` literal in `app/lib` outside `theme/typography.dart`.
- **RIR:**
  - `RirPicker` renders exactly `rir-$rirMin`…`rir-$rirMax`; `rirMax` selects and reports; 7 and null select nothing.
  - Every chip slot is ≥48×48 at the real host widths: SetLine and LiveSetCard at 262dp for a 320dp phone, History in its sheet, at 1.0× and 2.0×, with a 412dp one-row case.
  - `set_line_test`'s ≥48dp test extends to every chip and to 2.0×.
  - A stored `rirMax` survives a History weight edit (the local `FakeSessionRepository` in `set_editor_sheet_test.dart`).
  - The editor tests reference `rirMax`, not the literal 5.
- **Language sheet:**
  - in each UI locale all four endonyms show and "Tedesco", "Englisch" and "Inglés" are absent;
  - the current row has the check and the selected semantics, and no other row does;
  - with a null override the system row is marked;
  - rows are ≥48dp;
  - tapping returns the code or `'system'`; the barrier returns null;
  - "Predeterminado del sistema" is not ellipsized at 320dp and 2.0×;
  - the endonym row's semantics locale is `de`;
  - the check's colour is asserted in a light theme with `accents[3]`, where `accentText != accent`.
  - Profile integration: pick Deutsch → `harness.settings.localeOverride == 'de'`, and the row's sub-label reads "Deutsch".
- **Discard guard** (AppShell over the real DB):
  - untouched → back closes with no dialog;
  - edited → `tester.binding.handlePopRoute()` shows the dialog; Keep editing keeps the edit; Discard closes, and reopening shows the DB value;
  - a half-typed stepper value (focus still in the field) → back prompts;
  - the header chevron behaves the same as back;
  - Save closes with no dialog;
  - edit → another tab → back to Plan: the edit is intact and no dialog appeared;
  - an lb exercise +/− round trip → no prompt;
  - exit from Today with a dirty editor: `SystemChannels.platform` is mocked to record `SystemNavigator.pop`. The shell switches to Plan and shows the dialog, and pop is not called. Keep editing stays; Discard calls pop.

**Layout sweep (`test/layout/`):**
- lb cases for Summary and History.
- Live-screen states with the post-log RIR strip open (`logLiveSet`) and the live card's RIR row (`focusSet` on a logged set). Today the sweep never renders a `RirPicker`.
- The Profile sweep waits for the training line (`settleUntilFound`) before checking, plus one es case at 320dp and 2.0×.

## Device checks (preview build)

- **Build:** `gh workflow run android-preview.yml --ref feat/stop-showing-wrong-things -f build_number=<N>`, with N between the installed versionCode (37) and the next release run number (38). Install with `adb install -r`.
- **Safety:**
  - Wi-Fi adb at the IP:port the user gives.
  - Every tap and screenshot is guarded on `io.github.psychonaut0.reps` being the foreground app, and stops if it isn't.
  - View only: never log, save, delete or sign out. A Plan editor is opened, changed, and backed out of with Discard or Keep editing, never saved.
  - Use `svc power stayon true` and DND while working. Restore both, and any setting changed, at the end.

Checks:
1. The Profile line shows the real first-workout month and day count, in the current language.
2. Fonts: login, a SnackBar, the export date-range picker (open and cancel), and the Progress and Bodyweight chart labels are in Hanken Grotesk / JetBrains Mono, at 1.0× and 2.0×. Onboarding only if it can be reached without resetting anything.
3. lb (switched temporarily, then restored): Summary or History volume reads "…k lb", Progress shows whole pounds, and the Today tile matches the bodyweight view.
4. RIR: in History, opening a past workout's set editor shows the 0–5 picker, in one row or two as the phone's width dictates. View it, don't tap a chip: the sheet autosaves. The two live-workout hosts need a logged set, which the view-only rule forbids, so the widget and layout tests cover them.
5. Language: the sheet shows endonyms with the current one checked, rows are comfortable to tap, and TalkBack (if its tutorial can be skipped) reads "Deutsch" in German. Restore the original language.
6. Discard: the chevron, the back gesture, and exit-from-Today with a changed editor each ask; Keep editing keeps the change; Discard throws it away; an untouched editor closes silently.

## Out of scope

- Localised decimal and grouping separators ("66,4", "12.961"). The localization spec deferred them, and they need their own increment.
- Seeding a live set's RIR from the plan. It is always 1 today, which is a separate behaviour change.
- The screen-reader semantics pass (critique #9), including per-chip RIR labels.
- Persisting editor drafts across a kill or minimize; discard prompts on a tab switch.
- Editing and deleting bodyweight entries (the other half of critique #10).
- First-run empty states and the starter split (the rest of critique #5).
- The Profile server-URL field, which also drops text that hasn't been applied.

## Release

Recommend **0.18.0**. Everything here is a correctness fix, but it visibly changes behaviour on several screens: a new prompt, a new sheet, RIR 0–5, fonts on five surfaces and different lb numbers. Before tagging, bump `app/pubspec.yaml` to `0.18.0+N`.
