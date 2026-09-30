# Stop showing wrong things: design

Date: 2026-09-30
Status: approved (decisions confirmed in session; revised after an adversarial review against the code)
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

- It must filter `is_template IS NOT 1`. Synced template days sit in the local DB next to their absorbed copies (absorb reads them and never deletes them), so a raw count doubles them. `NULL` counts as owned, as in `watchDays`.
- The query always returns exactly one row, so an empty DB emits `(firstSessionDate: null, dayCount: 0)`.
- It stays light on purpose. Sharing `_QuickStats`' stream object would not share its SQL, because `reListenable` creates one upstream per listener.

**Wording (pure, top-level in `ui/profile_screen.dart`):**

```dart
/// The Profile header's second line, or null to hide it.
String? profileTrainingLine(AppLocalizations l, String localeName,
    {String? firstSessionDate, int? dayCount});
```

- The "since" part is `l.profileTrainingSince(fmtMonthYear(firstSessionDate, localeName))`. It is dropped when the date is null or doesn't parse.
- The split part is `l.profileSplitDays(dayCount)`. It is dropped when the count is null or 0.
- Both parts are joined with ` · `. The function returns null when neither part exists.

**Month (`util/dates.dart`):** `String? fmtMonthYear(String? iso, String localeName)`:
- It uses `DateFormat.yMMM(localeName)` on `DateTime.tryParse('${iso}T00:00:00')`, which is local midnight, so no timezone shift can move the month.
- It returns null for a null, empty or bad date. It must never use `DateTime.parse`: a throw during build renders the gray ErrorWidget.
- Real output on the pinned SDK (intl and flutter_localizations agree): en "Mar 2026", it "mar 2026", de "März 2026", es "mar 2026". The quirks are real and accepted: de "Jan." / "Sept." / "Dez.", es "ene", it "set".

**Rendering:**
- `_ProfileScreenState`, which sits outside the Profile `ListView`, subscribes to `watchTrainingSummary()` in `initState`. It keeps the latest value in a field via `setState`, with an `onError` that clears the field, and cancels the subscription in `dispose`, following the pattern in today_screen.dart:185-209.
- `_buildProfileHeader` reads that field. The header is ListView child 0 and is swapped out while the name is being edited, so a stream owned by a widget inside it would be re-created on every remount. The line would then vanish for a query round trip and make the header jump. A field on the outer State doesn't.
- The whole Profile rebuilds when sessions or days change. That is rare, and acceptable at personal-data scale.
- The line renders the 3dp gap plus a `Text` with `key: const Key('profile-training-line')`, or nothing at all when `profileTrainingLine` returns null. It also renders nothing before the first value arrives, so a transient "0-day split" never shows.
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
  - It must **never** be called with no argument. Its default base is `ThemeData.light().textTheme`, which would put dark text (0xFF1D1B20) on the dark theme and drop the table's weights.
  - Called with the table, it keeps every size and weight, leaves colors null (so they still come from `colorScheme.onSurface` = `tokens.text`), and sets the per-weight families `HankenGrotesk_regular` / `_500` / `_600`. All three are bundled, so no network fetch happens.
- The chart's label styles come from two top-level helpers in `line_chart.dart`: `chartLabelStyle(Color)`, which is `WorkoutType.mono(size: 9, color: …)`, and `chartChipStyle(Color)`, which is `WorkoutType.mono(size: 12, weight: FontWeight.w700, color: …)`. They are built once per `paint()`, not per gridline.
- `_LineChartPainter` passes `repaint: PaintingBinding.instance.systemFonts` to `super`, so labels painted before a face finished loading repaint when it arrives. This matters under reduced motion, where the chart paints exactly once.
- Two stale comments are fixed: typography.dart:65-71, which justified the literal name, and app_theme.dart:6, which refers to a `_buildTextTheme` that doesn't exist.
- `test/theme/tokens_test.dart` is the only plain `test()` that calls `buildTheme`. It gains `TestWidgetsFlutterBinding.ensureInitialized()`, because once `buildTheme` goes through google_fonts, its asset-manifest load needs the binding.

**Known trade-off:** google_fonts families are per weight. A future `textTheme.x!.copyWith(fontWeight: …)` would get a synthetic bold of the wrong face. No code does this today; the typography doc comment says so.

### 3. lb correctness: one formatter set (critique #6)

**Today:** four unrelated weight rules. The lb examples reproduce from the harness's `seedLong` data; the kg edge cases (999.6 kg, a stored 82.37 kg) don't, and are covered by pure tests and one custom seed.

| Screen | Rule | What goes wrong |
|---|---|---|
| Summary volume (session_summary_screen.dart:384-392) | ≥1000 → `x.yt` in both units | 3268 lb reads "3.3t", and 999.6 kg reads "1000kg" |
| History 4-week volume (history_screen.dart:152-156) | always ÷1000, `toStringAsFixed(1)`, "t" for kg / bare "k" for lb | 12961 lb reads "13.0k" |
| Progress (progress_screen.dart:252-253) | `fmtPlain`, 1 dp | lb 100 kg reads "220.5" next to "226", and every other screen shows "220" |
| Today tile and Profile stat (today_screen.dart:466, profile_screen.dart:237) vs the bodyweight view (bodyweight_view.dart:220/251/357) | `fmtWt`, whole lb / ≤2 dp kg, vs `fmtPlain`, 1 dp | "182" vs "181.7", and "82.37" vs "82.4" |

**New file `app/lib/units/unit_format.dart`** (pure functions):

| Function | Rule | kg | lb |
|---|---|---|---|
| `fmtLoad(double display, Unit)` | the set-weight rule, **byte-identical** to today's `UnitService.fmtDisplay` body (unit_service.dart:52-62), which now delegates to it | `102.5`, `60.25` (≤2 dp trimmed) | `226`, `220` (whole) |
| `fmtBodyweight(double display)` | 1 dp, `.0` trimmed (today's `fmtPlain` rule) | `82.4`, `82` | `181.7` |
| `fmtVolume(double kg, Unit)` | see below | `850kg`, `1t`, `1.5t`, `5.9t` | `850lb`, `1k lb`, `3.3k lb`, `13k lb` |
| `fmtCount(double v)` | grouped whole number (today's `fmtThousands`) | `1,483` | `3,268` |

`fmtVolume` rule:
- `v = UnitService.fromKg(kg, unit).round()`, an int.
- `v < 1000` → `'${v}kg'` / `'${v}lb'`.
- Otherwise `tenths = (v / 100).round()`, which rounds half away from zero, exact at .5. Render `'${tenths ~/ 10}'` when `tenths % 10 == 0`, else `'${tenths ~/ 10}.${tenths % 10}'`, then append `t` (kg) or `k lb` (lb).
- Never use `toStringAsFixed` here. It misrounds binary half-cases: 1150 → "1.1", 9950 → "9.9".

Rounding helpers, each returning the displayed precision as a double:
- `roundLoad(double display, Unit)` = `double.parse(fmtLoad(display, unit))`, and `roundBodyweight(double display)` = `double.parse(fmtBodyweight(display))`. Both are derived from the formatter's own string, so they agree with it at binary half-cases (1.005 kg → 1). Parsing our own formatter output is safe: it is never empty or grouped.
- `roundCount(double v)` = `v.roundToDouble()`, which is `fmtCount`'s own rule. Never parse `fmtCount`'s grouped string.
- There is no `roundVolume`: no volume tile shows a delta.

`UnitService` gains `fmtBw(double kg)` and `fmtVol(double kg)`. `fmtWt(kg)` and `fmtDisplay` keep their behaviour exactly. The ruler's echo detection (ruler_picker.dart:299) and the typed-entry untouched-seed check (stepper.dart:197) compare display strings, so the set-weight rule must not change.

**Call sites:**
- Summary and History volume tiles → `fmtVol`. An empty 4-week window now reads `0kg` / `0lb` (was `0.0t` / `0.0k`), matching Summary for a zero-volume session.
- Progress `_fmtVal` (it has no `Unit` in scope; inside `build`, `unit` is the label String):
  - top set and e1RM → `fmtLoad(v, unitService.unit)`, with `roundLoad`;
  - volume and reps → `fmtCount(v)`, with `roundCount`. Reps are whole numbers under 1000, so no grouping appears.
- Today bodyweight tile and Profile bodyweight stat → `fmtBw`.
- Bodyweight view: Current, Lowest and history-row values → `fmtBodyweight`; the 30-day delta and per-row delta (bodyweight_view.dart:209, :375) → `signedChange(…, fmtBodyweight, l)`.
- The LineChart value chip: `LineChart` gains a required `String Function(double) formatValue`, which the painter receives. Progress passes `_fmtVal` and BodyweightView passes `fmtBodyweight`, so the chip matches the cards. The volume chip showed "1482.5kg" against the card's "1,483". The chart's series stays raw, so its y-domain and ticks don't change.
- The exercise editor start weight (exercise_editor.dart:493/498) → `fmtLoad` for `format` and `formatForEdit`. That makes 1.25 kg "1.25", not "1.3", and 20 kg in lb "44", matching the live set, not "44.1". It stays in DISPLAY units and must **not** gain `parseDisplay` (app/AGENTS.md). Every seeded plate step is ≥1 kg (≥2.2 lb), so consecutive ± values never display the same.

**Deltas from displayed values** (the mechanism):
- Progress: `_ProgressContent` gains `double _roundVal(double v)` next to `_fmtVal`, using `roundLoad` for top/e1RM and `roundCount` for volume/reps. It builds `shownValues = seriesValues.map(_roundVal).toList()` and passes `shownValues` to `_BigStatRow` and `_SessionLogCard`. `LineChart` keeps the raw `seriesValues`.
- `topSetChange`, `signedChange` and `progressDeltaStat` keep their signatures. Their docs now say the weights passed in are displayed (rounded) values.
- Current and Best don't change, because `fmtVal(round(x)) == fmtVal(x)` by construction.
- A row or tile is accent only when its label is not `progressSame` and its rounded delta is > 0. `progressDeltaStat`'s reps branch returns `unit: null` whenever the label is `progressSame`, so "same" never reads "same lb".
- `changeLabel`'s `WeightChange` branch gains the same "same" guard `signedChange` has. With rounded inputs it can't fire; it is defensive only.
- Bodyweight: `_BwStatRow` and `BodyweightHistoryCard` apply `roundBodyweight` to each value before subtracting, inside the widgets, so `bodyweight_history_card_test` can pin the behaviour. `displayedBodyweightDelta` stays and is fed that rounded difference. Its doc (bodyweight_goal.dart:16) now says it matches `fmtBodyweight`'s 1-dp precision, not `fmtSigned`.
- A change below display precision therefore reads "same" with the neutral colour, never "+0". A real change the old raw subtraction hid now shows: 100 → 100.1 kg in lb displays 220 → 221 and reads "+1".

**Deleted:** `util/format.dart` goes, with its four lib imports (line_chart, bodyweight_view, exercise_editor, progress_screen).
- `fmtPlain` and `fmtThousands` cases in `test/util/format_test.dart` move to `unit_format_test.dart` as `fmtBodyweight` / `fmtCount` cases.
- That file's `est1rm` group moves to a models test (e.g. `test/data/est1rm_test.dart`).
- `test/util/format_signed_test.dart` is deleted: `fmtSigned` is dead and has no successor.
- `test/ui/progress_change_test.dart` drops the import and uses `fmtBodyweight` (:75) and `fmtCount` (:78).

**Unchanged on purpose:**
- Storage strings: every `toStringAsFixed(2)` write, which stays dot-decimal.
- The add-weight sheet's input display (fixed 1 dp).
- The chart's y-axis ticks.
- `est1rm`.
- Localised decimal and grouping separators, deferred (see Out of scope). No formatter may ever produce a grouping separator in an edit seed: `parseNumberInput` reads ',' as the decimal separator (util/number_input.dart:48), so an en-grouped "1,102", or a future localised "1.102", would commit 1.102.

**Departures from the design handoff (recorded deliberately):** the handoff has the bare lb "k" (screen-history.jsx:72) and 1 dp everywhere on Progress (ui.jsx `fmtKg`). This app already departed once: kg set weights moved to ≤2 dp in the ruler-zoom increment.

### 4. RIR 0–5 everywhere (critique #6)

**Today:**
- `RirPicker` hard-codes four chips, 0–3 (rir_picker.dart:43-55).
- The day- and exercise-editor steppers hard-code `min: 0, max: 5` (day_editor.dart:729-747, exercise_editor.dart:642-666).
- `rirMin` / `rirMax` (models.dart:36-38) are used only by the clamp helpers.
- A prescribed 4–5 can't be logged in the live strip, the live card or History.
- At 320dp and 2.0× text, the live screen's four chips are already under 48dp wide: about 47dp in the post-log strip and 45dp in the live card.
- The live `SetLine` shows a null RIR as "RIR 0" (set_line.dart:128), although History hides it (set_editor_sheet.dart:524). A null working-set RIR reaches the live screen through resume and History-added sets.

**Fix:**
- `rirMin` / `rirMax` become the single range for pickers and editors. The doc comment changes from "the editors' bounds" to "the RIR range".
- `RirPicker` iterates `rirMin..rirMax`, and all four steppers pass `min: rirMin.toDouble(), max: rirMax.toDouble()`.
- **Layout:** a `LayoutBuilder` picks one row of six when `maxWidth / 6 ≥ 48`, otherwise two rows of three with a 3dp row gap. Rows are always balanced, never 5+1.
  - The chip slots tile each row. Every chip except the last *in its row* keeps a 3dp right margin inside its keyed `GestureDetector` (`rir-$n`, `HitTestBehavior.opaque`), so `maxWidth / 6` is the slot width, and each slot is ≥48×48dp in every case.
  - The picker absorbs taps inside its own rect: its rows sit in a `GestureDetector(behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: () {})`. So a tap in the 3dp row gap selects nothing and never reaches `SetLine`'s row tap. That tap would call `focusSet`, turning the logged set back into the live card and closing the strip.
  - `height` defaults to 48, the height every host uses, and its doc says so.
  - In two-row mode the host's "RIR" caption aligns with the first row: each host Row uses `crossAxisAlignment: CrossAxisAlignment.start`, and the caption sits in a 48dp-tall box centred vertically. In one-row mode this is identical to today's layout.
- **Where each layout appears.** Host picker widths use the host width, which is the phone width − 58 (2×16 list padding, 2×1 block border, 2×12 sets padding): 262dp at 320 and 354dp at 412. History's sheet uses the phone width.
  - At 320dp every host gives two rows.
  - At 412dp and 1.0× all three hosts give one row: slots of 50.1dp (post-log strip), 48.4dp (live card, only 0.43dp of slack) and 52.8dp (History).
  - At 412dp and 2.0× the strip (46.9dp) and the live card (45.4dp) give two rows, while History keeps one (49.8dp).
  - On common 360–400dp phones the two live hosts show two rows.
- **Values:**
  - A stored value outside the range (possible from the old free-text editor, a restore or the server, none of which clamp) selects no chip and is never rewritten.
  - `null` stays a valid "no RIR" state, and a logged working set with a null RIR shows no inline RIR text on `SetLine`, as History's line already does.
  - The editors keep today's clamp-on-touch behaviour for out-of-range prescriptions.
- The doc comments on `RirPicker` say 0–5.

### 5. Language picker (critique #6)

**Today:** `_pickLanguage` (profile_screen.dart:412-432) is a `showWDialog` with five `WDialogAction`s and an empty message:
- it renders as a wrapped row of text buttons, with the last one (Español) always in the accent colour;
- nothing marks the current language;
- the names are translated ("Tedesco", "Englisch").

**Shared sheet (`widgets/w_action_sheet.dart`):**
- `WSheetAction` gains `bool selected = false` and `Locale? labelLocale`, and `icon` becomes optional. All defaults are named, so every existing call site compiles unchanged (the two live-workout menus, the goal picker, `w_action_sheet_test`).
- A selected row draws a trailing `Icon(WIcons.check, size: 20, color: tokens.accentText)`. It is a thin mark, so `accentText`, never `accent`.
- The row's existing `Semantics(button:, enabled:)` gains `selected: a.selected ? true : null`, so unselected rows carry no selected state (`Tristate.none`), as in the exercise sheet.
- When `labelLocale` is set, the row's own `Semantics(button:, enabled:, selected:)` is wrapped in a separate outer `Semantics(localeForSubtree: labelLocale, child: …)`. The row stays one semantics node carrying label, locale, button, selected and tap, so TalkBack reads "Deutsch" in German on the node it focuses. Probed on Flutter 3.44, the other placements break the row:
  - on the label alone, the label splits off and the button is left unlabelled;
  - on the row's own `Semantics`, the tap splits from the button and selected node;
  - `MergeSemantics` drops the locale.
- Never use `Localizations.override`: it reloads every localization delegate for the subtree, and adds a container node, just to set one locale.
- Row labels wrap to at most two lines (`FitLabel`, `maxLines: 2`) instead of ellipsizing, so "Predeterminado del sistema" survives 320dp at 2.0×.
- The title stays pinned, and the rows scroll. They go in `Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)))`, a direct child of the sheet's Column (the app/AGENTS.md flex rule). On main, the six-row live-workout block menu already overflows the modal's 9/16 height cap on phones under about 760dp tall (about 865dp at 2.0×). It fits on the sweep's 915dp phone, so the sweep can't catch it.
- Rows stay ≥56dp, and the keys (`sheet-action-$i`) and the destructive/disabled colours are unchanged.

**Language sheet:**
- It is a public `Future<String?> showLanguageSheet(BuildContext context, {required String? current})` in `app/lib/settings/app_languages.dart`, next to the endonym table. It returns a code, `'system'` (a non-null sentinel, because null means dismissed), or null on dismiss. `_pickLanguage` calls it, maps `'system'` to null, and applies the locale after the sheet has popped, as today.
- It calls `showWActionSheet<String>(title: l.settingsLanguage, …)`. Rows in order: `l.languageSystem`, English, Italiano, Deutsch, Español. Endonym rows carry `labelLocale: Locale(code)`; the system row has none.
- The row for the current override is selected, or the system row when the override is null. An unknown stored override selects nothing.
- The endonyms live in one const table: `[(code: 'en', name: 'English'), (code: 'it', name: 'Italiano'), (code: 'de', name: 'Deutsch'), (code: 'es', name: 'Español')]`. The table's order is the sheet order.
- The Profile row's sub-label (`_languageLabel`) reads the same table: an Italian UI shows "Deutsch", not "Tedesco". Null, or an unknown code (which can't be written through the UI), shows `l.languageSystem`, as today.
- `languageEnglish`, `languageItalian`, `languageGerman` and `languageSpanish` are deleted from all four ARBs. They are referenced only in profile_screen.dart. `languageSystem` and `settingsLanguage` stay.

**Goal picker (profile_screen.dart:442-455):** every row keeps `icon: WIcons.target`, and the current goal gets `selected: true`, replacing today's swap of the leading icon for a check. The chart-correctness spec's "current one marked by a check" still holds.

**Fallback bug:**
- gen_l10n orders `supportedLocales` alphabetically, so it starts [de, en, es, it], and Flutter falls back to `supportedLocales.first`.
- So "System default" on a device whose language list holds no supported language (say, French only) shows German, while the notifications fall back to English.
- `app/l10n.yaml` gains `preferred-supported-locales: [en]`. `supportedLocales` becomes [en, de, es, it], and such a device falls back to English, matching the notifications. That corrects the localization spec's assumption (2026-06-08, line 29).
- A list with a supported secondary language (e.g. fr, de) still shows that language in the app and English in the notification. That mismatch predates this change and is out of scope.

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

- `_openEditor(kind, id)` builds a fresh `_EditorRoute` with its own `EditorGuard` (`_EditorRoute` drops `const`), and does nothing while `_editor != null`.
  - Callers pass kind and id, not a route.
  - The list is only reachable when no editor is open, so such a call can only come from a tap that fell through the `AnimatedSwitcher` stack to the outgoing list while the new editor still showed its spinner.
- A fresh route per open means an outgoing editor, still mounted during the 220ms fade, can never report on or close the new one. That is why it's a handle rather than a `GlobalKey<State>`, which two overlapping editors would duplicate.
- `DayEditor` and `ExerciseEditor` take an optional `EditorGuard? guard`, so `ExerciseEditor(id:, onBack:)` in existing tests still compiles. They set `guard.isDirty` in `initState`, and re-bind it in `didUpdateWidget` if `widget.guard` changes.

**Dirty rule:** an editor is dirty when a snapshot of what Save would write differs from the snapshot taken right after `_loadData` finishes normalising. The baseline is the snapshot *value*, never a stored draft.

Normalisation per editor:
- day: `resolveSlot` defaults, `rirOrdered`, orphan slots skipped;
- exercise: `rirOrdered`, a half-set RIR → null, the `?? 8 / 12 / 3 / 0` load defaults, and the rest 0 sentinel.

Each editor extracts its draft-building code from `_save` into one `_currentDraft()`. It keeps producing kg, and Save and the guard both use it. The snapshots are top-level pure functions in `ui/editor_guard.dart`:
- `daySnapshot(DayDraft)`: trimmed name, focus (empty → null), weekday, and a list of per-slot value records (item id, exercise id, work, warm-up, rep low/high, RIR low/high). `DaySlotRow` mutates `SlotDraft` in place (day_editor.dart:417-472), so the snapshot must copy values. A snapshot that holds `SlotDraft` references changes along with every edit and never reads as dirty.
- `exerciseSnapshot(ExerciseDraft)`: trimmed name and equipment, muscle, compound, start weight and plate step as kg `toStringAsFixed(2)` (null kept as null), reps, sets, warm-ups, RIR, rest 0 → null. The kg-string form is the persisted form, so an lb ± round trip is not a change. That was simulated over 1.4M cases with the real `clampRound2` and factor, and the only exceptions are sequences clamped at 0.
- Each returns a small value class whose `==` compares the slot list element-wise (`listEquals`). Never use a record holding a `List`: record equality compares a List field by identity, so two snapshots never compare equal.

Which states count:
- **Not dirty:** before loading finishes; while a save is in flight; and while a confirmed delete is in flight, from the delete confirm returning true until `deleteX` completes. In those cases back closes as today and the write still lands. An untouched new day or exercise is not dirty.
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
1. It is re-entrant-safe: a second call while one is running returns false. Two queued back events really do both reach the shell's handler.
2. It calls `commitPendingInput()`, so a focused stepper's typed value counts.
3. Not dirty → close.
4. Dirty → `showWConfirm(title: l.planDiscardTitle, message: <day or exercise message>, cancelLabel: l.commonKeepEditing, confirmLabel: l.commonDiscard, destructive: true)`. Only `true` closes; `false` and `null` (barrier or back) mean keep editing. If the open editor changed or closed while the dialog was up, it returns false and does nothing.

Wiring:
- The header `_BackButton`, including its `Semantics.onTap`, calls `requestClose`.
- `handleBack()` returns true synchronously and runs `requestClose()` unawaited.
- Save and Delete close **only their own editor**: `onBack` becomes a closure bound to the route that checks `identical(_editor, route)`. A late save can no longer close a different editor opened during the fade.

**Exit from Today:**
- `decideBack` gains `required bool planEditsAtRisk`. On tab 0 with edits at risk it returns a new `BackAction.confirmExit`; otherwise it behaves as today, and `tabHandled` still wins.
- AppShell's `onPopInvokedWithResult` stays synchronous. For `confirmExit` it runs three steps, unawaited:
  1. switch to Plan (`_index = 3`);
  2. `await requestClose()`, then return if `!mounted`;
  3. if the editor closed (Discard), call `SystemNavigator.pop()`, completing the exit the user asked for. On Keep editing, stay in the editor.
- `planEditsAtRisk` is `_planKey.currentState?.hasUnsavedEdits ?? false`. The hidden tab's typed values are already committed, because the tab lost focus.

**Known and accepted:** a back press during the exercise editor's reference lookup, before its delete confirm, may stack the discard prompt under the delete confirm. Either outcome is safe.

**Strings (en/it/de/es):**

| key | en | it | de | es |
|---|---|---|---|---|
| planDiscardTitle | Discard changes? | Scartare le modifiche? | Änderungen verwerfen? | ¿Descartar los cambios? |
| planDiscardDayMessage | Your changes to this training day will be lost. | Le modifiche a questo giorno di allenamento andranno perse. | Deine Änderungen an diesem Trainingstag gehen verloren. | Se perderán los cambios de este día de entrenamiento. |
| planDiscardExerciseMessage | Your changes to this exercise will be lost. | Le modifiche a questo esercizio andranno perse. | Deine Änderungen an dieser Übung gehen verloren. | Se perderán los cambios de este ejercicio. |
| commonKeepEditing | Keep editing | Continua a modificare | Weiter bearbeiten | Seguir editando |

`commonDiscard` already exists.

## Testing

Every behaviour change gets a failing test first. A behaviour-neutral refactor gets a regression guard instead, and is labelled as one. Commands:
- Run tests only as `timeout 900 make -C app test [TEST=<file>] > /tmp/claude-1000/<name>.log 2>&1; echo EXIT=$?`.
- Never run `make -C app fmt` or `dart format` on a directory.
- Run `make -C app get` after ARB **or `l10n.yaml`** changes. The generated l10n is gitignored, and `make -C app test` does not regenerate it.

**Pure tests:**
- `profileTrainingLine` and `fmtMonthYear` run under `setUpAll(initializeDateFormatting)`, as test/util/dates_test.dart does; uninitialised intl rejects even 'en'.
  - `profileTrainingLine`, in en/it/de/es: both parts; the singular; each part alone; neither → null; a bad date drops "since".
  - `fmtMonthYear`: real output, including de "Sept. 2026"; null, empty and garbage → null.
- `unit_format_test.dart`:
  - `fmtLoad` matches a frozen, verbatim copy of today's `fmtDisplay` body kept in the test (not `UnitService.fmtDisplay`, which delegates to it), over kg and lb values i/100 for i in 0..50000.
  - `fmtLoad` goldens: 80 → '80', 72.5 → '72.5', 60.25 → '60.25', 60.10 → '60.1', 1.005 → '1', 1.125 → '1.13', 99.999 → '100', lb 220.46 → '220', 220.5 → '221', 1102.3 → '1102' (never grouped).
  - `fmtVolume`, called with kg inputs: (0, kg) '0kg'; (850, kg) '850kg'; (999.6, kg) '1t'; (1000, kg) '1t'; (1482.5, kg) '1.5t'; (5879, kg) '5.9t'; (1482.5, lb) '3.3k lb'; (5879, lb) '13k lb'; (453.4, lb) '1k lb'; half-cases (1150, kg) '1.2t' and (9950, kg) '10t'.
  - `fmtBodyweight` and `fmtCount` cases (moved from format_test).
  - `roundLoad` / `roundBodyweight` agree with their formatters at half-cases.
- Rounded-first deltas. These pairs are chosen so that raw subtraction plus the `changeLabel` guard fails (b) and (c):
  - (a) 99.75 → 100 kg in lb: both display 220 and read "same", neutral colour; raw would read "+1".
  - (b) 100 → 100.1 kg in lb: 220 → 221 reads "+1", accent; raw would read "same".
  - (c) top set 99.75 kg ×6 → 100 kg ×8 in lb: the weights display the same, so it reads "+2 reps", accent.
  - (d) bodyweight 67.04 → 67.06 kg reads "+0.1", with the good tone on bulk; 67.06 → 67.14 kg reads "same", neutral.
- The edit snapshots:
  - untouched equals initial; reorder-then-back equals initial;
  - remove + re-add is a change;
  - whitespace is ignored;
  - rest 0 equals default;
  - lb: the `ExerciseDraft` built from `toKg(clampRound2(clampRound2(fromKg(20, lb) + s) - s), lb)` snapshots equal to the 20 kg draft;
  - a snapshot taken, then a `SlotDraft` mutated in place, then a second snapshot: the two differ (the snapshot holds values, not references).
- `decideBack`: the three existing cases in `test/shell/back_dispatch_test.dart` pass `planEditsAtRisk: false`. New cases: tab 0 + at risk → `confirmExit`; tabs 1–3 + at risk → unchanged (`goHome`); tab 3 with `tabHandled` → `none`.
- The endonym table's codes, *as a set*, equal `AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet()`, and `supportedLocales.first == Locale('en')`.
- `basicLocaleListResolution([Locale('fr', 'FR')], AppLocalizations.supportedLocales) == Locale('en')`. It fails on main, where it is de.

**Data (real DB), in `test/data/stats_repository_integration_test.dart`:** `watchTrainingSummary`:
- (a) one `is_template = 1` day, its owned copy (`is_template = 0`) and one day with NULL `is_template` give `dayCount == 2`;
- (b) an empty DB emits `(firstSessionDate: null, dayCount: 0)`;
- (c) sessions inserted out of date order give the earliest date;
- (d) `stream.first` twice on one stream instance works;
- (e) after the first emission, inserting only a `day_templates` row emits `dayCount + 1`, which proves `triggerOnTables`.

**Widget tests over the real DB (`test/support/screen_harness.dart`):** use `settleReal` / `settleUntilFound`, never `pumpAndSettle`. End every test with `harness.unmount(tester)` and `tearDown(harness.close)`.

*Profile line:*
- Fixed-date seeds (e.g. `DateTime(2026, 3, 14)`) render "Training since Mar 2026 · 2-day split" in en and de.
- A fresh DB: `find.byKey(const Key('profile-training-line'))` finds nothing, and the old placeholder text is found nowhere.
- Days-only and sessions-only cases.
- Deleting the earliest session updates the month.
- Tapping the name hides the line; saving shows it again within a few `settleReal` ticks.

*lb screens* (`prefs: {'unit': 'lb'}`, seedLong):
- Summary shows "3.3k lb" and no "3.3t".
- History shows "13k lb" and no "13.0k".
- Progress mounted with `ProgressScreen(initialTarget: 'ex3')`:
  - wait with `settleUntilFound(tester, find.text('226'), …)` (Current and Best are plain Text);
  - then assert: the 12-week tile reads `+17` (main: '+16.5'); a session-log row reads `220lb × 5`; `find.textContaining('220.5')` finds nothing.
  - Session-log rows are `Text.rich`, so plain `find.text` only matches their full plain text.
  - Optionally, the volume metric's middle delta reads `+27` (1102 − 1075), where raw subtraction gives '+28'.
- Today and the bodyweight view show the same bodyweight string ("181.7").
- kg: a custom seed whose latest bodyweight is 82.37 kg makes Today and the bodyweight view both read "82.4" (main: "82.37" vs "82.4").
- The kg counterparts "1.5t" / "5.9t" are regression pins; they already pass on main.

*Fonts:*
- Setup: `setUpAll(preloadAppFonts)`. The theme checks go in their own file (or come first and are seen failing on main), so their red is a font fallback and not a compile error from helpers that don't exist yet.
- Proportional-width checks (`'iiii'` < `'MMMM'`/2) on a default `Text` inside a `Scaffold` body under `buildTheme`, a `FilledButton` label, and all 15 `textTheme` slots. It must be a Scaffold body: with no Material ancestor, a Text inherits MaterialApp's 48px error style and fails even after the fix. On main these measure equal (FlutterTest squares).
- Chart helpers: ten zeros measure 0.6 em × size × 10, ≈54 for `chartLabelStyle` (9px) and ≈72 for `chartChipStyle` (12px).
- In `tokens_test.dart`, for Brightness.dark and .light: `buildTheme(b, accent).textTheme.bodyMedium!.color == tokens.text`, which a no-argument call fails (0xFF1D1B20 in both). For all 15 slots, (fontSize, fontWeight) equals today's table (displayLarge 57/w400 … labelLarge 14/w600 … labelSmall 11/w500), and `fontFamily` starts with `HankenGrotesk_`, which main's plain 'HankenGrotesk' fails.
- The no-network test calls `buildTheme` before `pendingFonts`, so an unbundled theme weight fails.
- A source guard fails on any match of `RegExp(r'\bfontFamily\s*:')` in `app/lib/**/*.dart`, with no exemption. After the fix no file names a family. `fontFamilyFallback:` doesn't match, and doc comments must not quote the pattern.

*RIR:*
- Selection is observed through the chip's `BoxDecoration` colour (`tokens.accent`) and digit colour (`tokens.accentInk`). The chips have no semantics yet.
- Font-free, in `rir_picker_test`:
  - it renders exactly `rir-$rirMin`…`rir-$rirMax`;
  - `rirMax` selects and reports; 7 and null select nothing;
  - `SizedBox(width: 288)` → one row with 48dp slots, `SizedBox(width: 287)` → two rows of three;
  - `height` defaults to 48.
- Every file that asserts a row count or a chip width uses `setUpAll(preloadAppFonts)`: `live_set_card_test` and `set_editor_sheet_test` gain it. Under the FlutterTest font, the live card at 354dp measures 278.6dp and gives two rows.
- Every chip slot is ≥48×48 at the real host widths (SetLine and LiveSetCard at 262 and 354dp; History in its sheet at 320 and 412dp), at 1.0× and 2.0×, with the one- or two-row result listed in the design.
- `set_line_test`:
  - the ≥48dp test extends to every chip and to 2.0×;
  - with the strip open at 262dp, a tap at the midpoint between rir-0's bottom and rir-3's top leaves the row's `onTap` count at 0 and fires no `onRir`;
  - a done working set with a null RIR shows no "RIR" text.
- `set_editor_sheet_test` (local `FakeSessionRepository`):
  - open a set with RIR 1, tap `rir-5`, pump past the 400ms debounce → `updateCalls.last.rir == 5`. It fails on main, which has no rir-5.
  - Regression guard: a set stored at RIR 7 survives a weight edit with `updateCalls.last.rir == 7`, and no chip is selected.
- Regression guards for the behaviour-neutral constant refactor:
  - `day_editor_slot_row_test` ('RIR steppers stay within rirMin to rirMax') and `rir_range_test` use `rirMin` / `rirMax` instead of the literals 0 and 5;
  - `exercise_editor_rir_test` gains a bounds case: 7 taps on RIR HIGH + → `rirMax`, then 3 taps on RIR LOW − → `rirMin`.

*Language:* split by what each test exercises.
- **Shared sheet**, in `w_action_sheet_test`, under a light `buildTheme(Brightness.light, accents[3])` MaterialApp where colour matters (in the dark theme `accentText == accent`):
  - the check is `accentText`;
  - every row is ≥56dp, including two-line rows at 320dp and 2.0×;
  - "Predeterminado del sistema" is not ellipsized (`RenderFitLabel.ellipsized == false`) at 320dp and 2.0×;
  - six rows at `setPhone(width: 320, height: 640, textScale: 2.0)` in de raise no exception (fails on main with an overflow), and `ensureVisible` plus a tap on `sheet-action-5` returns its value.
- **Semantics**, after `tester.ensureSemantics()`. For each row i, `final d = tester.getSemantics(find.byKey(ValueKey('sheet-action-$i'))).getSemanticsData();`, asserting on that one node:
  - `d.label` is the row's text;
  - `d.flagsCollection.isButton`, and `d.hasAction(SemanticsAction.tap)`;
  - `d.locale == Locale(code)` for endonym rows and `null` for the system row;
  - `d.flagsCollection.isSelected == Tristate.isTrue` only on the current row, and `Tristate.none` on every other.

  Don't use the widget-ancestor `_isSelected` helper or a `find.text` semantics lookup: both pass against the broken split-node tree.
- **`showLanguageSheet`**, under `wrapL10n`:
  - in each UI locale all four endonyms show, and "Tedesco", "Englisch" and "Inglés" are absent;
  - rows `sheet-action-0..4` read System default (localized), English, Italiano, Deutsch, Español;
  - the current row is marked, and with a null override the system row is marked;
  - tapping returns the code or `'system'`; the barrier returns null.
- **Goal sheet:** exactly one `WIcons.check`, trailing on the current goal's row; that row's node is selected; every row shows `WIcons.target`.
- **Profile integration**, in the `it` UI (`harness.wrap(…, locale: const Locale('it'))`): pick Deutsch → `harness.settings.localeOverride == 'de'`, the Language row's sub-label reads "Deutsch", and "Tedesco" is found nowhere. In en this would already pass on main, because the en ARB happens to hold endonyms.

*Discard guard* (AppShell over the real DB):
- **DayEditor** on seedLong's d1 (4 slots):
  - (a) untouched → `handlePopRoute` closes with no dialog;
  - (b) expand a slot and tap `stepper-inc` on its working-sets stepper → `handlePopRoute` prompts. This catches a baseline that aliases the live SlotDrafts.
  - (c) + then − on that same working-sets stepper → no prompt. Working sets have no side effects: rep low bumps rep high, and an unset RIR is accepted as dirty.
  - (d) a half-typed value in a DaySlotRow stepper (focus still in the field) → back prompts;
  - (e) Keep editing keeps the edit; Discard closes, and reopening shows the DB value;
  - (f) Save closes with no dialog;
  - (g) edit → another tab → back to Plan: the edit is intact and no dialog appeared. Assertions made while Plan is hidden use `skipOffstage: false`.
- **ExerciseEditor:**
  - the header chevron behaves the same as back; tap it via `find.bySemanticsLabel(l.commonBack)`, because `WIcons.chevron` also appears in slot rows;
  - an lb exercise +/− round trip → no prompt.
- **Exit from Today with a dirty editor:** mock `SystemChannels.platform` and record calls whose method is `SystemNavigator.pop`; the channel also carries haptics and SystemChrome calls. Clear the mock in `addTearDown`. The shell switches to Plan and shows the dialog, and pop is not called. Keep editing stays; Discard calls pop.
- Probe results: DayEditor mounts in AppShell over ScreenHarness; a slot expands by tapping its exercise name; `handlePopRoute` reaches the root `PopScope`.

**Layout sweep (`test/layout/`):**
- lb cases for Summary and History.
- Live-screen states with the post-log RIR strip open (`logLiveSet`) and the live card's RIR row (`focusSet` on a logged set). Today the sweep never renders a `RirPicker`.
- The Profile sweep waits for `find.byKey(const Key('profile-training-line'))` with `settleUntilFound` before checking. Never match on ' · ': the sync status and the local-first hint contain it too. Plus one es case at 320dp and 2.0×.

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
- The app-vs-notification language mismatch for a device list with a supported secondary language.

## Release

Recommend **0.18.0**. Everything here is a correctness fix, but it visibly changes behaviour on several screens: a new prompt, a new sheet, RIR 0–5, fonts on five surfaces and different lb numbers. Before tagging, bump `app/pubspec.yaml` to `0.18.0+N`.
