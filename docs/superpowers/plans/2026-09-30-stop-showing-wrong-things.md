# Stop Showing Wrong Things Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every number, name and label Reps shows is true and consistent, in kg and lb and in all four languages, and Plan edits are never lost without a word.

**Architecture:** Client-only display fixes in the Flutter app; no schema, server or sync changes.
- **Profile line:** computed from one light watch in `StatsRepository`.
- **Fonts:** Material text and the chart labels go through the google_fonts helpers already used everywhere else.
- **Formatters:** one per displayed quantity, in a new `units/unit_format.dart`. Deltas are taken between the rounded values the screen shows.
- **RIR:** `RirPicker` covers `rirMin..rirMax` and wraps to 3×2 when six chips can't each get 48dp.
- **Action sheets:** the shared sheet gains a selected state and a per-row semantics locale. That serves the endonym language sheet and the goal picker.
- **Plan editors:** each gets a per-open `EditorGuard`. PlanScreen asks before back, or exit from Today, would discard its edits.

**Tech Stack:** Flutter 3.44 via fvm (`make -C app …`), Dart, provider, PowerSync (sqlite_async), google_fonts 6.3.3 (bundled faces), intl, gen_l10n ARBs (en/it/de/es), flutter_test with the real-DB `test/support/screen_harness.dart`.

**Spec:** `docs/superpowers/specs/2026-09-30-stop-showing-wrong-things-design.md`. Read it with this plan: the plan argues from it.

## Global Constraints

**Commands**
- Every command runs from the repo root with explicit paths. Never `cd`.
- Tests run ONLY as `timeout 900 make -C app test [TEST=<file or "f1 f2">] > /tmp/claude-1000/<name>.log 2>&1; echo EXIT=$?`, then grep the log. A bare run gets auto-backgrounded and hangs subagents.
- NEVER run `make -C app fmt`, `make -C app format` or `dart format` on a directory: it rewrites about 190 unrelated files.
- Run `make -C app get` after any ARB or `app/l10n.yaml` change. The generated `app/lib/l10n/app_localizations*.dart` is gitignored, and `make -C app test` does not regenerate it.
- `make -C app analyze` must end at "No issues found!". Grep its log with `"issues? found"`: `info` also matches pub's "for more information" line.

**Commits**
- Conventional Commits, subject line only, no body, no trailers. Strip any harness `Claude-Session:` / `Co-Authored-By:` lines.
- Never reference plan or task numbers in code, comments, test names or commit messages. Use descriptive language.

**Code rules**
- Treat the repo as public: no secrets.
- Colours: `tokens.accentText` for accent text, icons and thin marks; `tokens.accent` for fills only.
- Confirm dialogs: `showWConfirm` / `showWDialog` only, never `AlertDialog`.
- Never create a `db.watch()` / `repo.watchX()` stream inside `build()` or a helper it calls.
- Parse DB data with `tryParse`, never `parse`.
- Weight steppers: the session and history steppers keep `parseDisplay`. The exercise-editor start weight is held in DISPLAY units and must NOT gain `parseDisplay`.
- The set-weight display rule (`UnitService.fmtDisplay` / `fmtWt`: kg up to 2 dp trimmed, lb whole) must stay byte-identical. The ruler's echo detection and the stepper's untouched-seed check compare those strings.
- Storage strings stay dot-decimal `toStringAsFixed(2)`. No formatter output may ever seed an edit field with a grouping separator.

**Real-screen tests**
- Use `test/support/screen_harness.dart` (`ScreenHarness().open/wrap/unmount/close`, `settleReal`, `settleUntilFound`).
- Never `pumpAndSettle` over the harness.
- End each test with `await harness.unmount(tester)`, with `tearDown(harness.close)`.
- The layout sweep in `app/test/layout/` must stay green.

## Review Focus

These inputs are implied by the spec but easy to miss. Each is pinned by a test in the task that owns the code:

1. **A fast double back swipe.** Two back events queue while an editor holds edits. Expect exactly one discard dialog, never two stacked. Pinned in the leaving-asks task by "two back presses queued together ask once" and "a close requested while one is asking is refused".
2. **An Android predictive back gesture** (`startBackGesture` then `commitBackGesture`) on a changed editor. Expect the same discard dialog as a back press. Pinned in the leaving-asks task by "a predictive back gesture asks before discarding".
3. **Switching the unit to lb in Profile** while an untouched exercise editor sits on the hidden Plan tab. Going back to Plan and pressing back closes it silently. Pinned in the unsaved-edits task ("an untouched exercise stays clean when the unit switches") and the leaving-asks task ("switching to lb behind an untouched editor does not ask").
4. **Changing only the day's name**, a text field rather than a stepper, then pressing back. Expect the prompt. Pinned in the leaving-asks task by "an edited day name asks before back discards it".
5. **A fresh install, or four idle weeks.** History's volume tile reads `0kg`, matching an empty session, not `0.0t`. Pinned in the volume/bodyweight task by "an empty four weeks reads 0kg, like an empty session".

## Execution notes

- **Order.** Tasks run in order. Several files are touched by more than one task, and each later task anchors its edits on code the earlier ones leave in place:
  - `profile_screen.dart`, by the volume/bodyweight, language and Profile-line tasks;
  - the four ARBs, by the language, Profile-line and leaving-asks tasks;
  - `exercise_editor.dart` and `day_editor.dart`, by the volume/bodyweight, RIR and unsaved-edits tasks;
  - `line_chart.dart`, by the chart-labels and Progress tasks.
- **Test counts.** Each area was prototyped red, then green, on main with only its own tasks applied, so full-suite pass counts quoted in a step (`+902`, `+946`, …) are from that run. Run in order, the totals differ. What a step requires is `EXIT=0` and `All tests passed!`. The targeted runs' counts hold, except where a step says otherwise.
- **Where the code differs from the spec's wording:**
  - Progress's `_fmtVal` / `_roundVal` live in `_LiftView`, the class that holds `_fmtVal` on main. The spec calls it `_ProgressContent`.
  - The Profile-line data test (e) pins the days-only re-emit. It can't prove `triggerOnTables` is present, because PowerSync also infers both tables. The parameter stays, as the spec requires.
  - The language rows have no leading icon.
  - "Two back presses queued together" passes even without the re-entrancy flag, because the pushed dialog absorbs the second pop. The flag gets its own red and green through a direct double `requestClose()`.
- **Whole-branch review.** After Task 13, before device checks: a fresh reviewer looks at `git diff main...HEAD` against the spec.

---


### Task 1: Theme text resolves to the bundled Hanken Grotesk

**Files:**
- Create: `app/test/support/text_theme_slots.dart` (test helper)
- Modify: `app/lib/theme/typography.dart`. The change covers the `WorkoutType.hankenTextTheme` getter and its doc comment, adds a private `_hankenSizes`, and ends at the class's closing brace.
- Modify: `app/lib/theme/app_theme.dart`. Only the doc comment on `buildTheme` changes: the line that names `[_buildTextTheme]`.
- Test: `app/test/theme/theme_fonts_test.dart` (new)
- Test: `app/test/theme/tokens_test.dart` (whole file replaced)
- Test: `app/test/theme/bundled_fonts_test.dart`. The imports change, and so does the body of `'every face the app draws loads from the bundle, with no network'`.

**Interfaces:**
- Consumes: nothing new. It uses:
  - `GoogleFonts.hankenGroteskTextTheme([TextTheme?])` from google_fonts 6.3.3;
  - the existing `preloadAppFonts()` in `app/test/support/app_fonts.dart`;
  - `accents` from `app/lib/theme/tokens.dart`.
- Produces:
  - `static TextTheme get WorkoutType.hankenTextTheme`, with the same signature as before. Each slot now names a per-weight family (`HankenGrotesk_regular`, `HankenGrotesk_500` or `HankenGrotesk_600`) with `fontFamilyFallback: ['HankenGrotesk']`. Sizes and weights don't change, and colours stay null.
  - `static const TextTheme _hankenSizes`, private to `WorkoutType`.
  - A test helper, `Map<String, TextStyle?> textThemeSlots(TextTheme t)`, in `app/test/support/text_theme_slots.dart`.
  - After this task, `app/lib/theme/typography.dart` has no `fontFamily:` literal. The source guard in the chart-labels task depends on that.

- [ ] **Step 1: Write the failing tests**

Create `app/test/support/text_theme_slots.dart`:

```dart
import 'package:flutter/material.dart';

/// The fifteen Material 3 [TextTheme] slots by name, so a test can check
/// every style the theme hands to Material widgets.
Map<String, TextStyle?> textThemeSlots(TextTheme t) => {
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };
```

Create `app/test/theme/theme_fonts_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

import '../support/app_fonts.dart';
import '../support/text_theme_slots.dart';

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  setUpAll(preloadAppFonts);

  // Hanken Grotesk is proportional: "i" is far narrower than "M". A theme
  // family that never loaded falls back to the test font, which draws both
  // as the same square.
  Matcher proportionalTo(double mmmm) => lessThan(mmmm / 2);

  testWidgets('a Text with no style draws in Hanken Grotesk', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      home: const Scaffold(
        body: Column(children: [Text('iiii'), Text('MMMM')]),
      ),
    ));
    expect(tester.getSize(find.text('iiii')).width,
        proportionalTo(tester.getSize(find.text('MMMM')).width));
  });

  testWidgets('a FilledButton label draws in Hanken Grotesk', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      home: Scaffold(
        body: Column(children: [
          FilledButton(onPressed: () {}, child: const Text('iiii')),
          FilledButton(onPressed: () {}, child: const Text('MMMM')),
        ]),
      ),
    ));
    expect(tester.getSize(find.text('iiii')).width,
        proportionalTo(tester.getSize(find.text('MMMM')).width));
  });

  test('every text theme slot draws in Hanken Grotesk', () {
    for (final b in Brightness.values) {
      final slots = textThemeSlots(buildTheme(b, accents[0]).textTheme);
      for (final MapEntry(key: name, value: style) in slots.entries) {
        expect(_width('iiii', style!), proportionalTo(_width('MMMM', style)),
            reason: '${b.name} $name');
      }
    }
  });
}
```

Replace `app/test/theme/tokens_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

import '../support/text_theme_slots.dart';

/// The theme's size and weight per text slot.
const _hankenScale = <String, (double, FontWeight)>{
  'displayLarge': (57, FontWeight.w400),
  'displayMedium': (45, FontWeight.w400),
  'displaySmall': (36, FontWeight.w400),
  'headlineLarge': (32, FontWeight.w600),
  'headlineMedium': (28, FontWeight.w600),
  'headlineSmall': (24, FontWeight.w600),
  'titleLarge': (22, FontWeight.w600),
  'titleMedium': (16, FontWeight.w500),
  'titleSmall': (14, FontWeight.w500),
  'bodyLarge': (16, FontWeight.w400),
  'bodyMedium': (14, FontWeight.w400),
  'bodySmall': (12, FontWeight.w400),
  'labelLarge': (14, FontWeight.w600),
  'labelMedium': (12, FontWeight.w500),
  'labelSmall': (11, FontWeight.w500),
};

void main() {
  // buildTheme loads its faces through google_fonts, which reads the asset
  // manifest through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark + light tokens resolve; accent applies', () {
    final dark = buildTheme(Brightness.dark, const Color(0xFFc2f53a));
    final light = buildTheme(Brightness.light, const Color(0xFF5ce6a4));
    final d = dark.extension<WorkoutTokens>()!;
    final l = light.extension<WorkoutTokens>()!;
    expect(d.bg, const Color(0xFF0b0b0c));
    expect(l.bg, const Color(0xFFf3f2ec));
    expect(d.accent, const Color(0xFFc2f53a));
    expect(l.accent, const Color(0xFF5ce6a4));
    expect(d.accentInk, const Color(0xFF0b0c08)); // constant in both modes
  });

  for (final b in Brightness.values) {
    test('${b.name} theme text keeps the token colour and the Hanken scale',
        () {
      final theme = buildTheme(b, accents[0]);
      final tokens = theme.extension<WorkoutTokens>()!;
      expect(theme.textTheme.bodyMedium!.color, tokens.text);
      final slots = textThemeSlots(theme.textTheme);
      for (final MapEntry(key: name, value: (size, weight))
          in _hankenScale.entries) {
        expect(slots[name]!.fontSize, size, reason: name);
        expect(slots[name]!.fontWeight, weight, reason: name);
        // google_fonts registers one family per weight (HankenGrotesk_600).
        expect(slots[name]!.fontFamily, startsWith('HankenGrotesk_'),
            reason: name);
      }
    });
  }
}
```

In `app/test/theme/bundled_fonts_test.dart`, replace the imports:

```dart
// old
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:workout_tracker/theme/typography.dart';
```

```dart
// new
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/theme/typography.dart';
```

In the test `'every face the app draws loads from the bundle, with no network'`, call `buildTheme` before the fonts are awaited:

```dart
// old
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);
    // A face missing from assets/google_fonts/ throws here instead of
    // falling back to a fetch.
    await preloadAppFonts();
```

```dart
// new
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);
    // buildTheme asks google_fonts for the theme's own text weights.
    for (final b in Brightness.values) {
      buildTheme(b, accents[0]);
    }
    // A face missing from assets/google_fonts/ throws here instead of
    // falling back to a fetch.
    await preloadAppFonts();
```

- [ ] **Step 2: Run the tests to verify they fail**

**theme_fonts_test.dart**

Run: `timeout 900 make -C app test TEST=test/theme/theme_fonts_test.dart > /tmp/claude-1000/fonts-theme.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error|Expected|Actual|\[E\]" /tmp/claude-1000/fonts-theme.log | tail -12`

Expected: EXIT=2 and `+0 -3`. The theme's plain `'HankenGrotesk'` family is not registered, so it falls back to the FlutterTest font's squares:
```
Expected: a value less than <28.5>
  Actual: <57.0>
00:00 +0 -1: a Text with no style draws in Hanken Grotesk [E]
Expected: a value less than <28.200000762939453>
  Actual: <56.400001525878906>
00:00 +0 -2: a FilledButton label draws in Hanken Grotesk [E]
00:00 +0 -3: every text theme slot draws in Hanken Grotesk [E]
  Expected: a value less than <114.0>
    Actual: <228.0>
00:00 +0 -3: Some tests failed.
make: *** [Makefile:45: test] Error 1
```

**tokens_test.dart**

Run: `timeout 900 make -C app test TEST=test/theme/tokens_test.dart > /tmp/claude-1000/fonts-tokens.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error|Expected|Actual|\[E\]" /tmp/claude-1000/fonts-tokens.log | tail -8`

Expected: EXIT=2 and `+1 -2`. Both brightness tests fail on the family. The colour, size and weight checks already pass on main.
```
00:00 +1 -1: dark theme text keeps the token colour and the Hanken scale [E]
  Expected: a string starting with 'HankenGrotesk_'
    Actual: 'HankenGrotesk'
00:00 +1 -2: light theme text keeps the token colour and the Hanken scale [E]
  Expected: a string starting with 'HankenGrotesk_'
    Actual: 'HankenGrotesk'
00:00 +1 -2: Some tests failed.
make: *** [Makefile:45: test] Error 1
```

**bundled_fonts_test.dart**

Run: `timeout 900 make -C app test TEST=test/theme/bundled_fonts_test.dart > /tmp/claude-1000/fonts-bundled.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-bundled.log | tail -5`

Expected: EXIT=0 and `00:00 +2: All tests passed!`.

This test is a **regression guard**. On main, `buildTheme` makes no google_fonts request, so it can't find a face missing. Once the theme goes through google_fonts, a theme weight with no bundled file makes this test throw. For example, w300 throws `GoogleFonts.config.allowRuntimeFetching is false but font HankenGrotesk-Light was not found in the application assets`.

- [ ] **Step 3: Implement**

In `app/lib/theme/typography.dart`, replace lines 65–92 with the block below. Those lines run from the `hankenTextTheme` doc comment, through the getter, to the closing brace of `WorkoutType`. The old block ends with the getter's `  }` and then the class's `}`. The new block ends with `  );` and then the class's `}`.

```dart
// old
  /// A [TextTheme] with Hanken Grotesk as the declared font family.
  ///
  /// Uses the font family name directly rather than routing through
  /// [GoogleFonts.hankenGroteskTextTheme] so that no async font-file fetches
  /// are triggered when this getter is called (e.g. inside [buildTheme] during
  /// tests). The [WorkoutType.body], [display], and [mono] helpers use
  /// [GoogleFonts] at the widget level where async loading is fine.
  static TextTheme get hankenTextTheme {
    const family = 'HankenGrotesk';
    return const TextTheme(
      displayLarge: TextStyle(fontFamily: family, fontSize: 57, fontWeight: FontWeight.w400),
      displayMedium: TextStyle(fontFamily: family, fontSize: 45, fontWeight: FontWeight.w400),
      displaySmall: TextStyle(fontFamily: family, fontSize: 36, fontWeight: FontWeight.w400),
      headlineLarge: TextStyle(fontFamily: family, fontSize: 32, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontFamily: family, fontSize: 22, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontFamily: family, fontSize: 11, fontWeight: FontWeight.w500),
    );
  }
}
```

```dart
// new
  /// Material's text theme in Hanken Grotesk, for every widget that styles
  /// its text from the theme (onboarding, login, SnackBars, the date-range
  /// picker).
  ///
  /// google_fonts registers one family per weight (`HankenGrotesk_600`) and
  /// nothing registers the plain name, so the styles must come from
  /// [GoogleFonts.hankenGroteskTextTheme]. Always pass [_hankenSizes]: with
  /// no argument it starts from `ThemeData.light().textTheme`, which brings
  /// a dark text colour onto the dark theme and drops these weights. Colours
  /// stay null, so they come from `colorScheme.onSurface`.
  ///
  /// Because each family is one weight, `copyWith(fontWeight: …)` on these
  /// styles keeps the old face and synthesises the new weight; use [body]
  /// for another weight.
  static TextTheme get hankenTextTheme =>
      GoogleFonts.hankenGroteskTextTheme(_hankenSizes);

  static const _hankenSizes = TextTheme(
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
  );
}
```

In `app/lib/theme/app_theme.dart`, fix the stale doc line on `buildTheme`:

```dart
// old
/// Build a [ThemeData] with [WorkoutTokens] wired as a [ThemeExtension].
/// Typography is applied in [WorkoutType] and wired via [_buildTextTheme].
ThemeData buildTheme(Brightness brightness, Color accent) {
```

```dart
// new
/// Build a [ThemeData] with [WorkoutTokens] wired as a [ThemeExtension].
/// Material's text theme is [WorkoutType.hankenTextTheme].
ThemeData buildTheme(Brightness brightness, Color accent) {
```

- [ ] **Step 4: Run the tests to verify they pass**

**theme_fonts_test.dart**
- Run: `timeout 900 make -C app test TEST=test/theme/theme_fonts_test.dart > /tmp/claude-1000/fonts-theme.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-theme.log | tail -5`
- Expected: EXIT=0 and `00:00 +3: All tests passed!`

**tokens_test.dart**
- Run: `timeout 900 make -C app test TEST=test/theme/tokens_test.dart > /tmp/claude-1000/fonts-tokens.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-tokens.log | tail -5`
- Expected: EXIT=0 and `00:00 +3: All tests passed!`

**bundled_fonts_test.dart**
- Run: `timeout 900 make -C app test TEST=test/theme/bundled_fonts_test.dart > /tmp/claude-1000/fonts-bundled.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-bundled.log | tail -5`
- Expected: EXIT=0 and `00:00 +2: All tests passed!`

**Full suite.** Any test that builds the theme can be affected: every `wrapL10n` and `ScreenHarness` test, the layout sweep under `test/layout/`, and the onboarding and login tests.
- Run: `timeout 900 make -C app test > /tmp/claude-1000/fonts-full.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-full.log | tail -5`
- Expected: EXIT=0 and `+902: All tests passed!`. That is 897 on main plus this task's five new tests: three in theme_fonts_test, and tokens_test goes from 1 to 3.

- [ ] **Step 5: Analyze**

Run: `make -C app analyze > /tmp/claude-1000/fonts-analyze.log 2>&1; echo EXIT=$?`

Then: `tail -3 /tmp/claude-1000/fonts-analyze.log`

Expected: EXIT=0 and "No issues found!".

- [ ] **Step 6: Commit**

```
git add app/lib/theme/typography.dart app/lib/theme/app_theme.dart app/test/support/text_theme_slots.dart app/test/theme/theme_fonts_test.dart app/test/theme/tokens_test.dart app/test/theme/bundled_fonts_test.dart
git commit -m "fix(app): draw theme-styled text in the bundled Hanken Grotesk"
```

### Task 2: Chart labels use JetBrains Mono

**Files:**
- Modify: `app/lib/widgets/line_chart.dart`. Anchors:
  - the import block;
  - the new top-level `chartLabelStyle` / `chartChipStyle`, placed just above the `/// A progression line chart ported from \`ui.jsx\` \`LineChart\`.` doc of `class LineChart`;
  - the `_LineChartPainter` constructor;
  - in `_LineChartPainter.paint`:
    - the `// ── gridlines + left y labels` loop;
    - the `// ── month x-labels` block (`xLabelStyle`);
    - the value-chip `TextPainter` after `final label =`.
- Test: `app/test/theme/font_family_source_test.dart` (new)
- Test: `app/test/widgets/line_chart_fonts_test.dart` (new)

**Interfaces:**
- Consumes:
  - The Hanken Grotesk theme task above. `app/lib/theme/typography.dart` must no longer contain a `fontFamily:` literal, or the source guard stays red.
  - The existing `WorkoutType.mono({double size = 12, FontWeight weight = FontWeight.w400, Color? color, double? letterSpacing})`.
  - The existing `preloadAppFonts()`.
- Produces:
  - `TextStyle chartLabelStyle(Color color)`, top-level in `app/lib/widgets/line_chart.dart`. It returns `WorkoutType.mono(size: 9, color: color)`.
  - `TextStyle chartChipStyle(Color color)`, top-level in `app/lib/widgets/line_chart.dart`. It returns `WorkoutType.mono(size: 12, weight: FontWeight.w700, color: color)`.
  - `_LineChartPainter` passes `repaint: PaintingBinding.instance.systemFonts` to `super`.
  - The chip label line is unchanged: `'${fmtPlain(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}'`. The `../util/format.dart` import stays, because `fmtPlain` is still used.
  - `app/test/theme/font_family_source_test.dart`. Every later task must keep it green: no `fontFamily:` anywhere in `app/lib/**/*.dart`, doc comments included.
  - `app/test/widgets/line_chart_fonts_test.dart`, which has three points a later change must keep in mind:
    - Its `_pumpChart` helper builds `const LineChart(series: …, unit: 'kg')` in one place. A later change that adds a required `LineChart` parameter (the formatter's `formatValue`) must update that call.
    - Passing a top-level function tear-off such as `fmtBodyweight` keeps the call `const`.
    - `'the chart draws every label in JetBrains Mono'` pins the chip text `82.5kg ×5`: 9 glyphs × 0.6 em × 12px = 64.8. The formatter passed there must render 82.5 as `82.5`, as `fmtBodyweight` does, or the expected widths must be updated.

- [ ] **Step 1: Write the failing behaviour tests**

Create `app/test/theme/font_family_source_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // google_fonts registers one family per weight (`JetBrainsMono_700`) and
  // nothing registers a plain name like 'JetBrainsMono', so a style that
  // names a family itself silently draws in the platform font. Every style
  // goes through WorkoutType instead.
  test('no lib file names a font family', () {
    final pattern = RegExp(r'\bfontFamily\s*:');
    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        hits.add('${file.path}:$line');
      }
    }
    expect(hits, isEmpty);
  });
}
```

Create `app/test/widgets/line_chart_fonts_test.dart` with the two painter tests. The helper width tests come in Step 3. That way both reds here are behavioural: one is a font fallback and the other a missing repaint, with no compile error.

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/line_chart.dart';

import '../support/app_fonts.dart';

/// Pumps a two-point chart under reduced motion and finds its CustomPaint.
/// Under reduced motion the chart paints exactly once, at full progress, so
/// the value chip is drawn too.
Future<Finder> _pumpChart(WidgetTester tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures.allOn;
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: LineChart(
        series: [
          (date: '2026-06-01', value: 80, reps: 5, isPr: false),
          (date: '2026-06-08', value: 82.5, reps: 5, isPr: true),
        ],
        unit: 'kg',
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return find.descendant(
      of: find.byType(LineChart), matching: find.byType(CustomPaint));
}

void main() {
  setUpAll(preloadAppFonts);

  testWidgets('the chart draws every label in JetBrains Mono', (tester) async {
    final chart = await _pumpChart(tester);
    final widths = <double>[];
    expect(
      chart,
      paints
        ..everything((method, args) {
          if (method == #drawParagraph) {
            widths.add((args[0] as ui.Paragraph).longestLine);
          }
          return true;
        }),
    );
    // Four y labels ("78" to "84") and "Jun" at 9px, then "82.5kg ×5" at
    // 12px, each 0.6 em per glyph. The test font draws 18, 27 and 108.
    expect(widths, [
      for (final w in [10.8, 10.8, 10.8, 10.8, 16.2, 64.8]) closeTo(w, 0.1),
    ]);
  });

  testWidgets('the chart repaints when a font finishes loading',
      (tester) async {
    // A face that arrives after the chart's one paint is only drawn if a
    // font change repaints it.
    final chart =
        tester.renderObject<RenderCustomPaint>(await _pumpChart(tester));
    expect(chart.debugNeedsPaint, isFalse);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec
          .encodeMessage(<String, dynamic>{'type': 'fontsChange'}),
      (_) {},
    );

    expect(chart.debugNeedsPaint, isTrue);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

**font_family_source_test.dart**

Run: `timeout 900 make -C app test TEST=test/theme/font_family_source_test.dart > /tmp/claude-1000/fonts-guard.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error|Expected|Actual|lib/" /tmp/claude-1000/fonts-guard.log | tail -8`

Expected: EXIT=2. After the theme task, only the chart's three literals remain:
```
  Expected: empty
    Actual: [
              'lib/widgets/line_chart.dart:299',
              'lib/widgets/line_chart.dart:377',
              'lib/widgets/line_chart.dart:428'
00:00 +0 -1: Some tests failed.
make: *** [Makefile:45: test] Error 1
```

**line_chart_fonts_test.dart**

Run: `timeout 900 make -C app test TEST=test/widgets/line_chart_fonts_test.dart > /tmp/claude-1000/fonts-chart.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error|Expected|Actual|Which|\[E\]" /tmp/claude-1000/fonts-chart.log | tail -9`

Expected: EXIT=2 and `+0 -2`. The labels fall back to the test font, and a font change doesn't repaint:
```
Expected: [
  Actual: [18.0, 18.0, 18.0, 18.0, 27.0, 108.0]
   Which: at location [0] is <18.0> which  differs by <7.199999999999999>
00:00 +0 -1: the chart draws every label in JetBrains Mono [E]
Expected: true
  Actual: <false>
00:00 +0 -2: the chart repaints when a font finishes loading [E]
00:00 +0 -2: Some tests failed.
make: *** [Makefile:45: test] Error 1
```

- [ ] **Step 3: Write the failing helper tests**

In `app/test/widgets/line_chart_fonts_test.dart`, add `_width` above the `_pumpChart` doc comment:

```dart
// old
/// Pumps a two-point chart under reduced motion and finds its CustomPaint.
```

```dart
// new
double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Pumps a two-point chart under reduced motion and finds its CustomPaint.
```

Then add the two helper tests at the top of `main`, after `setUpAll`:

```dart
// old
  setUpAll(preloadAppFonts);

  testWidgets('the chart draws every label in JetBrains Mono', (tester) async {
```

```dart
// new
  setUpAll(preloadAppFonts);

  // JetBrains Mono advances every glyph 0.6 em; a family that never loaded
  // falls back to the test font's 1 em squares.
  test('axis labels draw in JetBrains Mono', () {
    expect(_width('0000000000', chartLabelStyle(Colors.white)),
        closeTo(54, 1));
  });

  test('the value chip draws in JetBrains Mono', () {
    expect(_width('0000000000', chartChipStyle(Colors.white)),
        closeTo(72, 1));
  });

  testWidgets('the chart draws every label in JetBrains Mono', (tester) async {
```

- [ ] **Step 4: Run it to verify it fails**

Run: `timeout 900 make -C app test TEST=test/widgets/line_chart_fonts_test.dart > /tmp/claude-1000/fonts-chart.log 2>&1; echo EXIT=$?`

Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-chart.log | tail -5`

Expected: EXIT=2, with a compile error because the helpers don't exist yet:
```
test/widgets/line_chart_fonts_test.dart:55:33: Error: Method not found: 'chartChipStyle'.
  Compilation failed for testPath=…/app/test/widgets/line_chart_fonts_test.dart: test/widgets/line_chart_fonts_test.dart:50:33: Error: Method not found: 'chartLabelStyle'.
  test/widgets/line_chart_fonts_test.dart:55:33: Error: Method not found: 'chartChipStyle'.
00:00 +0 -1: Some tests failed.
make: *** [Makefile:45: test] Error 1
```

- [ ] **Step 5: Implement**

In `app/lib/widgets/line_chart.dart`, add the typography import:

```dart
// old
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../util/format.dart';
```

```dart
// new
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';
import '../util/format.dart';
```

Add the two helpers just above the `LineChart` class doc:

```dart
// old
/// A progression line chart ported from `ui.jsx` `LineChart`.
```

```dart
// new
/// The chart's axis labels: the y gridline values and the month names.
TextStyle chartLabelStyle(Color color) =>
    WorkoutType.mono(size: 9, color: color);

/// The value chip beside the chart's last point.
TextStyle chartChipStyle(Color color) =>
    WorkoutType.mono(size: 12, weight: FontWeight.w700, color: color);

/// A progression line chart ported from `ui.jsx` `LineChart`.
```

Make the painter repaint when the system fonts change:

```dart
// old
class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.unit,
    required this.showReps,
    required this.accent,
    required this.bg,
    required this.faint,
    required this.text,
    required this.localeName,
    this.progress = 1.0,
  });
```

```dart
// new
class _LineChartPainter extends CustomPainter {
  // Repaints when a font finishes loading, so labels first drawn in a
  // fallback face are redrawn in JetBrains Mono. Under reduced motion the
  // chart paints once and nothing else would repaint it.
  _LineChartPainter({
    required this.series,
    required this.unit,
    required this.showReps,
    required this.accent,
    required this.bg,
    required this.faint,
    required this.text,
    required this.localeName,
    this.progress = 1.0,
  }) : super(repaint: PaintingBinding.instance.systemFonts);
```

In `paint`, build the label style once, before the gridline loop:

```dart
// old
    double yAt(double v) => _padT + ih - ((v - lo) / (hi - lo)) * ih;

    // ── gridlines + left y labels, on round values ───────────────────────────
```

```dart
// new
    double yAt(double v) => _padT + ih - ((v - lo) / (hi - lo)) * ih;

    // One style for every axis label, built once per paint rather than per
    // gridline: each call goes through google_fonts.
    final labelStyle = chartLabelStyle(faint);

    // ── gridlines + left y labels, on round values ───────────────────────────
```

The y labels:

```dart
// old
        rightAlign: true,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 9,
          color: faint,
        ),
      );
```

```dart
// new
        rightAlign: true,
        style: labelStyle,
      );
```

The month labels. Delete `xLabelStyle`:

```dart
// old
    // don't stack their labels), skipping any that would crowd a neighbour.
    final xLabelStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 9,
      color: faint,
    );
    for (final m in monthLabelPositions([for (final s in series) s.date])) {
```

```dart
// new
    // don't stack their labels), skipping any that would crowd a neighbour.
    for (final m in monthLabelPositions([for (final s in series) s.date])) {
```

```dart
// old
        centreAlign: true,
        style: xLabelStyle,
      );
```

```dart
// new
        centreAlign: true,
        style: labelStyle,
      );
```

The value chip. The `final label = …` line above it stays exactly as it is:

```dart
// old
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
```

```dart
// new
    final tp = TextPainter(
      text: TextSpan(text: label, style: chartChipStyle(text)),
      textDirection: TextDirection.ltr,
    )..layout();
```

- [ ] **Step 6: Run the tests to verify they pass**

**line_chart_fonts_test.dart**
- Run: `timeout 900 make -C app test TEST=test/widgets/line_chart_fonts_test.dart > /tmp/claude-1000/fonts-chart.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-chart.log | tail -5`
- Expected: EXIT=0 and `00:00 +4: All tests passed!`

**font_family_source_test.dart**
- Run: `timeout 900 make -C app test TEST=test/theme/font_family_source_test.dart > /tmp/claude-1000/fonts-guard.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-guard.log | tail -5`
- Expected: EXIT=0 and `00:00 +1: All tests passed!`

**line_chart_math_test.dart**
- Run: `timeout 900 make -C app test TEST=test/widgets/line_chart_math_test.dart > /tmp/claude-1000/fonts-chartmath.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-chartmath.log | tail -5`
- Expected: EXIT=0 and `00:00 +23: All tests passed!`

**Full suite.** The Progress and Bodyweight screens and the layout sweep all mount the chart.
- Run: `timeout 900 make -C app test > /tmp/claude-1000/fonts-full.log 2>&1; echo EXIT=$?`
- Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/fonts-full.log | tail -5`
- Expected: EXIT=0 and `+907: All tests passed!`. That is 902 after the theme task plus this task's five new tests: four in line_chart_fonts_test and one in font_family_source_test.

- [ ] **Step 7: Analyze**

Run: `make -C app analyze > /tmp/claude-1000/fonts-analyze.log 2>&1; echo EXIT=$?`

Then: `tail -3 /tmp/claude-1000/fonts-analyze.log`

Expected: EXIT=0 and "No issues found!".

- [ ] **Step 8: Commit**

```
git add app/lib/widgets/line_chart.dart app/test/widgets/line_chart_fonts_test.dart app/test/theme/font_family_source_test.dart
git commit -m "fix(app): draw chart labels in the bundled JetBrains Mono"
```


### Task 3: One formatter per quantity

**Files:**
- Create: `app/lib/units/unit_format.dart`
- Modify: `app/lib/units/unit_service.dart`: the imports, the body of `UnitService.fmtDisplay`, and two new methods `fmtBw` and `fmtVol` placed right after `fmtDisplay`
- Test: `app/test/units/unit_format_test.dart` (new)

**Interfaces:**
- Consumes: nothing new. `Unit` and `UnitService.fromKg(double kg, Unit unit)` already exist.
- Produces (top-level functions in `app/lib/units/unit_format.dart`):
  - `String fmtLoad(double display, Unit unit)`: the set-weight rule
  - `String fmtBodyweight(double display)`: 1 dp, `.0` trimmed
  - `String fmtVolume(double kg, Unit unit)`: takes **kg**
  - `String fmtCount(double v)`: a grouped whole number
  - `double roundLoad(double display, Unit unit)`, `double roundBodyweight(double display)`, `double roundCount(double v)`
  - On `UnitService`: `String fmtBw(double kg)` and `String fmtVol(double kg)`. `static String fmtDisplay(double v, Unit unit)` becomes `=> fmtLoad(v, unit)` and behaves exactly as before. `fmtWt` does not change.
  - This task changes no call sites. `util/format.dart` stays until Task 5.

- [ ] **Step 1: Write the failing test.** Create `app/test/units/unit_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/units/unit_format.dart';
import 'package:workout_tracker/units/unit_service.dart';

/// A frozen, verbatim copy of the set-weight rule as `UnitService.fmtDisplay`
/// shipped it before [fmtLoad] existed. Kept here, not read from the service
/// (which now delegates to [fmtLoad]), so a drift in the rule fails this file:
/// the ruler's echo detection and the stepper's untouched-seed check compare
/// these strings.
String _frozenFmtDisplay(double v, Unit unit) {
  if (unit == Unit.lb) {
    return v.round().toString();
  }
  // kg: drop trailing ".0"
  if (v == v.truncateToDouble()) {
    return v.toInt().toString();
  }
  // Up to two decimals (quarter-kilo loads), trailing zeros trimmed.
  return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}

void main() {
  group('fmtLoad', () {
    test('matches the shipped set-weight rule over 0 to 500 in hundredths', () {
      for (final unit in Unit.values) {
        for (var i = 0; i <= 50000; i++) {
          final v = i / 100;
          final got = fmtLoad(v, unit);
          final want = _frozenFmtDisplay(v, unit);
          if (got != want) fail('fmtLoad($v, $unit) = "$got", want "$want"');
        }
      }
    });

    test('kg keeps up to two decimals, trimmed', () {
      expect(fmtLoad(80, Unit.kg), '80');
      expect(fmtLoad(72.5, Unit.kg), '72.5');
      expect(fmtLoad(60.25, Unit.kg), '60.25');
      expect(fmtLoad(60.10, Unit.kg), '60.1');
      expect(fmtLoad(1.005, Unit.kg), '1');
      expect(fmtLoad(1.125, Unit.kg), '1.13');
      expect(fmtLoad(99.999, Unit.kg), '100');
    });

    test('lb is a whole number and never grouped', () {
      expect(fmtLoad(220.46, Unit.lb), '220');
      expect(fmtLoad(220.5, Unit.lb), '221');
      expect(fmtLoad(1102.3, Unit.lb), '1102');
    });

    test('UnitService.fmtDisplay and fmtWt read the same', () {
      expect(UnitService.fmtDisplay(60.25, Unit.kg), fmtLoad(60.25, Unit.kg));
      expect(UnitService.fmtDisplay(220.46, Unit.lb), fmtLoad(220.46, Unit.lb));
      final u = UnitService()..setUnit(Unit.lb);
      expect(u.fmtWt(100), '220');
    });
  });

  group('fmtVolume', () {
    test('under a thousand reads whole, with the unit', () {
      expect(fmtVolume(0, Unit.kg), '0kg');
      expect(fmtVolume(850, Unit.kg), '850kg');
      expect(fmtVolume(0, Unit.lb), '0lb');
      expect(fmtVolume(385.6, Unit.lb), '850lb'); // 850.1 lb
    });

    test('a thousand and up reads in tenths: t for kg, k lb for lb', () {
      expect(fmtVolume(999.6, Unit.kg), '1t');
      expect(fmtVolume(1000, Unit.kg), '1t');
      expect(fmtVolume(1482.5, Unit.kg), '1.5t');
      expect(fmtVolume(5879, Unit.kg), '5.9t');
      expect(fmtVolume(1482.5, Unit.lb), '3.3k lb');
      expect(fmtVolume(5879, Unit.lb), '13k lb');
      expect(fmtVolume(453.4, Unit.lb), '1k lb');
    });

    test('a half tenth rounds up, where toStringAsFixed would not', () {
      expect(fmtVolume(1150, Unit.kg), '1.2t');
      expect(fmtVolume(9950, Unit.kg), '10t');
    });
  });

  group('fmtBodyweight', () {
    test('one decimal, with ".0" trimmed', () {
      expect(fmtBodyweight(82.37), '82.4');
      expect(fmtBodyweight(82), '82');
      expect(fmtBodyweight(82.04), '82');
      expect(fmtBodyweight(181.659), '181.7');
    });
  });

  group('fmtCount', () {
    test('a grouped whole number', () {
      expect(fmtCount(1482.5), '1,483');
      expect(fmtCount(3268.35), '3,268');
      expect(fmtCount(1102.3), '1,102');
      expect(fmtCount(5), '5');
      expect(fmtCount(-1200), '-1,200');
    });
  });

  group('rounding agrees with the formatters', () {
    test('roundLoad at half-cases', () {
      expect(roundLoad(1.005, Unit.kg), 1);
      expect(roundLoad(1.125, Unit.kg), 1.13);
      expect(roundLoad(60.25, Unit.kg), 60.25);
      expect(roundLoad(220.5, Unit.lb), 221);
      expect(roundLoad(219.911, Unit.lb), 220);
    });

    test('roundBodyweight at half-cases', () {
      expect(roundBodyweight(67.05), 67);
      expect(roundBodyweight(0.25), 0.3);
      expect(roundBodyweight(82.37), 82.4);
    });

    test('roundCount is fmtCount\'s own rule', () {
      expect(roundCount(1482.5), 1483);
      expect(roundCount(1074.75), 1075);
    });

    test('a rounded value formats exactly as the raw one', () {
      void same(String rounded, String raw, String what) {
        if (rounded != raw) fail('$what: rounded "$rounded", raw "$raw"');
      }

      for (var i = 0; i <= 20000; i++) {
        final v = i / 1000;
        for (final unit in Unit.values) {
          same(fmtLoad(roundLoad(v, unit), unit), fmtLoad(v, unit),
              'load $v $unit');
        }
        same(fmtBodyweight(roundBodyweight(v)), fmtBodyweight(v),
            'bodyweight $v');
        same(fmtCount(roundCount(v * 100)), fmtCount(v * 100),
            'count ${v * 100}');
      }
    });
  });

  group('UnitService', () {
    test('fmtBw is one decimal in the current unit', () {
      final u = UnitService()..setUnit(Unit.kg);
      expect(u.fmtBw(82.37), '82.4');
      u.setUnit(Unit.lb);
      expect(u.fmtBw(82.4), '181.7');
    });

    test('fmtVol takes kg and reads in the current unit', () {
      final u = UnitService()..setUnit(Unit.kg);
      expect(u.fmtVol(1482.5), '1.5t');
      u.setUnit(Unit.lb);
      expect(u.fmtVol(1482.5), '3.3k lb');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**
  - Run: `timeout 900 make -C app test TEST=test/units/unit_format_test.dart > /tmp/claude-1000/formatters-unit-format.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/formatters-unit-format.log | tail -5`
  - Expected: EXIT=2 and `+0 -1: Some tests failed.`, from a compile failure. The log contains `Error when reading 'lib/units/unit_format.dart': No such file or directory`, `Method not found: 'fmtLoad'`, `Method not found: 'fmtCount'`, `The method 'fmtBw' isn't defined for the type 'UnitService'` and `The method 'fmtVol' isn't defined for the type 'UnitService'`.

- [ ] **Step 3: Implement.** Create `app/lib/units/unit_format.dart`:

```dart
// One formatter per displayed quantity, plus the rounding that matches each.
//
// Every value here is already in display units except [fmtVolume], which
// takes kg like the tiles that call it. None of them ever groups a value that
// can seed an edit field: `parseNumberInput` reads ',' as the decimal
// separator, so "1,102" would commit 1.102.

import 'unit_service.dart';

/// A set weight already in [unit]: kg up to two decimals with trailing zeros
/// trimmed ("102.5", "60.25", "80"), lb as a whole number ("226").
///
/// The ruler's echo detection and the stepper's untouched-seed check compare
/// these strings, so this rule must not change.
String fmtLoad(double display, Unit unit) {
  if (unit == Unit.lb) {
    return display.round().toString();
  }
  // kg: drop trailing ".0"
  if (display == display.truncateToDouble()) {
    return display.toInt().toString();
  }
  // Up to two decimals (quarter-kilo loads), trailing zeros trimmed.
  return display.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}

/// A bodyweight already in display units: one decimal, ".0" trimmed
/// ("82.4", "82", "181.7").
String fmtBodyweight(double display) {
  if (display == display.roundToDouble()) return display.toInt().toString();
  final s = display.toStringAsFixed(1);
  if (s.endsWith('.0')) return s.substring(0, s.length - 2);
  return s;
}

/// A training volume of [kg], shown in [unit]: whole under a thousand
/// ("850kg", "850lb"), else in tenths of a thousand with ".0" trimmed
/// ("1t", "1.5t", "3.3k lb", "13k lb").
///
/// The tenths come from integer rounding, never `toStringAsFixed`, which
/// misrounds binary half-cases (1150 would read "1.1t").
String fmtVolume(double kg, Unit unit) {
  final v = UnitService.fromKg(kg, unit).round();
  if (v < 1000) return unit == Unit.lb ? '${v}lb' : '${v}kg';
  // Rounds half away from zero, exact at .5.
  final tenths = (v / 100).round();
  final whole = tenths ~/ 10;
  final n = tenths % 10 == 0 ? '$whole' : '$whole.${tenths % 10}';
  return unit == Unit.lb ? '${n}k lb' : '${n}t';
}

/// A count as a comma-grouped whole number ("1,483", "900"), matching
/// `toLocaleString('en-US')`. Display only: never an edit seed.
String fmtCount(double v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '-${buf.toString()}' : buf.toString();
}

// The round helpers return the precision the matching formatter shows, so a
// change computed from them is the change the user reads. The first two parse
// the formatter's own string, which keeps them in step at binary half-cases
// (1.005 kg reads "1"); that string is never empty or grouped.

/// [display] rounded the way [fmtLoad] shows it.
double roundLoad(double display, Unit unit) =>
    double.parse(fmtLoad(display, unit));

/// [display] rounded the way [fmtBodyweight] shows it.
double roundBodyweight(double display) =>
    double.parse(fmtBodyweight(display));

/// [v] rounded the way [fmtCount] shows it. Never parse [fmtCount]'s grouped
/// string.
double roundCount(double v) => v.roundToDouble();
```

In `app/lib/units/unit_service.dart`, add the import. Old:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Weight unit the user has selected.
```

New:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unit_format.dart';

/// Weight unit the user has selected.
```

Then replace `fmtDisplay` and add the two formatters after it. Old:

```dart
  /// Format a value already in [unit] for display: kg up to two decimals
  /// (trailing zeros trimmed), lb as a whole number.
  static String fmtDisplay(double v, Unit unit) {
    if (unit == Unit.lb) {
      return v.round().toString();
    }
    // kg: drop trailing ".0"
    if (v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    // Up to two decimals (quarter-kilo loads), trailing zeros trimmed.
    return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }
```

New:

```dart
  /// Format a value already in [unit] for display: kg up to two decimals
  /// (trailing zeros trimmed), lb as a whole number. The set-weight rule,
  /// [fmtLoad].
  static String fmtDisplay(double v, Unit unit) => fmtLoad(v, unit);

  /// Format a bodyweight in kg for display in the current unit: one decimal,
  /// ".0" trimmed ([fmtBodyweight]).
  String fmtBw(double kg) => fmtBodyweight(fromKg(kg, _unit));

  /// Format a training volume in kg for display in the current unit
  /// ([fmtVolume]): "850kg", "1.5t", "3.3k lb".
  String fmtVol(double kg) => fmtVolume(kg, _unit);
```

`unit_format.dart` and `unit_service.dart` now import each other. That is legal in Dart, and analyze reports nothing for it.

- [ ] **Step 4: Run the tests to verify they pass.** Run each command below, then grep its log with `grep -E "All tests passed|Some tests failed" <that log> | tail -1`.
  - `timeout 900 make -C app test TEST=test/units/unit_format_test.dart > /tmp/claude-1000/formatters-unit-format.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+15: All tests passed!`.
  - `timeout 900 make -C app test TEST=test/units/unit_service_test.dart > /tmp/claude-1000/formatters-unit-service.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+3`.
  - `timeout 900 make -C app test TEST=test/widgets/ruler_picker_test.dart > /tmp/claude-1000/formatters-ruler.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+39`. Echo detection compares `fmtDisplay` strings.
  - `timeout 900 make -C app test TEST=test/widgets/stepper_input_test.dart > /tmp/claude-1000/formatters-stepper-input.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+18`.
  - `timeout 900 make -C app test TEST=test/session/set_values_editor_test.dart > /tmp/claude-1000/formatters-set-values.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+5`.
  - Full suite: `timeout 900 make -C app test > /tmp/claude-1000/formatters-full.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/formatters-full.log | tail -2`. Expected: EXIT=0, `All tests passed!`.

- [ ] **Step 5: Analyze.**
  - Run: `make -C app analyze > /tmp/claude-1000/formatters-unit-format-analyze.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "issues? found" /tmp/claude-1000/formatters-unit-format-analyze.log`
  - Expected: EXIT=0 and `No issues found!`.

- [ ] **Step 6: Commit.**
  - `git add app/lib/units/unit_format.dart app/lib/units/unit_service.dart app/test/units/unit_format_test.dart`
  - `git commit -m "refactor(app): give each displayed quantity one formatter"`

### Task 4: Volume and bodyweight read the same everywhere

**Files:**
- Modify: `app/lib/session/session_summary_screen.dart`: in `_StatTiles`, delete `_fmtVolume()` and change the `value:` of the volume `_Tile`
- Modify: `app/lib/ui/history_screen.dart`: in `_HistoryScreenState._buildBody`, change `monthVolDisplay`
- Modify: `app/lib/ui/today_screen.dart`: in `_TodayScreenState._buildStatTiles`, change `bwValue`
- Modify: `app/lib/ui/profile_screen.dart`: in `_QuickStatsState.build`, change `bwText`
- Modify: `app/lib/ui/bodyweight_view.dart`: the imports, `_BwStatRow.build` and `BodyweightHistoryCard.build`
- Modify: `app/lib/settings/bodyweight_goal.dart`: the doc comment of `displayedBodyweightDelta`
- Modify: `app/lib/ui/exercise_editor.dart`: the imports, and the start-weight `Field`/`WStepper` in `build`
- Test: `app/test/ui/unit_display_test.dart` (new)
- Test: `app/test/ui/bodyweight_history_card_test.dart` (two new tests)
- Test: `app/test/ui/exercise_editor_start_weight_test.dart` (new)
- Test: `app/test/layout/lb_layout_test.dart` (new, a layout guard)

**Interfaces:**
- Consumes (Task 3): `UnitService.fmtVol(double kg)` and `UnitService.fmtBw(double kg)`, plus `fmtBodyweight(double)`, `roundBodyweight(double)` and `fmtLoad(double, Unit)` from `app/lib/units/unit_format.dart`. The profile-line task also edits `profile_screen.dart`. This task touches only the `bwText` expression in `_QuickStatsState`.
- Produces:
  - `app/test/ui/unit_display_test.dart`, with the `harness` setup, the `_lb` prefs constant and the `PowerSyncDatabase` import. Task 5 adds a theme import, a `_seedPairs` seed and a `group('Progress', …)` inside its `main`.
  - After this task, only `line_chart.dart` and `progress_screen.dart` still import `util/format.dart`.
  - `BodyweightView` still builds its `LineChart` without `formatValue`. Task 5 adds it.

- [ ] **Step 1: Write the failing tests.**

Create `app/test/ui/unit_display_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/ui/profile_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/ui/today_screen.dart';
import 'package:workout_tracker/widgets/sparkline.dart';

import '../support/screen_harness.dart';

const _lb = <String, Object>{'unit': 'lb'};

Widget _today() => Scaffold(
      body: TodayScreen(
        onStart: (_) {},
        onOpenExercise: (_) {},
        onOpenProfile: () {},
        onResume: () {},
        auth: AuthStore(),
      ),
    );

Widget _profile() =>
    ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore());

/// Two bodyweight entries two days apart, the latest 82.37 kg.
Future<void> _seedBodyweightOnly(PowerSyncDatabase d) async {
  final now = DateTime.now();
  await seedBodyweight(d, now.subtract(const Duration(days: 2)), 82.33);
  await seedBodyweight(d, now, 82.37);
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  group('volume reads the same on Summary and History', () {
    // seedLong's s0 lifts 1482.5 kg (3268 lb); its four sessions 5879 kg
    // (12961 lb).
    testWidgets('Summary shows lb volume as thousands of lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
      await settleUntilFound(tester, find.text(longExercise),
          where: 'Summary lb');
      expect(find.text('3.3k lb'), findsOneWidget);
      expect(find.text('3.3t'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('History shows lb volume as thousands of lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleUntilFound(tester, find.byType(SessionCard),
          where: 'History lb');
      expect(find.text('13k lb'), findsOneWidget);
      expect(find.text('13.0k'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('kg volume reads in tonnes on both (regression pin)',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
      await settleUntilFound(tester, find.text(longExercise),
          where: 'Summary kg');
      expect(find.text('1.5t'), findsOneWidget);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleUntilFound(tester, find.byType(SessionCard),
          where: 'History kg');
      expect(find.text('5.9t'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('an empty four weeks reads 0kg, like an empty session',
        (tester) async {
      await harness.open(tester, seed: (_) async {});
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleReal(tester);
      expect(find.text('0kg'), findsOneWidget);
      expect(find.text('0.0t'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('bodyweight reads the same on Today, Profile and its own view', () {
    // seedLong's latest bodyweight is 82.4 kg = 181.66 lb.
    testWidgets('in lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(_today()));
      await settleUntilFound(tester, find.byType(Sparkline), where: 'Today lb');
      expect(find.text('181.7'), findsOneWidget);
      expect(find.text('182'), findsNothing);

      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: bwId))));
      await settleUntilFound(tester, find.text('181.7'),
          where: 'Bodyweight lb');

      await tester.pumpWidget(harness.wrap(_profile()));
      await settleReal(tester);
      expect(find.text('181.7lb'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('in kg, a two-decimal entry reads one decimal everywhere',
        (tester) async {
      await harness.open(tester, seed: _seedBodyweightOnly);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(_today()));
      await settleUntilFound(tester, find.byType(Sparkline), where: 'Today kg');
      expect(find.text('82.4'), findsOneWidget);
      expect(find.text('82.37'), findsNothing);

      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: bwId))));
      await settleUntilFound(tester, find.text('82.4'),
          where: 'Bodyweight kg');
      expect(find.text('82.3'), findsOneWidget); // Lowest
      // 82.33 → 82.37 displays 82.3 → 82.4: the 30-day tile and the newest
      // history row both read the change they show, not "same".
      expect(find.text('+0.1'), findsNWidgets(2));

      await tester.pumpWidget(harness.wrap(_profile()));
      await settleReal(tester);
      expect(find.text('82.4kg'), findsOneWidget);
      await harness.unmount(tester);
    });
  });
}
```

In `app/test/ui/bodyweight_history_card_test.dart`, insert these two tests directly before `testWidgets('the oldest visible row still shows a delta when older entries exist', …)`:

```dart
  testWidgets('a delta is taken between the displayed values: 67.04 to 67.06 reads +0.1', (tester) async {
    // 67.04 → 67.06 displays 67 → 67.1; the raw +0.02 read "same".
    final series = [
      (date: '2026-09-06', value: 67.04, reps: 0, isPr: false),
      (date: '2026-09-07', value: 67.06, reps: 0, isPr: false),
    ];
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: series, unit: 'kg', goal: BodyweightGoal.bulk))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(find.text('+0.1'), findsOneWidget);
    expect(_colorOf(tester, '+0.1'), tokens.accentText);
  });

  testWidgets('rows that display the same weight read "same", neutral, on bulk', (tester) async {
    // 67.06 → 67.14 displays 67.1 → 67.1; the raw +0.08 read "+0.1".
    final series = [
      (date: '2026-09-06', value: 67.06, reps: 0, isPr: false),
      (date: '2026-09-07', value: 67.14, reps: 0, isPr: false),
    ];
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: series, unit: 'kg', goal: BodyweightGoal.bulk))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(find.text('same'), findsOneWidget);
    expect(_colorOf(tester, 'same'), tokens.dim);
  });

```

Create `app/test/ui/exercise_editor_start_weight_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

// Field renders its label upper-cased.
Finder _startWeight(Finder matching) => find.descendant(
      of: find.ancestor(
          of: find.text('START WEIGHT'), matching: find.byType(Field)),
      matching: matching,
    );

Future<void> _openEditor(WidgetTester tester, ScreenHarness harness) async {
  setPhone(tester, width: 412);
  await tester.pumpWidget(harness.wrap(
      Scaffold(body: ExerciseEditor(id: 'ex3', onBack: () {}))));
  await pumpUntilFound(tester,
      find.descendant(of: find.byType(ExerciseEditor), matching: find.byType(ListView)));
  await scrollIntoView(
      tester, find.byType(ExerciseEditor), find.text('START WEIGHT'));
}

/// The text the start-weight edit field is seeded with when tapped.
Future<String> _editSeed(WidgetTester tester, String shown) async {
  await tester.tap(_startWeight(find.text(shown)));
  await tester.pump();
  return tester
      .widget<TextField>(_startWeight(find.byType(TextField)))
      .controller!
      .text;
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('in lb the start weight reads whole pounds, like a live set',
      (tester) async {
    // seedLong's ex3 starts at 20 kg = 44.09 lb.
    await harness.open(tester, prefs: const {'unit': 'lb'});
    await _openEditor(tester, harness);
    expect(_startWeight(find.text('44lb')), findsOneWidget);
    expect(await _editSeed(tester, '44lb'), '44');
    await harness.unmount(tester);
  });

  testWidgets('in kg a quarter-kilo start weight keeps both decimals',
      (tester) async {
    await harness.open(tester, seed: (d) async {
      await seedLong(d);
      await d.execute(
          "UPDATE exercises SET base_weight_kg = '1.25' WHERE id = 'ex3'");
    });
    await _openEditor(tester, harness);
    expect(_startWeight(find.text('1.25kg')), findsOneWidget);
    expect(await _editSeed(tester, '1.25kg'), '1.25');
    await harness.unmount(tester);
  });
}
```

Create `app/test/layout/lb_layout_test.dart`. It guards the layout for the longer lb strings, and it already passes on main:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/ui/history_screen.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

// The lb volume strings ("3.3k lb", "13k lb") are the longest a volume tile
// shows.
void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('the summary holds in lb at $name', (tester) async {
      await harness.open(tester, prefs: const {'unit': 'lb'});
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          const SessionSummaryScreen(sessionId: 's0'),
          locale: c.locale));
      await pumpUntilFound(tester, find.text(longExercise));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(SessionSummaryScreen), 'Summary lb $name');
      await harness.unmount(tester);
    });

    testWidgets('History holds in lb at $name', (tester) async {
      await harness.open(tester, prefs: const {'unit': 'lb'});
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: HistoryScreen()),
          locale: c.locale));
      await settleUntilFound(tester, find.byType(SessionCard),
          where: 'History lb $name');
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(HistoryScreen), 'History lb $name');
      await harness.unmount(tester);
    });
  }
}
```

- [ ] **Step 2: Run them to verify they fail.** Run each command, then `grep -E "All tests passed|Some tests failed|Found 0" <that log> | head -8`.
  - `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display.log 2>&1; echo EXIT=$?`. Expected: EXIT=2 and `+1 -5`. Five checks find nothing:
    - "3.3k lb": main reads "3.3t".
    - "13k lb": main reads "13.0k".
    - "0kg": main reads "0.0t".
    - "181.7": Today reads "182".
    - "82.4": Today reads "82.37".
    - The kg tonnes pin passes.
  - `timeout 900 make -C app test TEST=test/ui/bodyweight_history_card_test.dart > /tmp/claude-1000/formatters-bw-card.log 2>&1; echo EXIT=$?`. Expected: EXIT=2 and `+6 -2`. It finds no `"+0.1"` (main reads "same") and no `"same"` (main reads "+0.1").
  - `timeout 900 make -C app test TEST=test/ui/exercise_editor_start_weight_test.dart > /tmp/claude-1000/formatters-editor-start.log 2>&1; echo EXIT=$?`. Expected: EXIT=2 and `+0 -2`. It finds no `"44lb"` (main reads "44.1lb") and no `"1.25kg"` (main reads "1.3kg").
  - `timeout 900 make -C app test TEST=test/layout/lb_layout_test.dart > /tmp/claude-1000/formatters-lb-layout.log 2>&1; echo EXIT=$?`. Expected: EXIT=0 and `+24: All tests passed!`. This one is the regression guard and passes before the change.

- [ ] **Step 3: Implement.**

In `app/lib/session/session_summary_screen.dart`, class `_StatTiles`, delete the method. Old:

```dart
  final UnitService unit;
  final WorkoutTokens tokens;

  String _fmtVolume() {
    final v = UnitService.fromKg(volumeKg, unit.unit);
    if (v >= 1000) {
      final t = v / 1000;
      final rounded = (t * 10).round() / 10;
      return '${rounded % 1 == 0 ? rounded.toInt() : rounded}t';
    }
    return '${v.round()}${unit.uLabel}';
  }

  @override
```

New:

```dart
  final UnitService unit;
  final WorkoutTokens tokens;

  @override
```

In the same class, the volume `_Tile`. Old:

```dart
            value: _fmtVolume(),
```

New:

```dart
            value: unit.fmtVol(volumeKg),
```

In `app/lib/ui/history_screen.dart`, in `_buildBody`. Old:

```dart
    final monthVolDisplay = () {
      final converted = UnitService.fromKg(monthTonnageKg, units.unit) / 1000;
      final suffix = units.uLabel == 'kg' ? 't' : 'k';
      return '${converted.toStringAsFixed(1)}$suffix';
    }();
```

New:

```dart
    final monthVolDisplay = units.fmtVol(monthTonnageKg);
```

In `app/lib/ui/today_screen.dart`, in `_buildStatTiles`. Old:

```dart
        final bwValue = hasBw ? units.fmtWt(bwEntries.last.weightKg) : '—';
```

New:

```dart
        final bwValue = hasBw ? units.fmtBw(bwEntries.last.weightKg) : '—';
```

In `app/lib/ui/profile_screen.dart`, in `_QuickStatsState.build`. Old:

```dart
                : '${unitService.fmtWt(bwEntries.last.weightKg)}${unitService.uLabel}';
```

New:

```dart
                : '${unitService.fmtBw(bwEntries.last.weightKg)}${unitService.uLabel}';
```

In `app/lib/ui/bodyweight_view.dart`, the imports. Old:

```dart
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../util/format.dart';
```

New:

```dart
import '../units/unit_format.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
```

In `_BwStatRow.build`, old:

```dart
    final last = series.last.value;
    final lowest =
        series.map((s) => s.value).reduce((a, b) => a < b ? a : b);
```

New:

```dart
    // Rounded to what the cards show, so the delta is the change they read.
    final last = roundBodyweight(series.last.value);
    final lowest = roundBodyweight(
        series.map((s) => s.value).reduce((a, b) => a < b ? a : b));
```

Old:

```dart
    final delta30 = last - month30.value;
    final delta30Label = signedChange(delta30, fmtPlain, l);
```

New:

```dart
    final delta30 = last - roundBodyweight(month30.value);
    final delta30Label = signedChange(delta30, fmtBodyweight, l);
```

Old:

```dart
                value: fmtPlain(last),
```

New:

```dart
                value: fmtBodyweight(last),
```

Old:

```dart
                value: fmtPlain(lowest),
```

New:

```dart
                value: fmtBodyweight(lowest),
```

Leave the accent expression `bodyweightDeltaTone(displayedBodyweightDelta(delta30), goal)` as it is. It now receives the rounded difference.

In `BodyweightHistoryCard.build`, inside `List.generate`, old:

```dart
          final seriesIndex = series.length - 1 - i;
          final prevValue =
              seriesIndex > 0 ? series[seriesIndex - 1].value : null;
          final diff = prevValue != null ? entry.value - prevValue : 0.0;
```

New:

```dart
          final seriesIndex = series.length - 1 - i;
          // Both ends rounded to what the rows show, so the delta is the
          // change between the two displayed weights.
          final value = roundBodyweight(entry.value);
          final prevValue = seriesIndex > 0
              ? roundBodyweight(series[seriesIndex - 1].value)
              : null;
          final diff = prevValue != null ? value - prevValue : 0.0;
```

Old:

```dart
                        text: fmtPlain(entry.value),
```

New:

```dart
                        text: fmtBodyweight(value),
```

Old:

```dart
                    signedChange(diff, fmtPlain, l),
```

New:

```dart
                    signedChange(diff, fmtBodyweight, l),
```

In `app/lib/settings/bodyweight_goal.dart`, old:

```dart
/// Rounds [delta] to the same one-decimal precision `fmtSigned` displays, so
/// a delta whose printed text reads "0" is never toned as a change — a raw
/// delta in (0, 0.05) would otherwise still read as a gain or loss.
double displayedBodyweightDelta(double delta) => (delta * 10).round() / 10;
```

New:

```dart
/// Rounds [delta] to the one-decimal precision `fmtBodyweight` displays, so a
/// delta that reads "same" is never toned as a change. Callers pass the
/// difference of two already-rounded weights; this also drops the binary
/// noise of that subtraction (67.1 − 67 is 0.0999…).
double displayedBodyweightDelta(double delta) => (delta * 10).round() / 10;
```

In `app/lib/ui/exercise_editor.dart`, the imports. Old:

```dart
import '../units/unit_service.dart';
import '../util/format.dart';
```

New:

```dart
import '../units/unit_format.dart';
import '../units/unit_service.dart';
```

The start-weight stepper in `build`. Old:

```dart
        // Start-weight stepper in DISPLAY units.
        // step = fromKg(plateStepKg, unit) — NOT raw plateStepKg.
        Field(
          label: l.exerciseEditorStartWeight,
          hint: l.exerciseEditorStartWeightHint,
          child: WStepper(
            value: _baseWeightDisplay,
            step: _stepDisplay,
            format: (v) => '${fmtPlain(v)}${units.uLabel}',
            onChanged: (v) {
              setState(() => _baseWeightDisplay = v < 0 ? 0 : v);
            },
            editable: true,
            formatForEdit: (v) => fmtPlain(v),
```

New. It gets no `parseDisplay`, because this stepper holds display units:

```dart
        // Start-weight stepper in DISPLAY units, read like a live set's
        // weight. step = fromKg(plateStepKg, unit) — NOT raw plateStepKg.
        // No parseDisplay: the value is already in display units.
        Field(
          label: l.exerciseEditorStartWeight,
          hint: l.exerciseEditorStartWeightHint,
          child: WStepper(
            value: _baseWeightDisplay,
            step: _stepDisplay,
            format: (v) => '${fmtLoad(v, units.unit)}${units.uLabel}',
            onChanged: (v) {
              setState(() => _baseWeightDisplay = v < 0 ? 0 : v);
            },
            editable: true,
            formatForEdit: (v) => fmtLoad(v, units.unit),
```

- [ ] **Step 4: Run the tests to verify they pass.** Run each command, then `grep -E "All tests passed|Some tests failed" <that log> | tail -1`.
  - `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+6`.
  - `timeout 900 make -C app test TEST=test/ui/bodyweight_history_card_test.dart > /tmp/claude-1000/formatters-bw-card.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+8`.
  - `timeout 900 make -C app test TEST=test/ui/exercise_editor_start_weight_test.dart > /tmp/claude-1000/formatters-editor-start.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+2`.
  - `timeout 900 make -C app test TEST=test/layout/lb_layout_test.dart > /tmp/claude-1000/formatters-lb-layout.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+24`.
  - The existing files this change can break. Each should give EXIT=0:
    - `timeout 900 make -C app test TEST=test/layout/summary_layout_test.dart > /tmp/claude-1000/formatters-summary-layout.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/layout/shell_layout_test.dart > /tmp/claude-1000/formatters-shell-layout.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/layout/profile_layout_test.dart > /tmp/claude-1000/formatters-profile-layout.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/ui/history_layout_test.dart > /tmp/claude-1000/formatters-history-layout.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/session/session_summary_layout_test.dart > /tmp/claude-1000/formatters-session-summary-layout.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/ui/exercise_editor_rir_test.dart > /tmp/claude-1000/formatters-editor-rir.log 2>&1; echo EXIT=$?`
    - `timeout 900 make -C app test TEST=test/ui/progress_layout_test.dart > /tmp/claude-1000/formatters-progress-layout.log 2>&1; echo EXIT=$?`
  - Full suite: `timeout 900 make -C app test > /tmp/claude-1000/formatters-full.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/formatters-full.log | tail -2`. Expected: EXIT=0, `All tests passed!`.

- [ ] **Step 5: Analyze.**
  - Run: `make -C app analyze > /tmp/claude-1000/formatters-volume-bw-analyze.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "issues? found" /tmp/claude-1000/formatters-volume-bw-analyze.log`
  - Expected: EXIT=0 and `No issues found!`.

- [ ] **Step 6: Commit.**
  - `git add app/lib/session/session_summary_screen.dart app/lib/ui/history_screen.dart app/lib/ui/today_screen.dart app/lib/ui/profile_screen.dart app/lib/ui/bodyweight_view.dart app/lib/settings/bodyweight_goal.dart app/lib/ui/exercise_editor.dart app/test/ui/unit_display_test.dart app/test/ui/bodyweight_history_card_test.dart app/test/ui/exercise_editor_start_weight_test.dart app/test/layout/lb_layout_test.dart`
  - `git commit -m "fix(app): read volume and bodyweight the same on every screen"`

### Task 5: Progress deltas come from the numbers it shows

**Files:**
- Modify: `app/lib/ui/progress_change.dart`:
  - the doc comments of `WeightChange`, `topSetChange` and `signedChange`
  - the `WeightChange` branch of `changeLabel`, and its doc
  - the reps branch of `progressDeltaStat`, and its doc
- Modify: `app/lib/widgets/line_chart.dart`:
  - the `util/format.dart` import
  - `LineChart`'s doc, constructor, fields and `build`
  - `_LineChartPainter`'s constructor and fields
  - the chip label in `paint`
  - `shouldRepaint`
- Modify: `app/lib/ui/progress_screen.dart`:
  - the imports
  - in `_LiftView`: `_fmtVal`, plus new `_isLoad` and `_roundVal`
  - in `_LiftView.build`: `shownValues`, and the arguments to `LineChart`, `_BigStatRow` and `_SessionLogCard`
  - the doc of `_SessionLogCard.seriesValues`
  - the delta colour in `_SessionLogCard.build`
- Modify: `app/lib/ui/bodyweight_view.dart`: the `LineChart` in `_BodyweightViewState.build`
- Delete: `app/lib/util/format.dart`, `app/test/util/format_test.dart`, `app/test/util/format_signed_test.dart`
- Create: `app/test/data/est1rm_test.dart`, `app/test/widgets/line_chart_value_label_test.dart`
- Test (modified): `app/test/ui/progress_change_test.dart`, `app/test/ui/unit_display_test.dart` (gains a theme import, `_seedPairs` and `group('Progress', …)`), `app/test/units/unit_format_test.dart`

**Interfaces:**
- Consumes:
  - Task 3: `fmtLoad`, `fmtCount`, `roundLoad`, `roundCount` and `fmtBodyweight`.
  - Task 4: `app/test/ui/unit_display_test.dart` (`harness`, `_lb`, the `PowerSyncDatabase` import), and `bodyweight_view.dart` already importing `../units/unit_format.dart`.
  - Task 2 (brand fonts): `line_chart.dart` paints its label styles through `chartLabelStyle(Color)` / `chartChipStyle(Color)`, and the painter calls `super(repaint: PaintingBinding.instance.systemFonts)`. None of the edits below touch those lines. The chip's `final label = …` line still calls `fmtPlain`, and this task replaces that line.
- Produces:
  - `LineChart({Key? key, required List<({String date, double value, int reps, bool isPr})> series, double height = 210, required String unit, bool showReps = true, required String Function(double) formatValue})`.
  - No `fmtPlain`, `fmtThousands` or `fmtSigned` anywhere. `util/format.dart` is gone.

- [ ] **Step 1: Write the failing tests (change labels).** Edit `app/test/ui/progress_change_test.dart`.

Replace the import `import 'package:workout_tracker/util/format.dart';` with:

```dart
import 'package:workout_tracker/units/unit_format.dart';
import 'package:workout_tracker/units/unit_service.dart';
```

After the test `'negatives use the real minus sign'`, add:

```dart
  test('a weight change the formatter rounds away reads "same"', () {
    expect(changeLabel(l, const WeightChange(0.2), fmtVal: (v) => v.round().toString()),
        'same');
  });
```

In group `signedChange`, change two lines:
- `expect(signedChange(-0.04, fmtPlain, l), 'same');` becomes `expect(signedChange(-0.04, fmtBodyweight, l), 'same');`
- `expect(signedChange(1200, fmtThousands, l), '+1,200');` becomes `expect(signedChange(1200, fmtCount, l), '+1,200');`

In group `progressDeltaStat`, after the test `'"same" never carries a unit'`, add:

```dart
    test('a weight change that formats as "same" carries no unit either', () {
      expect(
          progressDeltaStat(l,
              series: [100, 100.2],
              reps: true,
              firstTopReps: 5,
              topReps: 5,
              unit: 'lb',
              fmtVal: (v) => v.round().toString()),
          (value: 'same', unit: null));
    });
```

Directly before `group('shownProgressTarget', () {`, add the rounded-first pairs as pure-function pins:

```dart
  // Progress rounds each value to what it shows before subtracting; these
  // pairs read differently from raw subtraction. Pure-function pins: the
  // Progress screen tests pin that the screen feeds them rounded values.
  group('deltas between displayed lb values', () {
    double shown(double kg) => roundLoad(UnitService.fromKg(kg, Unit.lb), Unit.lb);
    String fmtLb(double v) => fmtLoad(v, Unit.lb);
    ({String value, String? unit}) stat(double fromKg, double toKg, {bool reps = false}) =>
        progressDeltaStat(l,
            series: [shown(fromKg), shown(toKg)],
            reps: reps,
            firstTopReps: 5,
            topReps: 5,
            unit: 'lb',
            fmtVal: fmtLb);

    test('99.75 to 100 kg both show 220 lb and read "same"', () {
      expect((shown(99.75), shown(100)), (220.0, 220.0));
      expect(signedChange(shown(100) - shown(99.75), fmtLb, l), 'same');
      expect(stat(99.75, 100), (value: 'same', unit: null));
      expect(stat(99.75, 100, reps: true), (value: 'same', unit: null));
    });

    test('100 to 100.1 kg show 220 then 221 lb and read "+1"', () {
      expect((shown(100), shown(100.1)), (220.0, 221.0));
      expect(signedChange(shown(100.1) - shown(100), fmtLb, l), '+1');
      expect(stat(100, 100.1), (value: '+1', unit: 'lb'));
      expect(stat(100, 100.1, reps: true), (value: '+1', unit: 'lb'));
    });

    test('a top set from 99.75 kg x6 to 100 kg x8 reads the rep change', () {
      final c = topSetChange(
          prevWeight: shown(99.75), prevReps: 6, curWeight: shown(100), curReps: 8);
      expect(changeLabel(l, c, fmtVal: fmtLb), '+2 reps');
    });
  });

```

- [ ] **Step 2: Run it to verify it fails.**
  - Run: `timeout 900 make -C app test TEST=test/ui/progress_change_test.dart > /tmp/claude-1000/formatters-progress-change.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Expected:|Actual:" /tmp/claude-1000/formatters-progress-change.log | head -10`
  - Expected: EXIT=2 and `+26 -2`:
    - `a weight change the formatter rounds away reads "same"`: Expected `'same'`, Actual `'+0'`.
    - `a weight change that formats as "same" carries no unit either`: Actual `(unit: lb, value: +0)`.
  - The three "deltas between displayed lb values" tests already pass. They are pure-function pins over Task 3's `roundLoad`. The screen-level red for rounding before subtracting comes in Step 12.

- [ ] **Step 3: Implement the change labels.** Edit `app/lib/ui/progress_change.dart`.

Old:

```dart
/// The weight moved by [delta] kg (display units, via the caller's `fmtVal`).
class WeightChange extends TopSetChange {
```

New:

```dart
/// The displayed weight moved by [delta], in display units.
class WeightChange extends TopSetChange {
```

Old:

```dart
/// Compares a previous top set to the current one and decides what to show.
TopSetChange topSetChange({
```

New:

```dart
/// Compares a previous top set to the current one and decides what to show.
///
/// The weights are the displayed (rounded) values, so a change too small to
/// show is no change and the rep change stands in for it.
TopSetChange topSetChange({
```

Old:

```dart
/// is exactly zero, or rounds away to nothing under the caller's formatter.
String signedChange(
```

New:

```dart
/// is exactly zero, or rounds away to nothing under the caller's formatter.
///
/// [delta] is the difference of two displayed (rounded) values, so it is the
/// change the user can read off the screen.
String signedChange(
```

Old:

```dart
/// - [WeightChange]: `fmtVal` of the absolute delta, prefixed with the sign
///   and suffixed with [unit] when non-empty (no space before the unit).
```

New:

```dart
/// - [WeightChange]: `fmtVal` of the absolute delta, prefixed with the sign
///   and suffixed with [unit] when non-empty (no space before the unit), or
///   [AppLocalizations.progressSame] when it formats as zero, as in
///   [signedChange]. A delta between displayed values never does; the guard
///   is defensive.
```

Old:

```dart
    case WeightChange(:final delta):
      final abs = fmtVal(delta.abs());
      final sign = delta > 0 ? '+$abs' : '−$abs';
```

New:

```dart
    case WeightChange(:final delta):
      final abs = fmtVal(delta.abs());
      if (abs == fmtVal(0)) return l.progressSame;
      final sign = delta > 0 ? '+$abs' : '−$abs';
```

Old:

```dart
/// For a top-set metric ([reps]) the rep change stands in when the weight
/// didn't move. The unit slot is null whenever the value is not a weight:
/// a rep change, or "same". Fewer than two points show "—".
```

New:

```dart
/// [series] holds the displayed (rounded) values. For a top-set metric
/// ([reps]) the rep change stands in when the weight didn't move. The unit
/// slot is null whenever the value is not a weight: a rep change, or "same".
/// Fewer than two points show "—".
```

Old:

```dart
    return (
      value: changeLabel(l, c, fmtVal: fmtVal),
      unit: c is WeightChange ? unitSlot : null,
    );
```

New:

```dart
    final value = changeLabel(l, c, fmtVal: fmtVal);
    return (
      value: value,
      unit: c is WeightChange && value != l.progressSame ? unitSlot : null,
    );
```

- [ ] **Step 4: Run it to verify it passes.**
  - Run: `timeout 900 make -C app test TEST=test/ui/progress_change_test.dart > /tmp/claude-1000/formatters-progress-change.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/formatters-progress-change.log | tail -1`
  - Expected: EXIT=0, `+28: All tests passed!`.

- [ ] **Step 5: Write the failing test (chart chip).** Create `app/test/widgets/line_chart_value_label_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/line_chart.dart';

import '../support/l10n_harness.dart';

void main() {
  testWidgets("the last point's value chip reads through the caller's formatter",
      (tester) async {
    final formatted = <double>[];
    await tester.pumpWidget(wrapL10n(SizedBox(
      width: 320,
      child: LineChart(
        series: const [
          (date: '2026-09-01', value: 1474.0, reps: 5, isPr: false),
          (date: '2026-09-08', value: 1482.5, reps: 5, isPr: false),
        ],
        unit: 'kg',
        showReps: false,
        formatValue: (v) {
          formatted.add(v);
          return '1,483';
        },
      ),
    )));
    // The chip paints once the 450ms mount has drawn the line in.
    await tester.pump(const Duration(milliseconds: 500));
    expect(formatted, contains(1482.5));
  });
}
```

- [ ] **Step 6: Run it to verify it fails.**
  - Run: `timeout 900 make -C app test TEST=test/widgets/line_chart_value_label_test.dart > /tmp/claude-1000/formatters-chart-chip.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/formatters-chart-chip.log | tail -5`
  - Expected: EXIT=2, with the compile error `Error: No named parameter with the name 'formatValue'.`

- [ ] **Step 7: Implement the chart formatter.** Edit `app/lib/widgets/line_chart.dart`.

Delete the line `import '../util/format.dart';`.

In the `LineChart` class doc, old:

```dart
/// Series values are already in display units — callers convert.
/// Each record includes
```

New:

```dart
/// Series values are already in display units — callers convert — and the
/// last point's value chip reads through [formatValue], the formatter the
/// caller's cards use.
/// Each record includes
```

In the `LineChart` constructor and fields, old:

```dart
    required this.unit,
    this.showReps = true,
  });

  final List<({String date, double value, int reps, bool isPr})> series;
  final double height;
  final String unit;
  final bool showReps;
```

New:

```dart
    required this.unit,
    this.showReps = true,
    required this.formatValue,
  });

  final List<({String date, double value, int reps, bool isPr})> series;
  final double height;
  final String unit;
  final bool showReps;

  /// Formats the last point's value for its chip, so the chip reads exactly
  /// like the screen's cards (Progress's `_fmtVal`, `fmtBodyweight`).
  final String Function(double) formatValue;
```

In `LineChart.build`, the painter arguments. Old:

```dart
              unit: unit,
              showReps: showReps,
              accent: tokens.accentText,
```

New:

```dart
              unit: unit,
              showReps: showReps,
              formatValue: formatValue,
              accent: tokens.accentText,
```

In the `_LineChartPainter` constructor, old:

```dart
    required this.unit,
    required this.showReps,
    required this.accent,
```

New:

```dart
    required this.unit,
    required this.showReps,
    required this.formatValue,
    required this.accent,
```

In the `_LineChartPainter` fields, old:

```dart
  final String unit;
  final bool showReps;
  final Color accent;
```

New:

```dart
  final String unit;
  final bool showReps;
  final String Function(double) formatValue;
  final Color accent;
```

In `paint`, the chip label: the two lines just above `final tp = TextPainter(`. After Task 2, that `TextSpan`'s style is `chartChipStyle(text)`. Old:

```dart
    final label =
        '${fmtPlain(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}';
```

New:

```dart
    final label =
        '${formatValue(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}';
```

In `shouldRepaint`, old:

```dart
        old.showReps != showReps ||
```

New:

```dart
        old.showReps != showReps ||
        old.formatValue != formatValue ||
```

In `app/lib/ui/bodyweight_view.dart`, the `LineChart` in `_BodyweightViewState.build`. Old:

```dart
                unit: unit,
                showReps: false,
              ),
```

New:

```dart
                unit: unit,
                showReps: false,
                formatValue: fmtBodyweight,
              ),
```

In `app/lib/ui/progress_screen.dart`, the `LineChart` in `_LiftView.build`. Old:

```dart
                  unit: unit,
                  showReps: metric.reps,
                ),
```

New:

```dart
                  unit: unit,
                  showReps: metric.reps,
                  formatValue: _fmtVal,
                ),
```

- [ ] **Step 8: Run them to verify they pass.** Run each command, then `grep -E "All tests passed|Some tests failed" <that log> | tail -1`.
  - `timeout 900 make -C app test TEST=test/widgets/line_chart_value_label_test.dart > /tmp/claude-1000/formatters-chart-chip.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+1`.
  - `timeout 900 make -C app test TEST=test/widgets/line_chart_math_test.dart > /tmp/claude-1000/formatters-chart-math.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+23`.

- [ ] **Step 9: Write the failing tests (Progress).** Edit `app/test/ui/unit_display_test.dart`.

Add the theme import, for `.tokens`. Old:

```dart
import 'package:workout_tracker/session/session_summary_screen.dart';
```

New:

```dart
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/theme/app_theme.dart';
```

Directly before `void main() {`, add the pairs seed:

```dart
/// Two sessions of pairs whose change reads differently once each value is
/// rounded to what Progress shows: lb exA 99.75 kg x5 -> 100 x5 (220 -> 220),
/// exB 100 x5 -> 100.1 x5 (220 -> 221), exC 99.75 x6 -> 100 x8 (220 -> 220,
/// two more reps); kg exD 60 x5 -> 60.25 x5.
Future<void> _seedPairs(PowerSyncDatabase d) async {
  await seedExercise(d, 'exA', 'Pair A');
  await seedExercise(d, 'exB', 'Pair B');
  await seedExercise(d, 'exC', 'Pair C');
  await seedExercise(d, 'exD', 'Pair D');
  final now = DateTime.now();
  await seedSession(d, 'p1',
      date: now.subtract(const Duration(days: 5)),
      label: 'Pairs',
      sets: [
        ('exA', 99.75, 5, 1, false),
        ('exB', 100, 5, 1, false),
        ('exC', 99.75, 6, 1, false),
        ('exD', 60, 5, 1, false),
      ]);
  await seedSession(d, 'p2',
      date: now.subtract(const Duration(days: 2)),
      label: 'Pairs',
      sets: [
        ('exA', 100, 5, 1, false),
        ('exB', 100.1, 5, 1, false),
        ('exC', 100, 8, 1, false),
        ('exD', 60.25, 5, 1, false),
      ]);
}

```

Inside `main`, after the closing `});` of `group('bodyweight reads the same on Today, Profile and its own view', …)`, add:

```dart

  group('Progress', () {
    // seedLong's ex3 top sets, oldest first: 95, 97.5, 100, 102.5 kg x5,
    // which display as 209, 215, 220, 226 lb.
    testWidgets('lb shows whole pounds and the changes between them',
        (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: 'ex3'))));
      // Current and Best are plain Text.
      await settleUntilFound(tester, find.text('226'), where: 'Progress lb');
      expect(find.text('+17'), findsOneWidget); // 226 − 209
      // Session-log rows are Text.rich: find.text matches their plain text.
      expect(find.text('220lb × 5'), findsOneWidget);
      expect(find.textContaining('220.5'), findsNothing);
      // The newest row shows its PR badge; the two below read the change
      // between the rows on screen (220 − 215, 215 − 209), where subtracting
      // the raw values would read +6 twice.
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('+6'), findsOneWidget);

      // Volume, 1047, 1075, 1102, 1130 lb shown: the middle change is
      // 1102 − 1075, where subtracting the raw values would read +28.
      await tester.tap(find.text('Volume'));
      await settleUntilFound(tester, find.text('+27'),
          where: 'Progress lb volume');
      expect(find.text('1,102lb'), findsOneWidget);
      await harness.unmount(tester);
    });

    // The 12-week tile and the newer session-log row both read the change
    // between the displayed values, accent only when it is a real gain.
    for (final (id, shown, change, accent) in const [
      ('exA', '220', 'same', false),
      ('exB', '221', '+1', true),
      ('exC', '220', '+2 reps', true),
    ]) {
      testWidgets('lb $id reads $change between the shown top sets',
          (tester) async {
        await harness.open(tester, prefs: _lb, seed: _seedPairs);
        setPhone(tester, width: 412);
        await tester.pumpWidget(harness.wrap(
            Scaffold(body: ProgressScreen(initialTarget: id))));
        await settleUntilFound(tester, find.textContaining('lb × '),
            where: 'Progress $id');
        final tokens = tester.element(find.byType(ProgressScreen)).tokens;
        expect(find.text(shown), findsNWidgets(2)); // Current and Best
        expect(find.text(change), findsNWidgets(2)); // 12wk tile, newer row
        final row = tester.widgetList<Text>(find.text(change)).last;
        expect(row.style!.color, accent ? tokens.accentText : tokens.faint);
        await harness.unmount(tester);
      });
    }

    testWidgets('kg keeps a quarter-kilo top set and its change',
        (tester) async {
      await harness.open(tester, seed: _seedPairs);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: 'exD'))));
      await settleUntilFound(tester, find.textContaining('kg × '),
          where: 'Progress exD');
      expect(find.text('60.25'), findsNWidgets(2)); // Current and Best
      expect(find.text('+0.25'), findsNWidgets(2)); // 12wk tile, newer row
      await harness.unmount(tester);
    });
  });
```

- [ ] **Step 10: Run it to verify it fails (the formatter).**
  - Run: `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display-progress.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Found 0" /tmp/claude-1000/formatters-unit-display-progress.log | head -8`
  - Expected: EXIT=2 and `+6 -5`. This red comes from `fmtPlain`, the formatter. Five checks find nothing:
    - ex3 `"+17"`: main reads "+16.5". The wait on '226' passes, because `fmtPlain(225.97)` also reads "226".
    - exA `"220"`: main reads "220.5".
    - exB `"221"`: main reads "220.7".
    - exC `"220"`: main reads "220.5".
    - exD `"60.25"`: main reads "60.3".

- [ ] **Step 11: Implement the Progress formatter.** Edit `app/lib/ui/progress_screen.dart`. Change the imports first. Old:

```dart
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../util/format.dart';
```

New:

```dart
import '../units/unit_format.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
```

`_LiftView._fmtVal`. Old:

```dart
  String _fmtVal(double v) =>
      metricId == 'volume' ? fmtThousands(v) : fmtPlain(v);
```

New:

```dart
  bool get _isLoad => metricId == 'top' || metricId == 'e1rm';

  // A weight reads as a set weight does on every other screen (whole lb,
  // kg up to two decimals); volume and reps read as whole counts.
  String _fmtVal(double v) =>
      _isLoad ? fmtLoad(v, unitService.unit) : fmtCount(v);
```

- [ ] **Step 12: Run it to verify the rounding is still missing.**
  - Run: `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display-progress.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Found 0" /tmp/claude-1000/formatters-unit-display-progress.log | head -8`
  - Expected: EXIT=2 and `+7 -4`. This red comes from subtracting raw values. Four checks find nothing:
    - ex3 `"+5"`: the raw rows read "+6" twice.
    - exA `"same"`: the tile and the row read "+1".
    - exB `"+1"`: both read "same".
    - exC `"+2 reps"`: both read "+1".
  - exD now passes. The kg quarter-kilo reading was the formatter's red.

- [ ] **Step 13: Implement rounding before subtracting.** In `app/lib/ui/progress_screen.dart`, add `_roundVal` directly after `_fmtVal`. Old:

```dart
  String _fmtVal(double v) =>
      _isLoad ? fmtLoad(v, unitService.unit) : fmtCount(v);
```

New:

```dart
  String _fmtVal(double v) =>
      _isLoad ? fmtLoad(v, unitService.unit) : fmtCount(v);

  // [v] rounded to exactly what [_fmtVal] shows, so a change is computed
  // between two values on screen.
  double _roundVal(double v) =>
      _isLoad ? roundLoad(v, unitService.unit) : roundCount(v);
```

In `_LiftView.build`, old:

```dart
    final seriesValues = rawSeries.map(_displayValue).toList();
```

New:

```dart
    final seriesValues = rawSeries.map(_displayValue).toList();
    // What the cards and the session log show and subtract. The chart keeps
    // the raw values, so its y-domain and ticks don't move.
    final shownValues = seriesValues.map(_roundVal).toList();
```

Old:

```dart
        _BigStatRow(
          series: seriesValues,
```

New:

```dart
        _BigStatRow(
          series: shownValues,
```

Old:

```dart
          _SessionLogCard(
            rawSeries: rawSeries,
            seriesValues: seriesValues,
```

New:

```dart
          _SessionLogCard(
            rawSeries: rawSeries,
            seriesValues: shownValues,
```

The `chartSeries` built from `seriesValues[i]` stays raw.

The `_SessionLogCard` fields. Old:

```dart
  final List<ProgressPoint> rawSeries;
  final List<double> seriesValues;
```

New:

```dart
  final List<ProgressPoint> rawSeries;

  /// Each point's displayed (rounded) value, parallel to [rawSeries].
  final List<double> seriesValues;
```

In `_SessionLogCard.build`, the delta colour. Old:

```dart
            deltaLabel = changeLabel(l, c, fmtVal: fmtVal);
            deltaColor = (c is WeightChange && c.delta > 0) ||
                    (c is RepChange && c.delta > 0)
                ? tokens.accentText
                : tokens.faint;
          } else {
            deltaLabel = signedChange(diff, fmtVal, l);
            deltaColor = diff > 0 ? tokens.accentText : tokens.faint;
          }
```

New:

```dart
            deltaLabel = changeLabel(l, c, fmtVal: fmtVal);
            final up = (c is WeightChange && c.delta > 0) ||
                (c is RepChange && c.delta > 0);
            deltaColor = up && deltaLabel != l.progressSame
                ? tokens.accentText
                : tokens.faint;
          } else {
            deltaLabel = signedChange(diff, fmtVal, l);
            deltaColor = diff > 0 && deltaLabel != l.progressSame
                ? tokens.accentText
                : tokens.faint;
          }
```

- [ ] **Step 14: Run it to verify it passes.**
  - Run: `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display-progress.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/formatters-unit-display-progress.log | tail -1`
  - Expected: EXIT=0, `+11: All tests passed!`.

- [ ] **Step 15: Delete `util/format.dart` and move its tests.** This step does not change behaviour. The moved cases are regression guards.

In `app/test/units/unit_format_test.dart`, add the moved `fmtPlain` cases as the first tests of `group('fmtBodyweight', …)`, before `test('one decimal, with ".0" trimmed', …)`:

```dart
    test('whole number returns bare integer', () {
      expect(fmtBodyweight(80), '80');
      expect(fmtBodyweight(80.0), '80');
    });
    test('fractional returns 1dp, no trailing .0', () {
      expect(fmtBodyweight(72.5), '72.5');
    });
```

Add the moved `fmtThousands` cases as the first tests of `group('fmtCount', …)`, before `test('a grouped whole number', …)`:

```dart
    test('comma-groups thousands', () {
      expect(fmtCount(12500), '12,500');
    });
    test('values under 1000 have no comma', () {
      expect(fmtCount(900), '900');
    });
```

Create `app/test/data/est1rm_test.dart`, with the `est1rm` group moved verbatim:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';

void main() {
  group('est1rm', () {
    test('Epley formula rounds correctly', () {
      // 100 * (1 + 5/30) = 116.666... → 117
      expect(est1rm(100, 5), 117);
    });
    test('1 rep returns the weight itself', () {
      expect(est1rm(100, 1), (100 * (1 + 1 / 30)).round());
    });
  });
}
```

Delete the old file and its two tests: `git rm app/lib/util/format.dart app/test/util/format_test.dart app/test/util/format_signed_test.dart`. `fmtSigned` is dead and has no successor. Then confirm that nothing still references them: `grep -rn "util/format\|fmtPlain\|fmtThousands\|fmtSigned" app/lib app/test`. Expected: no output.

- [ ] **Step 16: Run the tests to verify they pass.** Run each command, then `grep -E "All tests passed|Some tests failed" <that log> | tail -1`.
  - `timeout 900 make -C app test TEST=test/units/unit_format_test.dart > /tmp/claude-1000/formatters-unit-format-moved.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+19`.
  - `timeout 900 make -C app test TEST=test/data/est1rm_test.dart > /tmp/claude-1000/formatters-est1rm.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+2`.
  - `timeout 900 make -C app test TEST=test/ui/progress_change_test.dart > /tmp/claude-1000/formatters-progress-change-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+28`.
  - `timeout 900 make -C app test TEST=test/ui/unit_display_test.dart > /tmp/claude-1000/formatters-unit-display-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+11`.
  - `timeout 900 make -C app test TEST=test/widgets/line_chart_value_label_test.dart > /tmp/claude-1000/formatters-chart-chip-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+1`.
  - `timeout 900 make -C app test TEST=test/widgets/line_chart_math_test.dart > /tmp/claude-1000/formatters-chart-math-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+23`.
  - `timeout 900 make -C app test TEST=test/ui/bodyweight_history_card_test.dart > /tmp/claude-1000/formatters-bw-card-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+8`.
  - `timeout 900 make -C app test TEST=test/ui/progress_layout_test.dart > /tmp/claude-1000/formatters-progress-layout-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+4`.
  - `timeout 900 make -C app test TEST=test/ui/progress_screen_target_test.dart > /tmp/claude-1000/formatters-progress-target.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+2`.
  - `timeout 900 make -C app test TEST=test/layout/shell_layout_test.dart > /tmp/claude-1000/formatters-shell-layout-final.log 2>&1; echo EXIT=$?`. Expected: EXIT=0, `+12`.
  - Full suite: `timeout 900 make -C app test > /tmp/claude-1000/formatters-full.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/formatters-full.log | tail -2`. Expected: EXIT=0, `All tests passed!`.

- [ ] **Step 17: Analyze.**
  - Run: `make -C app analyze > /tmp/claude-1000/formatters-progress-analyze.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "issues? found" /tmp/claude-1000/formatters-progress-analyze.log`
  - Expected: EXIT=0 and `No issues found!`.

- [ ] **Step 18: Commit.**
  - `git add app/lib/ui/progress_change.dart app/lib/ui/progress_screen.dart app/lib/widgets/line_chart.dart app/lib/ui/bodyweight_view.dart app/test/ui/progress_change_test.dart app/test/ui/unit_display_test.dart app/test/units/unit_format_test.dart app/test/widgets/line_chart_value_label_test.dart app/test/data/est1rm_test.dart`
  - Step 15's `git rm` already staged the deletions.
  - `git commit -m "fix(app): show Progress in whole pounds and compute its changes from the shown values"`


### Task 6: RIR picker offers the full 0–5 range

**Files:**
- Create: `app/test/support/rir_expect.dart`
- Modify: `app/lib/widgets/rir_picker.dart` (whole file: class `RirPicker`)
- Modify: `app/lib/data/models.dart` (the doc comment above `const int rirMin`)
- Modify: `app/lib/ui/day_editor.dart` (`_DaySlotRowState.build`, the `// RIR low + RIR high` `Row`: the two `WStepper`s with `semanticLabel: l.dayEditorRirLow` / `l.dayEditorRirHigh`)
- Modify: `app/lib/ui/exercise_editor.dart` (`_ExerciseEditorState` build, the `// RIR low + RIR high` `Row`: the two `WStepper`s whose `onChanged` call `rirWithLow` / `rirWithHigh`)
- Test: `app/test/widgets/rir_picker_test.dart` (rewritten)
- Test (picker behaviour at the real host widths): `app/test/session/set_line_test.dart`, `app/test/session/live_set_card_test.dart`, `app/test/ui/set_editor_sheet_test.dart`, `app/test/layout/live_layout_test.dart`
- Test (regression guards for the behaviour-neutral constant refactor): `app/test/data/rir_range_test.dart`, `app/test/ui/day_editor_slot_row_test.dart`, `app/test/ui/exercise_editor_rir_test.dart`

**Interfaces:**
- Consumes: `rirMin` / `rirMax` (`const int`, `app/lib/data/models.dart`, already exist). Existing test support: `wrapL10n` (`test/support/l10n_harness.dart`), `preloadAppFonts` (`test/support/app_fonts.dart`), `pumpUntilFound` (`test/support/pump_until.dart`), and from `test/support/screen_harness.dart`: `ScreenHarness`, `setPhone`, `layoutConditions`, `describeCondition`, `longDraft`, `settleReal`, `settleUntilFound`, `scrollIntoView`, `expectLayoutHoldsWhileScrolling`. `ActiveSessionController.seedForTest`, `.logLiveSet()`, `.focusSet(SetState)` and `.draft` (all exist). Nothing from other areas' tasks.
- Produces:
  - `RirPicker({Key? key, required int? value, required ValueChanged<int> onChanged, double height = 48})`. It renders exactly the keys `rir-$rirMin` … `rir-$rirMax` (`rir-0` … `rir-5`). Each key sits on the chip's slot (a `GestureDetector`, `HitTestBehavior.opaque`), which also holds the 3dp gap to the next chip in its row. The visible face is the slot's `DecoratedBox`: `tokens.accent` when selected, `tokens.surface3` otherwise, with the digit in `tokens.accentInk` / `tokens.dim`. It shows one row of six when `maxWidth / 6 >= 48`, otherwise two rows of three with a 3dp row gap, and it absorbs taps inside its own rect.
  - `int expectRirChipsAtLeast48(WidgetTester tester, {String where = ''})` in `app/test/support/rir_expect.dart`. It asserts that every `rir-n` slot is at least 48×48 and returns the number of chip rows.
  - In `live_set_card_test.dart`: `host(Widget child, {Locale locale = const Locale('en'), double width = 260})`, plus `setUpAll(preloadAppFonts)`.
  - In `set_editor_sheet_test.dart`: `setUpAll(preloadAppFonts)` and the imports `rir_expect.dart`, `app_fonts.dart`, `screen_harness.dart show setPhone`, `rir_picker.dart` and `app_theme.dart`.
  - The next task relies on all of these.

- [ ] **Step 1: Write the failing picker test**

Replace `app/test/widgets/rir_picker_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';

import '../support/l10n_harness.dart';

Finder _chip(int n) => find.byKey(Key('rir-$n'));

/// The chip's own fill: the keyed slot also holds the 3dp gap to its
/// neighbour, the decorated box is what the user sees.
Finder _face(int n) =>
    find.descendant(of: _chip(n), matching: find.byType(DecoratedBox));

Color? _fill(WidgetTester tester, int n) =>
    (tester.widget<DecoratedBox>(_face(n)).decoration as BoxDecoration).color;

Color? _digit(WidgetTester tester, int n) => tester
    .widget<Text>(find.descendant(of: _chip(n), matching: find.byType(Text)))
    .style
    ?.color;

void main() {
  Widget picker(int? value, {double width = 320, List<int>? reports}) => wrapL10n(
        SizedBox(
          width: width,
          child: RirPicker(value: value, onChanged: (v) => reports?.add(v)),
        ),
      );

  testWidgets('renders one chip per RIR value, rirMin to rirMax', (tester) async {
    await tester.pumpWidget(picker(1));
    for (var n = rirMin; n <= rirMax; n++) {
      expect(_chip(n), findsOneWidget, reason: 'rir-$n');
    }
    expect(_chip(rirMin - 1), findsNothing);
    expect(_chip(rirMax + 1), findsNothing);
  });

  testWidgets('rirMax can be selected and is reported', (tester) async {
    final reports = <int>[];
    await tester.pumpWidget(picker(rirMax, reports: reports));
    final tokens = tester.element(find.byType(RirPicker)).tokens;
    expect(_fill(tester, rirMax), tokens.accent);
    expect(_digit(tester, rirMax), tokens.accentInk);
    for (var n = rirMin; n < rirMax; n++) {
      expect(_fill(tester, n), tokens.surface3, reason: 'rir-$n');
    }
    await tester.tap(_chip(rirMax));
    expect(reports, [rirMax]);
  });

  for (final value in [7, null]) {
    testWidgets('a stored $value selects no chip', (tester) async {
      await tester.pumpWidget(picker(value));
      final tokens = tester.element(find.byType(RirPicker)).tokens;
      for (var n = rirMin; n <= rirMax; n++) {
        expect(_fill(tester, n), tokens.surface3, reason: 'rir-$n');
        expect(_digit(tester, n), tokens.dim, reason: 'rir-$n');
      }
    });
  }

  testWidgets('at 288dp the six chips sit in one row of 48dp slots', (tester) async {
    await tester.pumpWidget(picker(1, width: 288));
    final first = tester.getRect(_chip(rirMin));
    for (var n = rirMin; n <= rirMax; n++) {
      final slot = tester.getRect(_chip(n));
      expect(slot.top, first.top, reason: 'rir-$n');
      expect(slot.width, 48, reason: 'rir-$n');
      expect(slot.height, 48, reason: 'rir-$n');
    }
    // The 3dp gap sits between chips, not after the last one.
    expect(tester.getRect(_face(rirMin)).width, 45);
    expect(tester.getRect(_face(rirMax)).width, 48);
  });

  testWidgets('at 287dp the chips split into two rows of three', (tester) async {
    await tester.pumpWidget(picker(1, width: 287));
    final top = tester.getRect(_chip(0));
    final bottom = tester.getRect(_chip(3));
    for (final n in [1, 2]) {
      expect(tester.getRect(_chip(n)).top, top.top, reason: 'rir-$n');
    }
    for (final n in [4, 5]) {
      expect(tester.getRect(_chip(n)).top, bottom.top, reason: 'rir-$n');
    }
    expect(bottom.top, top.bottom + 3); // the row gap
    expect(bottom.left, top.left);
    for (var n = rirMin; n <= rirMax; n++) {
      final slot = tester.getRect(_chip(n));
      expect(slot.width, closeTo(287 / 3, 1e-9), reason: 'rir-$n');
      expect(slot.height, 48, reason: 'rir-$n');
    }
    // Each row ends flush: the last chip of a row keeps no gap.
    expect(tester.getRect(_face(2)).right, tester.getRect(_chip(2)).right);
    expect(tester.getRect(_face(5)).right, tester.getRect(_chip(5)).right);
    expect(tester.getRect(_face(1)).width, closeTo(287 / 3 - 3, 1e-9));
  });

  testWidgets('chips default to 48dp tall', (tester) async {
    await tester.pumpWidget(picker(1));
    expect(tester.getSize(_chip(2)).height, 48);
  });

  testWidgets('RirPicker honours its height', (tester) async {
    await tester.pumpWidget(wrapL10n(
        SizedBox(width: 320, child: RirPicker(value: 1, height: 56, onChanged: (_) {}))));
    expect(tester.getSize(_chip(2)).height, 56);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 900 make -C app test TEST=test/widgets/rir_picker_test.dart > /tmp/claude-1000/rir-picker.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-picker.log | tail -5`

Expected: EXIT=2, `+1 -7: Some tests failed.` Only `RirPicker honours its height` passes. The failures:
- `renders one chip per RIR value…`: `Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'rir-4'>]: []>`.
- `rirMax can be selected…`, `a stored 7 selects no chip` and `a stored null selects no chip`: `Bad state: No element`, because there is no `rir-4` / `rir-5` face.
- `at 288dp…`: `Actual: <72.0>`, because four chips share the 288dp.
- `at 287dp…`: `The finder "Found 0 widgets with key [<'rir-4'>]: []" … could not find any matching widgets`.
- `chips default to 48dp tall`: `Actual: <30.0>`.

- [ ] **Step 3: Write the failing tests at the real host widths**

Each host gives the picker a different width. The behaviour these tests pin comes from the picker: six chips, two rows below 288dp, and absorbed gap taps. So they are written here and seen red before the picker changes.

Create `app/test/support/rir_expect.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';

/// Expects every RIR chip on screen (`rir-<rirMin>`…`rir-<rirMax>`) to be a
/// slot of at least 48×48dp, and returns how many rows the chips sit in.
int expectRirChipsAtLeast48(WidgetTester tester, {String where = ''}) {
  final tops = <double>{};
  for (var n = rirMin; n <= rirMax; n++) {
    final slot = tester.getRect(find.byKey(Key('rir-$n')));
    expect(slot.width, greaterThanOrEqualTo(48), reason: '$where rir-$n width');
    expect(slot.height, greaterThanOrEqualTo(48), reason: '$where rir-$n height');
    tops.add(slot.top);
  }
  return tops.length;
}
```

In `app/test/session/set_line_test.dart`:

1. Add the import after `import '../support/layout_expect.dart';`:

```dart
import '../support/rir_expect.dart';
```

2. Replace the whole test `'RIR chips stay at least 48dp wide at a 260dp line width'`:

```dart
  testWidgets('RIR chips stay at least 48dp wide at a 260dp line width', (tester) async {
    await tester.pumpWidget(wrapL10n(
        SizedBox(width: 260, child: line(_s(done: true), prompt: true))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('rir-0'))).width, greaterThanOrEqualTo(48));
  });
```

with:

```dart
  // The line's width in a block on a 320dp and a 412dp phone (the list
  // padding, block border and sets padding take 58dp), and the chip rows
  // the strip must fall into there.
  for (final (width, scale, rows) in const [
    (262.0, 1.0, 2),
    (262.0, 2.0, 2),
    (354.0, 1.0, 1),
    (354.0, 2.0, 2),
  ]) {
    testWidgets(
        'every RIR chip is at least 48x48 at ${width.toInt()}dp / ${scale}x, '
        'in $rows row${rows == 1 ? '' : 's'}', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
            size: Size(width + 58, 900), textScaler: TextScaler.linear(scale)),
        child: wrapL10n(SizedBox(width: width, child: line(_s(done: true), prompt: true))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(expectRirChipsAtLeast48(tester), rows);
    });
  }

  testWidgets('a tap in the gap between the chip rows neither sets RIR nor focuses the set',
      (tester) async {
    await tester.pumpWidget(wrapL10n(
        SizedBox(width: 262, child: line(_s(done: true), prompt: true))));
    await tester.pumpAndSettle();
    final top = tester.getRect(find.byKey(const Key('rir-0')));
    final bottom = tester.getRect(find.byKey(const Key('rir-3')));
    expect(bottom.top, greaterThan(top.bottom)); // two rows, with a gap
    await tester.tapAt(Offset(top.center.dx, (top.bottom + bottom.top) / 2));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(rirs, isEmpty);
  });
```

In `app/test/session/live_set_card_test.dart`:

1. Replace `import '../support/l10n_harness.dart';` with:

```dart
import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/rir_expect.dart';
```

2. At the top of `main()`, replace:

```dart
void main() {
  late int changes;
```

with:

```dart
void main() {
  // Real metrics: the RIR row's layout depends on the caption's width.
  setUpAll(preloadAppFonts);

  late int changes;
```

3. Replace the `host` helper:

```dart
  Widget host(Widget child, {Locale locale = const Locale('en')}) =>
      wrapL10n(SingleChildScrollView(child: SizedBox(width: 260, child: child)), locale: locale);
```

with:

```dart
  Widget host(Widget child, {Locale locale = const Locale('en'), double width = 260}) =>
      wrapL10n(SingleChildScrollView(child: SizedBox(width: width, child: child)), locale: locale);
```

4. Immediately before the test `'no RIR picker for a pending set or a logged warm-up'`, add:

```dart
  // The card's width in a block on a 320dp and a 412dp phone (the list
  // padding, block border and sets padding take 58dp), and the chip rows
  // its RIR row must fall into there.
  for (final (width, scale, rows) in const [
    (262.0, 1.0, 2),
    (262.0, 2.0, 2),
    (354.0, 1.0, 1),
    (354.0, 2.0, 2),
  ]) {
    testWidgets(
        'every RIR chip is at least 48x48 at ${width.toInt()}dp / ${scale}x, '
        'in $rows row${rows == 1 ? '' : 's'}', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
            size: Size(width + 58, 900), textScaler: TextScaler.linear(scale)),
        child: host(card(_s(done: true)), width: width),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(expectRirChipsAtLeast48(tester), rows);
    });
  }

```

In `app/test/ui/set_editor_sheet_test.dart`:

1. Replace the import block:

```dart
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/ui/set_editor_sheet.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

import '../support/l10n_harness.dart';
```

with:

```dart
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/ui/set_editor_sheet.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/rir_expect.dart';
import '../support/screen_harness.dart' show setPhone;
```

2. At the top of `main()`, replace:

```dart
void main() {
  testWidgets('each set is a >=48dp line; tapping one opens its rulers', (tester) async {
```

with:

```dart
void main() {
  // Real metrics: the RIR row's layout depends on the caption's width.
  setUpAll(preloadAppFonts);

  testWidgets('each set is a >=48dp line; tapping one opens its rulers', (tester) async {
```

3. Replace the whole test `'the RIR chips in the open card are at least 48dp tall'`, which sits after the `dragOffset` / `dragDuration` consts that the last new test uses:

```dart
  testWidgets('the RIR chips in the open card are at least 48dp tall', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('rir-0'))).height, greaterThanOrEqualTo(48));
  });
```

with the block below. The sweep opens the sheet through the file's `host()`, which is `showModalBottomSheet(isScrollControlled: true)` as History does:

```dart
  // History opens the sheet across the whole phone; the chip rows its open
  // card must fall into there.
  for (final (width, scale, rows) in const [
    (320.0, 1.0, 2),
    (320.0, 2.0, 2),
    (412.0, 1.0, 1),
    (412.0, 2.0, 1),
  ]) {
    testWidgets(
        'every RIR chip in the open card is at least 48x48 on a ${width.toInt()}dp phone '
        'at ${scale}x, in $rows row${rows == 1 ? '' : 's'}', (tester) async {
      setPhone(tester, width: width, textScale: scale);
      final repo = FakeSessionRepository();
      await tester.pumpWidget(host(repo, [_set('s1')]));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('set-line-s1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(expectRirChipsAtLeast48(tester), rows);
    });
  }

  testWidgets('a set can be corrected to RIR 5', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1', rir: 1)]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rir-5')));
    await tester.pump(const Duration(milliseconds: 500)); // past the 400ms debounce
    expect(repo.updateCalls, isNotEmpty);
    expect(repo.updateCalls.last.rir, 5);
  });

  // Regression guard: a stored out-of-range RIR is neither shown as a
  // choice nor rewritten by an unrelated edit.
  testWidgets('a stored RIR outside the range selects no chip and survives a weight edit',
      (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1', rir: 7)]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    final tokens = tester.element(find.byType(SetEditorSheet)).tokens;
    final faces = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byType(RirPicker), matching: find.byType(DecoratedBox)));
    expect(faces, isNotEmpty);
    for (final face in faces) {
      expect((face.decoration as BoxDecoration).color, tokens.surface3);
    }

    await tester.timedDrag(find.byKey(const Key('live-weight')), dragOffset, dragDuration);
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.updateCalls, isNotEmpty);
    expect(repo.updateCalls.last.rir, 7);
  });
```

Replace `app/test/layout/live_layout_test.dart` with the version below. It adds the two live-screen states that render a `RirPicker`, which the sweep never covered. In `longDraft()`'s first block, `l1` is logged and `l2` pending. `logLiveSet()` logs `l2` and opens its strip, and `focusSet` on `l1` puts that logged set in the live card.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/active_session_screen.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';

import '../support/rir_expect.dart';
import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('the live workout holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      final controller = ActiveSessionController()..seedForTest(longDraft());
      await tester.pumpWidget(harness.wrap(
        const ActiveSessionScreen(),
        locale: c.locale,
        extra: [
          ChangeNotifierProvider<ActiveSessionController>.value(
              value: controller),
        ],
      ));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ActiveSessionScreen), 'Live $name');
      await harness.unmount(tester);
    });

    // The two places a RIR picker shows on the live screen: the strip under
    // a just-logged set, and the live card of a logged set being corrected.
    // Both fit one row of six only on the wide phone at 1.0x.
    final rows = c.width == 412 && c.textScale == 1.0 ? 1 : 2;
    for (final (state, prepare) in <(String, void Function(ActiveSessionController))>[
      ('the RIR strip open', (ctl) => ctl.logLiveSet()),
      ('a logged set in the live card',
          (ctl) => ctl.focusSet(ctl.draft.blocks.first.workingSets.first)),
    ]) {
      testWidgets('the live workout with $state holds at $name', (tester) async {
        await harness.open(tester);
        setPhone(tester, width: c.width, textScale: c.textScale);
        final controller = ActiveSessionController()..seedForTest(longDraft());
        prepare(controller);
        await tester.pumpWidget(harness.wrap(
          const ActiveSessionScreen(),
          locale: c.locale,
          extra: [
            ChangeNotifierProvider<ActiveSessionController>.value(
                value: controller),
          ],
        ));
        await settleUntilFound(tester, find.byType(RirPicker),
            where: 'Live, $state, $name');
        expect(find.byType(RirPicker), findsOneWidget);
        expect(expectRirChipsAtLeast48(tester, where: 'Live, $state, $name'), rows);
        await expectLayoutHoldsWhileScrolling(
            tester, find.byType(ActiveSessionScreen), 'Live, $state, $name');
        await harness.unmount(tester);
      });
    }
  }
}
```

- [ ] **Step 4: Run them to verify they fail**

Run: `timeout 900 make -C app test TEST="test/session/set_line_test.dart test/session/live_set_card_test.dart test/ui/set_editor_sheet_test.dart" > /tmp/claude-1000/rir-hosts-red.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-hosts-red.log | tail -5`

Expected: EXIT=2, `+40 -14: Some tests failed.` The 14 failures:
- **The twelve 48×48 sweep cases** fail with `The finder "Found 0 widgets with key [<'rir-4'>]: []" (used in a call to "getTopLeft()") could not find any matching widgets`. The exceptions are SetLine and LiveSetCard at 262dp and 2.0×. There the width check fires first, at `Actual: <47.42…>` and `Actual: <45.15…>` (the spec's "about 47 / 45dp").
- **The gap tap** fails with `Expected: a value greater than <96.0> Actual: <48.0>`, because the four chips sit in one row. When the two-row layout lands without the absorbing outer detector, the same test fails at `expect(taps, 0)` with `Actual: <1>`.
- **`a set can be corrected to RIR 5`** fails with `The finder "Found 0 widgets with key [<'rir-5'>]: []" (used in a call to "tap()") could not find any matching widgets`.

The RIR 7 guard passes, because it is a regression guard.

Run: `timeout 900 make -C app test TEST=test/layout/live_layout_test.dart > /tmp/claude-1000/rir-live-layout-red.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-live-layout-red.log | tail -5`

Expected: EXIT=2, `+12 -24: Some tests failed.`
- The 24 failures are exactly the new RIR-state cases: `rir-4` is missing, and at 320dp 2.0× the chips are `47.42…` / `45.15…` wide.
- The 12 original cases pass.

- [ ] **Step 5: Write the regression guards for the constant refactor**

These guards pass both before and after the change.

In `app/test/data/rir_range_test.dart`, which already imports `package:workout_tracker/data/models.dart`, find this test in `group('rirWithLow', …)`:

```dart
    test('the low is clamped to 0–5', () {
      expect(rirWithLow(1, 3, -2), (low: 0, high: 3));
      expect(rirWithLow(1, 3, 9), (low: 5, high: 5));
    });
```

and replace it with:

```dart
    test('the low is clamped to rirMin–rirMax', () {
      expect(rirWithLow(1, 3, rirMin - 2), (low: rirMin, high: 3));
      expect(rirWithLow(1, 3, rirMax + 4), (low: rirMax, high: rirMax));
    });
```

Then find this test in `group('rirWithHigh', …)`:

```dart
    test('the high is clamped to 0–5', () {
      expect(rirWithHigh(1, 3, 12), (low: 1, high: 5));
      expect(rirWithHigh(2, 3, -1), (low: 0, high: 0));
    });
```

and replace it with:

```dart
    test('the high is clamped to rirMin–rirMax', () {
      expect(rirWithHigh(1, 3, rirMax + 7), (low: 1, high: rirMax));
      expect(rirWithHigh(2, 3, rirMin - 1), (low: rirMin, high: rirMin));
    });
```

In `app/test/ui/day_editor_slot_row_test.dart` (it already imports models.dart), replace the whole test `'RIR steppers stay within 0 to 5'` with:

```dart
  testWidgets('RIR steppers stay within rirMin to rirMax', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrapL10n(const _Harness(expandedIndex: 0)));
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    for (var i = 0; i < 7; i++) {
      await tester.tap(rirButton('RIR HIGH', 'stepper-inc'));
      await tester.pumpAndSettle();
    }
    expect(state.slots[0].draft.rirHigh, rirMax);
    expect(state.slots[0].draft.rirLow, 1);

    for (var i = 0; i < 3; i++) {
      await tester.tap(rirButton('RIR LOW', 'stepper-dec'));
      await tester.pumpAndSettle();
    }
    expect(state.slots[0].draft.rirLow, rirMin);
    expect(state.slots[0].draft.rirHigh, rirMax);
  });
```

In `app/test/ui/exercise_editor_rir_test.dart`:

1. Add the import after `import 'package:flutter_test/flutter_test.dart';`:

```dart
import 'package:workout_tracker/data/models.dart';
```

2. Append this test inside `main()`, after the test `'RIR low and high stay ordered: each drags the other along'`:

```dart
  testWidgets('RIR steppers stay within rirMin to rirMax', (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(harness.wrap(
        Scaffold(body: ExerciseEditor(id: 'ex3', onBack: () {}))));
    await pumpUntilFound(tester,
        find.descendant(of: find.byType(ExerciseEditor), matching: find.byType(ListView)));
    await scrollIntoView(
        tester, find.byType(ExerciseEditor), find.text('RIR HIGH'));

    // Seeded at RIR 1–2.
    for (var i = 0; i < 7; i++) {
      await tester.tap(_inField('RIR HIGH', find.byKey(const Key('stepper-inc'))));
      await tester.pump();
    }
    expect(_inField('RIR HIGH', find.text('$rirMax')), findsOneWidget);
    expect(_inField('RIR LOW', find.text('1')), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(_inField('RIR LOW', find.byKey(const Key('stepper-dec'))));
      await tester.pump();
    }
    expect(_inField('RIR LOW', find.text('$rirMin')), findsOneWidget);
    expect(_inField('RIR HIGH', find.text('$rirMax')), findsOneWidget);

    await harness.unmount(tester);
  });
```

- [ ] **Step 6: Run the guards (green before the change)**

Run: `timeout 900 make -C app test TEST="test/data/rir_range_test.dart test/ui/day_editor_slot_row_test.dart test/ui/exercise_editor_rir_test.dart" > /tmp/claude-1000/rir-guards.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-guards.log | tail -5`

Expected: EXIT=0, `+18: All tests passed!`

- [ ] **Step 7: Implement**

Replace `app/lib/widgets/rir_picker.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A segmented RIR (Reps In Reserve) picker for values 0–5 ([rirMin] to
/// [rirMax]).
///
/// Selected segment = solid accent background + accentInk text.
/// Unselected = surface3 background + dim text. A value outside the range
/// (old free-text data, a restore) selects nothing and is never rewritten.
///
/// One row of six when each chip's slot is at least 48dp wide, otherwise two
/// rows of three with a 3dp gap between them: rows stay balanced, never 5+1.
/// The slots tile each row, a slot being maxWidth/6 wide in one row and
/// maxWidth/3 in two, so at the default [height] a picker at least 144dp
/// wide always gets slots of at least 48×48dp.
///
/// Warm-up sets should render an empty [SizedBox] of the same width instead
/// of this widget (the disabled state is handled by the caller, not here).
///
/// Button keys: `rir-<n>` (e.g. `rir-0`, `rir-1`, ...).
///
/// Taps do NOT bubble to enclosing widgets: each chip is a [GestureDetector]
/// with [HitTestBehavior.opaque], and the picker itself absorbs taps that
/// land between chips, so a tap in the row gap never reaches a host's own
/// tap (the live `SetLine` would turn the logged set back into the live card).
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `RirPicker`.
class RirPicker extends StatelessWidget {
  const RirPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 48,
  });

  /// Currently selected RIR value (0–5), or null for no selection.
  final int? value;

  final ValueChanged<int> onChanged;

  /// Chip height. Defaults to 48, the height every host uses.
  final double height;

  static const double _minSlot = 48;
  static const double _gap = 3;
  static const int _count = rirMax - rirMin + 1;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget chip(int r, {required bool lastInRow}) {
      final selected = value == r;
      return GestureDetector(
        key: Key('rir-$r'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onChanged(r);
        },
        child: Container(
          height: height,
          margin: EdgeInsets.only(right: lastInRow ? 0 : _gap),
          decoration: BoxDecoration(
            color: selected ? tokens.accent : tokens.surface3,
            borderRadius: BorderRadius.circular(AppRadius.radius * 0.35),
          ),
          alignment: Alignment.center,
          child: Text(
            '$r',
            style: WorkoutType.mono(
              size: 12,
              weight: FontWeight.w700,
              color: selected ? tokens.accentInk : tokens.dim,
            ),
          ),
        ),
      );
    }

    Widget row(int first, int last) => Row(
          children: [
            for (var r = first; r <= last; r++)
              Expanded(child: chip(r, lastInRow: r == last)),
          ],
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth / _count >= _minSlot) return row(rirMin, rirMax);
          final split = rirMin + (_count + 1) ~/ 2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(rirMin, split - 1),
              const SizedBox(height: _gap),
              row(split, rirMax),
            ],
          );
        },
      ),
    );
  }
}
```

In `app/lib/data/models.dart`, replace:

```dart
/// The editors' RIR bounds: 0–5.
const int rirMin = 0;
```

with:

```dart
/// The RIR range, 0–5: the bounds of every RIR picker and editor stepper.
const int rirMin = 0;
```

In `app/lib/ui/day_editor.dart` (`_DaySlotRowState.build`, the `// RIR low + RIR high` Row), replace:

```dart
                            min: 0,
                            max: 5,
                            semanticLabel: l.dayEditorRirLow,
```

with:

```dart
                            min: rirMin.toDouble(),
                            max: rirMax.toDouble(),
                            semanticLabel: l.dayEditorRirLow,
```

and replace:

```dart
                            min: 0,
                            max: 5,
                            semanticLabel: l.dayEditorRirHigh,
```

with:

```dart
                            min: rirMin.toDouble(),
                            max: rirMax.toDouble(),
                            semanticLabel: l.dayEditorRirHigh,
```

In `app/lib/ui/exercise_editor.dart` (the `// RIR low + RIR high` Row, whose steppers call `rirWithLow` / `rirWithHigh`), replace:

```dart
                  min: 0,
                  max: 5,
                  semanticLabel: l.dayEditorRirLow,
```

with:

```dart
                  min: rirMin.toDouble(),
                  max: rirMax.toDouble(),
                  semanticLabel: l.dayEditorRirLow,
```

and replace:

```dart
                  min: 0,
                  max: 5,
                  semanticLabel: l.dayEditorRirHigh,
```

with:

```dart
                  min: rirMin.toDouble(),
                  max: rirMax.toDouble(),
                  semanticLabel: l.dayEditorRirHigh,
```

Both editors already import `../data/models.dart`.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 900 make -C app test TEST="test/widgets/rir_picker_test.dart test/data/rir_range_test.dart test/ui/day_editor_slot_row_test.dart test/ui/exercise_editor_rir_test.dart test/session/set_line_test.dart test/session/live_set_card_test.dart test/ui/set_editor_sheet_test.dart test/layout/live_layout_test.dart test/session/active_session_screen_test.dart test/session/exercise_block_edit_test.dart test/session/exercise_block_badge_test.dart test/session/add_exercise_button_layout_test.dart test/session/exercise_block_accordion_test.dart test/session/log_set_bar_test.dart" > /tmp/claude-1000/rir-picker-green.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-picker-green.log | tail -5`

Expected: EXIT=0, `+149: All tests passed!`
- The list holds the picker test, the three guards and every test file that mounts a RIR host or an `ExerciseBlock`.
- Per-file counts, as a note: rir_picker 8, set_line 20, live_set_card 17, set_editor_sheet 17, live_layout 36.

Then the full suite, because a shared widget changed (its default height, its layout and a new outer detector): `timeout 900 make -C app test > /tmp/claude-1000/rir-picker-full.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-picker-full.log | tail -5`. Expected: EXIT=0, `All tests passed!`.

- [ ] **Step 9: Analyze**

`make -C app analyze > /tmp/claude-1000/rir-picker-analyze.log 2>&1; echo EXIT=$?` Expected: EXIT=0 and "No issues found!".

- [ ] **Step 10: Commit**

```
git add app/lib/widgets/rir_picker.dart app/lib/data/models.dart app/lib/ui/day_editor.dart app/lib/ui/exercise_editor.dart app/test/support/rir_expect.dart app/test/widgets/rir_picker_test.dart app/test/session/set_line_test.dart app/test/session/live_set_card_test.dart app/test/ui/set_editor_sheet_test.dart app/test/layout/live_layout_test.dart app/test/data/rir_range_test.dart app/test/ui/day_editor_slot_row_test.dart app/test/ui/exercise_editor_rir_test.dart
git commit -m "fix(app): offer the full RIR 0 to 5 range in chips of at least 48dp"
```

### Task 7: RIR hosts keep 48dp chips and align the caption

**Files:**
- Modify: `app/lib/session/set_line.dart` (`SetLine.build`: the `final strip = …` local, the inline `FitLabel(l.sessionRir(...))` under `if (done && !set.isWarmup)`, and the RIR strip `Row` inside the `AnimatedSize`)
- Modify: `app/lib/session/live_set_card.dart` (`LiveSetCard.build`: the RIR row under `if (set.done && !set.isWarmup) ...[`)
- Modify: `app/lib/ui/set_editor_sheet.dart` (`_SetEditingCard.build`: the RIR row under `if (!set.isWarmup) ...[`)
- Modify: `app/test/support/rir_expect.dart` (append `expectCaptionOnFirstRirRow`)
- Test: `app/test/session/set_line_test.dart`, `app/test/session/live_set_card_test.dart`, `app/test/ui/set_editor_sheet_test.dart`

**Interfaces:**
- Consumes (from the RIR range task above):
  - `RirPicker(value:, onChanged:, height = 48)` with keys `rir-0`…`rir-5`, one row when `maxWidth / 6 >= 48`, otherwise two rows of three with a 3dp gap;
  - `expectRirChipsAtLeast48(WidgetTester, {String where})` in `test/support/rir_expect.dart`;
  - live_set_card_test's `host(…, {double width = 260})` and its `setUpAll(preloadAppFonts)`;
  - set_editor_sheet_test's `setUpAll(preloadAppFonts)` and its `setPhone` / `rir_expect.dart` imports;
  - the set_line_test sweep and gap-tap tests, which are the anchors for the insertions below;
  - `rirMin` from `app/lib/data/models.dart`.
- Produces: `void expectCaptionOnFirstRirRow(WidgetTester tester, Finder caption)` in `test/support/rir_expect.dart`. The hosts no longer pass `height: 48`; they rely on the picker's default.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/support/rir_expect.dart`:

```dart

/// Expects the host's [caption] to sit level with the first chip row, as it
/// must when the chips wrap to two rows.
void expectCaptionOnFirstRirRow(WidgetTester tester, Finder caption) {
  expect(tester.getCenter(caption).dy,
      moreOrLessEquals(tester.getCenter(find.byKey(Key('rir-$rirMin'))).dy, epsilon: 0.01));
}
```

In `app/test/session/set_line_test.dart`:

1. Immediately before the test `'the RIR strip shows 48dp chips; a chip tap sets RIR, not focus'` (that is, after `'a logged line shows its RIR and the TOP tag'`), add:

```dart
  testWidgets('a logged working set with no RIR shows no RIR text', (tester) async {
    await tester.pumpWidget(wrapL10n(line(_s(done: true, rir: null))));
    expect(find.text('140kg  ×  6'), findsOneWidget);
    expect(find.textContaining('RIR'), findsNothing);
  });

```

2. Immediately before the test `'a tap in the gap between the chip rows neither sets RIR nor focuses the set'`, add:

```dart
  testWidgets('in two rows the RIR caption sits level with the first', (tester) async {
    await tester.pumpWidget(wrapL10n(
        SizedBox(width: 262, child: line(_s(done: true), prompt: true))));
    await tester.pumpAndSettle();
    expect(expectRirChipsAtLeast48(tester), 2);
    expectCaptionOnFirstRirRow(tester, find.text('RIR'));
  });

```

In `app/test/session/live_set_card_test.dart`, immediately before the test `'no RIR picker for a pending set or a logged warm-up'` (after the 48×48 sweep), add:

```dart
  testWidgets('in two rows the RIR caption sits level with the first', (tester) async {
    await tester.pumpWidget(host(card(_s(done: true)), width: 262));
    await tester.pumpAndSettle();
    expect(expectRirChipsAtLeast48(tester), 2);
    expectCaptionOnFirstRirRow(tester, find.text('RIR'));
  });

```

In `app/test/ui/set_editor_sheet_test.dart`, immediately before the test `'a set can be corrected to RIR 5'`, add the test below. It opens the sheet as History does, through the file's `host()`:

```dart
  testWidgets('in two rows the RIR caption sits level with the first', (tester) async {
    setPhone(tester, width: 320);
    final repo = FakeSessionRepository();
    await tester.pumpWidget(host(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();
    expect(expectRirChipsAtLeast48(tester), 2);
    expectCaptionOnFirstRirRow(tester, find.text('RIR'));
  });

```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 900 make -C app test TEST="test/session/set_line_test.dart test/session/live_set_card_test.dart test/ui/set_editor_sheet_test.dart" > /tmp/claude-1000/rir-hosts.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-hosts.log | tail -5`

Expected: EXIT=2, `+54 -4: Some tests failed.` The four new tests fail:
- `set_line_test: a logged working set with no RIR shows no RIR text` fails with `Expected: no matching candidates Actual: _TextContainingWidgetFinder:<Found 1 widget with text containing RIR: [...]>`, because the line renders "RIR 0".
- The three `in two rows the RIR caption sits level with the first` tests fail as follows. In each, the caption is centred on the 99dp two-row block instead of on the first 48dp row.
  - set_line: `Expected: 72.0 (±0.01) Actual: <97.5>`
  - live_set_card: `Expected: 280.5 (±0.01) Actual: <306.0>`
  - set_editor_sheet: `Expected: 676.5 (±0.01) Actual: <702.0>`

Every other test in the three files passes.

- [ ] **Step 3: Implement**

`app/lib/session/set_line.dart`, in `SetLine.build`, replace:

```dart
    final done = set.done;
    final strip = showRirPrompt && done && !set.isWarmup;
```

with:

```dart
    final done = set.done;
    final strip = showRirPrompt && done && !set.isWarmup;
    // A logged working set with no RIR (resumed, or added in History) shows
    // none, as History's line does.
    final rir = done && !set.isWarmup ? set.rir : null;
```

Then replace:

```dart
                          if (done && !set.isWarmup)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: FitLabel(
                                  l.sessionRir(set.rir ?? 0),
```

with:

```dart
                          if (rir != null)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: FitLabel(
                                  l.sessionRir(rir),
```

Then replace the strip:

```dart
                      padding: const EdgeInsets.only(left: 22, bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            l.sessionColRir,
                            style: WorkoutType.mono(
                                size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RirPicker(value: set.rir, height: 48, onChanged: onRir),
                          ),
                        ],
                      ),
```

with:

```dart
                      padding: const EdgeInsets.only(left: 22, bottom: 8),
                      // When the chips wrap to two rows, the caption stays
                      // level with the first.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 48,
                            child: Center(
                              child: Text(
                                l.sessionColRir,
                                style: WorkoutType.mono(
                                    size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RirPicker(value: set.rir, onChanged: onRir),
                          ),
                        ],
                      ),
```

`app/lib/session/live_set_card.dart`, in `LiveSetCard.build`, replace:

```dart
          if (set.done && !set.isWarmup) ...[
            const SizedBox(height: 12),
            inset(Row(
              children: [
                Text(l.sessionColRir, style: caption()),
                const SizedBox(width: 12),
                Expanded(
                  child: RirPicker(
                    value: set.rir,
                    height: 48,
                    onChanged: (v) {
```

with:

```dart
          if (set.done && !set.isWarmup) ...[
            const SizedBox(height: 12),
            // When the chips wrap to two rows, the caption stays level with
            // the first.
            inset(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Center(child: Text(l.sessionColRir, style: caption())),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RirPicker(
                    value: set.rir,
                    onChanged: (v) {
```

The rest (`set.rir = v; onChanged(); },` and the closing brackets) is unchanged.

`app/lib/ui/set_editor_sheet.dart`, in `_SetEditingCard.build`, replace:

```dart
          if (!set.isWarmup) ...[
            const SizedBox(height: 12),
            inset(
              Row(
                children: [
                  Text(l.sessionColRir, style: caption()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RirPicker(
                      value: set.rir,
                      height: 48,
                      onChanged: onRir,
                    ),
                  ),
                ],
              ),
            ),
          ],
```

with:

```dart
          if (!set.isWarmup) ...[
            const SizedBox(height: 12),
            // When the chips wrap to two rows, the caption stays level with
            // the first.
            inset(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(l.sessionColRir, style: caption()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RirPicker(value: set.rir, onChanged: onRir),
                  ),
                ],
              ),
            ),
          ],
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 make -C app test TEST="test/session/set_line_test.dart test/session/live_set_card_test.dart test/ui/set_editor_sheet_test.dart test/layout/live_layout_test.dart test/widgets/rir_picker_test.dart test/session/active_session_screen_test.dart test/session/exercise_block_edit_test.dart test/session/exercise_block_badge_test.dart test/session/add_exercise_button_layout_test.dart test/session/exercise_block_accordion_test.dart test/session/log_set_bar_test.dart" > /tmp/claude-1000/rir-hosts-green.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-hosts-green.log | tail -5`

Expected: EXIT=0, `+135: All tests passed!`
- Per-file counts, as a note: set_line 22, live_set_card 18, set_editor_sheet 18, live_layout 36.
- Dropping the hosts' explicit `height: 48` is guarded by these existing tests, which still assert 48dp chips: `the RIR strip shows 48dp chips…` and `a logged working set can still correct its RIR`. The 48×48 sweeps and the live layout cases guard it too.

Then the full suite: `timeout 900 make -C app test > /tmp/claude-1000/rir-full.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/rir-full.log | tail -5`. Expected: EXIT=0, `All tests passed!`.

- [ ] **Step 5: Analyze**

`make -C app analyze > /tmp/claude-1000/rir-hosts-analyze.log 2>&1; echo EXIT=$?` Expected: EXIT=0 and "No issues found!".

- [ ] **Step 6: Commit**

```
git add app/lib/session/set_line.dart app/lib/session/live_set_card.dart app/lib/ui/set_editor_sheet.dart app/test/support/rir_expect.dart app/test/session/set_line_test.dart app/test/session/live_set_card_test.dart app/test/ui/set_editor_sheet_test.dart
git commit -m "fix(app): keep the RIR caption level with the first chip row and hide an unset RIR"
```


### Task 8: Action sheets mark the current choice and never overflow

**Files:**
- Modify: `app/lib/widgets/w_action_sheet.dart` (the whole file: `WSheetAction`, `showWActionSheet` doc, `_WActionSheetBody.build`, `_WActionSheetBody._row`)
- Test: `app/test/widgets/w_action_sheet_test.dart`

**Interfaces:**
- Consumes: nothing new. It uses `FitLabel` / `RenderFitLabel` from `app/lib/widgets/fit_label.dart`, `WIcons.check` from `app/lib/theme/icons.dart`, and `setPhone` and `preloadAppFonts` from `test/support/`.
- Produces (Task 9 relies on these):
  - The constructor becomes `const WSheetAction<T>({required String label, required T value, IconData? icon, bool destructive = false, bool enabled = true, bool selected = false, Locale? labelLocale})`.
    - `icon` is now optional (`IconData?`).
    - Every existing call site compiles unchanged: `_openWorkoutMenu` and `_openBlockMenu` in active_session_screen.dart, `_pickGoal` in profile_screen.dart, and the old tests.
  - A selected row draws a trailing `Icon(WIcons.check, size: 20, color: tokens.accentText)`, and its row `Semantics` carries `selected: true`. Unselected rows carry no selected state (`Tristate.none`).
  - When `labelLocale` is set, the row is wrapped in an outer `Semantics(localeForSubtree: labelLocale)`. The row stays one semantics node, keyed under `sheet-action-$i`, that carries the label, locale, button, selected state and tap.
  - The `showWActionSheet` signature is unchanged. Rows keep `ValueKey('sheet-action-$i')` and the ≥56dp height.
  - One-line rows stay exactly 56dp at 1.0× and 2.0×. A two-line row grows (98dp at 2.0×).

The layout tests go in first, against the existing API (every row has an icon). That way their red on main is the real overflow and ellipsis, not a compile error. The selection and semantics tests follow in a second red step.

- [ ] **Step 1: Write the failing layout tests.** Replace `app/test/widgets/w_action_sheet_test.dart` with this complete file. The three existing tests are kept verbatim. New: `setUpAll(preloadAppFonts)`, the `sheetHost` and `open` helpers, and two tests.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/fit_label.dart';
import 'package:workout_tracker/widgets/w_action_sheet.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';
import '../support/screen_harness.dart' show setPhone;

void main() {
  late String? result;

  // Row widths and line counts depend on the real faces.
  setUpAll(preloadAppFonts);

  Widget host() => wrapL10n(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showWActionSheet<String>(context, title: 'Options', actions: const [
              WSheetAction(label: 'Add set', value: 'add', icon: Icons.add),
              WSheetAction(label: 'Move up', value: 'up', icon: Icons.north, enabled: false),
              WSheetAction(label: 'Remove', value: 'rm', icon: Icons.delete_outline, destructive: true),
            ]);
          },
          child: const Text('open'),
        ),
      ));

  // Builds [actions] under the app's localizations, so a German menu reads
  // as it does on device.
  Widget sheetHost(
    List<WSheetAction<String>> Function(AppLocalizations l) actions, {
    String title = 'Options',
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) =>
      MaterialApp(
        theme: theme ?? buildTheme(Brightness.dark, accents[0]),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showWActionSheet<String>(context,
                    title: title,
                    actions: actions(AppLocalizations.of(context)));
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() => result = null);

  testWidgets('returns the tapped action value', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result, 'rm');
    expect(find.text('Options'), findsNothing);
  });

  testWidgets('a disabled action does nothing', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Options'), findsOneWidget);
  });

  testWidgets('rows are at least 56dp tall', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Add set'), matching: find.byKey(const ValueKey('sheet-action-0')));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
  });

  // The live block menu's six rows outgrow the sheet's 9/16 height cap on a
  // short phone at large text: the rows scroll, the title stays put.
  testWidgets('six rows scroll under a pinned title at 320x640dp 2.0x de',
      (tester) async {
    setPhone(tester, width: 320, height: 640, textScale: 2.0);
    await tester.pumpWidget(sheetHost(
      locale: const Locale('de'),
      title: 'Bankdrücken',
      (l) => [
        WSheetAction(label: l.sessionAddSet, value: 'set', icon: WIcons.plus),
        WSheetAction(
            label: l.sessionAddWarmupSet, value: 'warmup', icon: WIcons.flame),
        WSheetAction(
            label: l.sessionMoveUp, value: 'up', icon: Icons.keyboard_arrow_up),
        WSheetAction(
            label: l.sessionMoveDown,
            value: 'down',
            icon: Icons.keyboard_arrow_down),
        WSheetAction(
            label: l.sessionReorderExercises,
            value: 'reorder',
            icon: Icons.drag_handle),
        WSheetAction(
            label: l.sessionRemoveExercise,
            value: 'remove',
            icon: WIcons.trash,
            destructive: true),
      ],
    ));
    await open(tester);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Bankdrücken'));
    final last = find.byKey(const ValueKey('sheet-action-5'));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    final rows = tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)))
        .position;
    expect(rows.pixels, greaterThan(0),
        reason: 'the rows should have scrolled to reach the last one');
    expect(tester.getRect(find.text('Bankdrücken')), title,
        reason: 'the title scrolled away with the rows');
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(result, 'remove');
  });

  // "Predeterminado del sistema" is the longest language-sheet label.
  testWidgets(
      'a long label wraps whole onto two lines inside a taller row at 320dp '
      '2.0x', (tester) async {
    setPhone(tester, width: 320, textScale: 2.0);
    await tester.pumpWidget(sheetHost(
      locale: const Locale('es'),
      (_) => const [
        WSheetAction(
            label: 'Predeterminado del sistema',
            value: 'system',
            icon: WIcons.globe),
        WSheetAction(label: 'Español', value: 'es', icon: WIcons.globe),
      ],
    ));
    await open(tester);
    expect(tester.takeException(), isNull);
    final label = find.text('Predeterminado del sistema');
    final p = tester.renderObject<RenderParagraph>(label);
    expect(p.didExceedMaxLines, isFalse, reason: 'the label is cut short');
    expect(
        tester
            .renderObject<RenderFitLabel>(
                find.ancestor(of: label, matching: find.byType(FitLabel)))
            .ellipsized,
        isFalse);
    final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(p.size.height, greaterThan(line * 1.5),
        reason: 'the label should wrap onto a second line');
    expectNoSplitWords(tester, within: label);
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(find.byKey(ValueKey('sheet-action-$i'))).height,
          greaterThanOrEqualTo(56),
          reason: 'row $i');
    }
    final row = tester.getRect(find.byKey(const ValueKey('sheet-action-0')));
    final text = tester.getRect(label);
    expect(text.top, greaterThanOrEqualTo(row.top));
    expect(text.bottom, lessThanOrEqualTo(row.bottom),
        reason: 'the second line spills out of its row');
  });
}
```

- [ ] **Step 2: Run them to verify they fail.**
  - Run: `timeout 900 make -C app test TEST=test/widgets/w_action_sheet_test.dart > /tmp/claude-1000/sheet-red1.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error|Expected|Actual|cut short" /tmp/claude-1000/sheet-red1.log | tail -8`
  - Expected: EXIT=2 and `+3 -2: Some tests failed`, with these two failures:
    - `six rows scroll under a pinned title at 320x640dp 2.0x de`: `Expected: null  Actual: FlutterError:<A RenderFlex overflowed by 66 pixels on the bottom.>`
    - `a long label wraps whole onto two lines…`: `Expected: false  Actual: <true>`, with the reason `the label is cut short`.

- [ ] **Step 3: Write the failing selection and semantics tests.** In `app/test/widgets/w_action_sheet_test.dart`, add this import as the file's first line, above `import 'package:flutter/material.dart';`:

```dart
import 'dart:ui' show Tristate;

```

Then append these two tests at the end of `main()`, after the `'a long label wraps whole onto two lines inside a taller row at 320dp 2.0x'` test and before the closing `}`:

```dart
  testWidgets('the current choice carries a trailing check in the accent text colour',
      (tester) async {
    final tokens = WorkoutTokens.light(accents[3]);
    // Only the light theme separates the two: in the dark one they're equal.
    expect(tokens.accentText, isNot(tokens.accent));
    await tester.pumpWidget(sheetHost(
      theme: buildTheme(Brightness.light, accents[3]),
      (_) => const [
        WSheetAction(label: 'Cut', value: 'cut', icon: WIcons.target),
        WSheetAction(
            label: 'Bulk', value: 'bulk', icon: WIcons.target, selected: true),
        WSheetAction(label: 'Maintain', value: 'maintain', icon: WIcons.target),
      ],
    ));
    await open(tester);
    final check = find.byIcon(WIcons.check);
    expect(check, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('sheet-action-1')), matching: check),
        findsOneWidget);
    final icon = tester.widget<Icon>(check);
    expect(icon.color, tokens.accentText);
    expect(icon.size, 20);
    expect(tester.getRect(check).left,
        greaterThan(tester.getRect(find.text('Bulk')).right),
        reason: 'the check should trail the label');
    expect(find.byIcon(WIcons.target), findsNWidgets(3),
        reason: 'the selected row keeps its own icon');
  });

  // One node per row carries the label, its language, the button role, the
  // selected state and the tap, so TalkBack reads "Deutsch" in German on the
  // node it focuses.
  testWidgets('each row is one semantics node with its label, language, state and tap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const List<({String label, String? code})> rows = [
      (label: 'System default', code: null),
      (label: 'English', code: 'en'),
      (label: 'Italiano', code: 'it'),
      (label: 'Deutsch', code: 'de'),
      (label: 'Español', code: 'es'),
    ];
    await tester.pumpWidget(sheetHost((_) => [
          for (final r in rows)
            WSheetAction(
              label: r.label,
              value: r.code ?? 'system',
              labelLocale: r.code == null ? null : Locale(r.code!),
              selected: r.code == 'de',
            ),
        ]));
    await open(tester);
    for (var i = 0; i < rows.length; i++) {
      final code = rows[i].code;
      final d = tester
          .getSemantics(find.byKey(ValueKey('sheet-action-$i')))
          .getSemanticsData();
      expect(d.label, rows[i].label, reason: 'row $i');
      expect(d.flagsCollection.isButton, isTrue, reason: 'row $i');
      expect(d.hasAction(SemanticsAction.tap), isTrue, reason: 'row $i');
      expect(d.locale, code == null ? isNull : Locale(code), reason: 'row $i');
      expect(d.flagsCollection.isSelected,
          code == 'de' ? Tristate.isTrue : Tristate.none,
          reason: 'row $i');
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('sheet-action-1')),
            matching: find.byType(Icon)),
        findsNothing,
        reason: 'a row without an icon draws none');
    semantics.dispose();
  });
```

- [ ] **Step 4: Run them to verify they fail.**
  - Run: `timeout 900 make -C app test TEST=test/widgets/w_action_sheet_test.dart > /tmp/claude-1000/sheet-red2.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/sheet-red2.log | tail -5`
  - Expected: EXIT=2 with two compile errors: `Error: No named parameter with the name 'selected'.` and `Error: No named parameter with the name 'labelLocale'.`

- [ ] **Step 5: Implement.** Replace `app/lib/widgets/w_action_sheet.dart` with this complete file:

```dart
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'fit_label.dart';

/// One row in a [showWActionSheet].
class WSheetAction<T> {
  const WSheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.selected = false,
    this.labelLocale,
  });

  final String label;
  final T value;

  /// The leading icon; a row without one is text only.
  final IconData? icon;
  final bool destructive;
  final bool enabled;

  /// The current choice: a trailing check, and a selected semantics state.
  final bool selected;

  /// The language [label] is written in, when it isn't the UI's (a language
  /// named in its own language), so a screen reader voices it in that one.
  final Locale? labelLocale;
}

/// Tokens-styled bottom action sheet: a small caps [title] over 56dp rows.
/// Returns the tapped action's value, or null on dismiss. Disabled rows render
/// faint and ignore taps. The title stays put and the rows scroll when they
/// outgrow the sheet (a six-row menu on a short phone at large text).
Future<T?> showWActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<WSheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _WActionSheetBody<T>(title: title, actions: actions),
  );
}

class _WActionSheetBody<T> extends StatelessWidget {
  const _WActionSheetBody({required this.title, required this.actions});

  final String title;
  final List<WSheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.radius),
          border: Border.all(color: tokens.lineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Text(
                title,
                style: WorkoutType.mono(
                    size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      _row(context, tokens, i, actions[i]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WorkoutTokens tokens, int i, WSheetAction<T> a) {
    final color = !a.enabled
        ? tokens.line
        : a.destructive
            ? tokens.danger
            : tokens.text;
    final icon = a.icon;
    final row = Semantics(
      button: true,
      enabled: a.enabled,
      selected: a.selected ? true : null,
      child: GestureDetector(
        key: ValueKey('sheet-action-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: a.enabled ? () => Navigator.of(context).pop(a.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          // The vertical inset only shows on a two-line label: one line stays
          // under the 56dp floor up to 2.0x text.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: FitLabel(
                    a.label,
                    maxLines: 2,
                    style: WorkoutType.body(size: 15, weight: FontWeight.w600, color: color),
                  ),
                ),
                if (a.selected) ...[
                  const SizedBox(width: 14),
                  Icon(WIcons.check, size: 20, color: tokens.accentText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // A separate outer node only sets the language: on the row's own
    // Semantics it would split the tap off the button.
    final locale = a.labelLocale;
    return locale == null ? row : Semantics(localeForSubtree: locale, child: row);
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass.** This runs the sheet test, every test that opens a live-workout menu, and the live layout sweep.
  - Run: `timeout 900 make -C app test TEST="test/widgets/w_action_sheet_test.dart test/session/session_header_test.dart test/session/log_set_bar_test.dart test/session/reorder_exercises_sheet_test.dart test/session/exercise_block_edit_test.dart test/session/resume_test.dart test/session/active_session_screen_test.dart test/layout/live_layout_test.dart" > /tmp/claude-1000/sheet-green.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/sheet-green.log | tail -5`
  - Expected: EXIT=0 and `+108: All tests passed!` (w_action_sheet_test alone is +7).

- [ ] **Step 7: Analyze.** Run `make -C app analyze > /tmp/claude-1000/sheet-analyze.log 2>&1; echo EXIT=$?`. Expected: EXIT=0 and "No issues found!".

- [ ] **Step 8: Commit.**
  - `git add app/lib/widgets/w_action_sheet.dart app/test/widgets/w_action_sheet_test.dart`
  - `git commit -m "fix(app): mark the current choice in action sheets and let long menus scroll"`

### Task 9: Language sheet shows each language in its own name

**Files:**
- Create: `app/lib/settings/app_languages.dart`
- Modify: `app/lib/ui/profile_screen.dart`:
  - the imports: add `../settings/app_languages.dart` after `../l10n/app_localizations.dart`;
  - `_ProfileScreenState._languageLabel` and `_ProfileScreenState._pickLanguage`, both under `// ── Language picker`;
  - `_ProfileScreenState._pickGoal`, the `WSheetAction` inside it.
- Modify: `app/lib/l10n/app_en.arb`, `app_it.arb`, `app_de.arb` and `app_es.arb`. Delete `languageEnglish`, `languageItalian`, `languageGerman` and `languageSpanish`, just below `"@@locale"`.
- Modify: `app/l10n.yaml` (append `preferred-supported-locales`)
- Test: `app/test/l10n/locale_fallback_test.dart` (create)
- Test: `app/test/ui/profile_pickers_test.dart` (create)
- Test: `app/test/settings/app_languages_test.dart` (create)

**Interfaces:**
- Consumes (from Task 8):
  - `WSheetAction({…, IconData? icon, bool selected = false, Locale? labelLocale})`
  - `showWActionSheet<T>(BuildContext, {required String title, required List<WSheetAction<T>> actions})`
  - rows keyed `ValueKey('sheet-action-$i')`
  - a selected row draws a trailing `WIcons.check`, and its node has `isSelected == Tristate.isTrue`.
- Produces:
  - `const List<({String code, String name})> appLanguages`: the endonym table in sheet order (en English, it Italiano, de Deutsch, es Español).
  - `Future<String?> showLanguageSheet(BuildContext context, {required String? current})`.
    - It returns a language code, `'system'` for the system row, or null on dismiss.
    - Row 0 is `l.languageSystem`, with no `labelLocale`. Rows 1–4 follow `appLanguages`, each with `labelLocale: Locale(code)`.
    - The row for `current` is selected, or row 0 when `current` is null. An unknown code selects nothing.
    - Rows have no icon.
  - `AppLocalizations.supportedLocales` becomes `[en, de, es, it]`.
  - `AppLocalizations.languageEnglish`, `languageItalian`, `languageGerman` and `languageSpanish` are removed. `languageSystem` and `settingsLanguage` stay.
- Anchors other areas may shift: other tasks add keys to the ARBs and edit `_buildProfileHeader` and `_ProfileScreenState.initState` in profile_screen.dart. The edits below are anchored on the `"@@locale"` lines, the `// ── Language picker` block and `_pickGoal`. None of those tasks touch them.

- [ ] **Step 1: Write the failing tests that compile on main.** Create `app/test/l10n/locale_fallback_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';

void main() {
  // Flutter falls back to the first supported locale, and gen_l10n sorts
  // them alphabetically unless told otherwise: "System default" on a device
  // with no app language showed German while the notifications were English.
  test('English is the first supported locale', () {
    expect(AppLocalizations.supportedLocales.first, const Locale('en'));
  });

  test('a device with no supported language falls back to English', () {
    expect(
        basicLocaleListResolution(
            const [Locale('fr', 'FR')], AppLocalizations.supportedLocales),
        const Locale('en'));
  });
}
```

Create `app/test/ui/profile_pickers_test.dart`:

```dart
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  Future<void> pumpProfile(WidgetTester tester, Locale locale) async {
    setPhone(tester, width: 412);
    await tester.pumpWidget(harness.wrap(
        ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
        locale: locale));
    await settleReal(tester);
  }

  Finder sheetRow(int i) => find.byKey(ValueKey('sheet-action-$i'));

  testWidgets('the goal sheet checks the current goal after its label and '
      'keeps every target icon', (tester) async {
    final semantics = tester.ensureSemantics();
    await harness.open(tester, prefs: {'settings.bodyweight_goal': 'bulk'});
    await pumpProfile(tester, const Locale('en'));
    final goalRow = find.text('Goal');
    await scrollIntoView(tester, find.byType(ProfileScreen), goalRow);
    await tester.tap(goalRow);
    await settleUntilFound(tester, sheetRow(2), where: 'goal sheet');
    await settleReal(tester, ticks: 10);
    // Rows follow BodyweightGoal.values: cut, bulk, maintain.
    final check = find.descendant(
        of: find.byType(BottomSheet), matching: find.byIcon(WIcons.check));
    expect(check, findsOneWidget);
    expect(find.descendant(of: sheetRow(1), matching: check), findsOneWidget);
    expect(
        tester.getRect(check).left,
        greaterThan(tester
            .getRect(find.descendant(of: sheetRow(1), matching: find.text('Bulk')))
            .right),
        reason: 'the check should trail the label');
    for (var i = 0; i < 3; i++) {
      expect(find.descendant(of: sheetRow(i), matching: find.byIcon(WIcons.target)),
          findsOneWidget,
          reason: 'row $i');
      expect(
          tester.getSemantics(sheetRow(i)).getSemanticsData().flagsCollection.isSelected,
          i == 1 ? Tristate.isTrue : Tristate.none,
          reason: 'row $i');
    }
    semantics.dispose();
    await harness.unmount(tester);
  });

  // In English this passed before: the en ARB happened to hold endonyms.
  testWidgets('in an Italian UI the language sheet and row name German '
      '"Deutsch"', (tester) async {
    await harness.open(tester);
    await pumpProfile(tester, const Locale('it'));
    final languageRow = find.text('Lingua');
    await scrollIntoView(tester, find.byType(ProfileScreen), languageRow);
    expect(find.text('Predefinita di sistema'), findsOneWidget);
    await tester.tap(languageRow);
    await settleUntilFound(tester, find.text('Italiano'), where: 'language picker');
    // Let the sheet finish sliding in, so the tap lands on its row.
    await settleReal(tester, ticks: 10);
    expect(find.text('Tedesco'), findsNothing);
    await tester.tap(find.text('Deutsch'));
    await settleReal(tester, ticks: 10);
    expect(harness.settings.localeOverride, 'de');
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Deutsch'), findsOneWidget,
        reason: 'the Language row should name the choice in its own language');
    expect(find.text('Tedesco'), findsNothing);
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 2: Run them to verify they fail.**
  - Run: `timeout 900 make -C app test TEST="test/l10n/locale_fallback_test.dart test/ui/profile_pickers_test.dart" > /tmp/claude-1000/language-red1.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Expected|Actual|should" /tmp/claude-1000/language-red1.log | tail -12`
  - Expected: EXIT=2 and `+0 -4: Some tests failed`, with these four failures:
    - `English is the first supported locale`: `Expected: Locale:<en>  Actual: Locale:<de>`
    - `a device with no supported language falls back to English`: `Expected: Locale:<en>  Actual: Locale:<de>`
    - the goal sheet: `Expected: a value greater than <381.0>  Actual: <31.0>`, with the reason `the check should trail the label`. Main swaps the leading icon for the check.
    - the Italian language test: `Expected: no matching candidates  Actual: _TextWidgetFinder:<Found 1 widget with text "Tedesco"…`

- [ ] **Step 3: Write the failing `showLanguageSheet` tests.** Create `app/test/settings/app_languages_test.dart`:

```dart
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/settings/app_languages.dart';
import 'package:workout_tracker/theme/icons.dart';

import '../support/l10n_harness.dart';

void main() {
  test('the language table covers exactly the supported locales', () {
    expect(appLanguages.map((lang) => lang.code).toSet(),
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet());
  });

  late String? result;
  late bool closed;

  Widget host({required String? current, Locale locale = const Locale('en')}) =>
      wrapL10n(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLanguageSheet(context, current: current);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
        locale: locale,
      );

  setUp(() {
    result = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder row(int i) => find.byKey(ValueKey('sheet-action-$i'));
  Finder checkIn(Finder f) =>
      find.descendant(of: f, matching: find.byIcon(WIcons.check));

  const systemLabels = {
    'en': 'System default',
    'it': 'Predefinita di sistema',
    'de': 'Systemstandard',
    'es': 'Predeterminado del sistema',
  };

  for (final MapEntry(key: code, value: system) in systemLabels.entries) {
    testWidgets('in a $code UI each language is named in its own language',
        (tester) async {
      await tester.pumpWidget(host(current: code, locale: Locale(code)));
      await open(tester);
      final labels = [system, 'English', 'Italiano', 'Deutsch', 'Español'];
      for (var i = 0; i < labels.length; i++) {
        expect(find.descendant(of: row(i), matching: find.text(labels[i])),
            findsOneWidget,
            reason: 'row $i');
      }
      expect(row(labels.length), findsNothing);
      for (final translated in ['Tedesco', 'Englisch', 'Inglés']) {
        expect(find.text(translated), findsNothing);
      }
      final current = 1 + appLanguages.indexWhere((lang) => lang.code == code);
      expect(find.byIcon(WIcons.check), findsOneWidget);
      expect(checkIn(row(current)), findsOneWidget,
          reason: 'the current language should be checked');
    });
  }

  testWidgets('with no override the system row is checked', (tester) async {
    await tester.pumpWidget(host(current: null));
    await open(tester);
    expect(find.byIcon(WIcons.check), findsOneWidget);
    expect(checkIn(row(0)), findsOneWidget);
  });

  testWidgets('an unknown stored override checks nothing', (tester) async {
    await tester.pumpWidget(host(current: 'fr'));
    await open(tester);
    expect(row(4), findsOneWidget);
    expect(find.byIcon(WIcons.check), findsNothing);
  });

  testWidgets('each language row tells a screen reader its language',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(current: 'de', locale: const Locale('it')));
    await open(tester);
    const codes = [null, 'en', 'it', 'de', 'es'];
    for (var i = 0; i < codes.length; i++) {
      final code = codes[i];
      final d = tester.getSemantics(row(i)).getSemanticsData();
      expect(d.locale, code == null ? isNull : Locale(code), reason: 'row $i');
      expect(d.flagsCollection.isSelected,
          code == 'de' ? Tristate.isTrue : Tristate.none,
          reason: 'row $i');
    }
    semantics.dispose();
  });

  testWidgets('a tap returns the language code, and "system" for the system row',
      (tester) async {
    await tester.pumpWidget(host(current: null));
    await open(tester);
    await tester.tap(row(3));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, 'de');
    closed = false;
    await open(tester);
    await tester.tap(row(0));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, 'system');
  });

  testWidgets('a tap on the barrier returns null', (tester) async {
    await tester.pumpWidget(host(current: 'it'));
    await open(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    expect(row(0), findsNothing);
  });
}
```

- [ ] **Step 4: Run it to verify it fails.**
  - Run: `timeout 900 make -C app test TEST=test/settings/app_languages_test.dart > /tmp/claude-1000/language-red2.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/language-red2.log | head -4`
  - Expected: EXIT=2 with these compile errors:
    - `Error when reading 'lib/settings/app_languages.dart': No such file or directory`
    - `Undefined name 'appLanguages'.`
    - `Method not found: 'showLanguageSheet'.`

- [ ] **Step 5: Implement the language table and sheet.** Create `app/lib/settings/app_languages.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../widgets/w_action_sheet.dart';

/// The app's languages, each named in its own language (an Italian UI still
/// lists "Deutsch"), in the order the language sheet shows them.
const appLanguages = [
  (code: 'en', name: 'English'),
  (code: 'it', name: 'Italiano'),
  (code: 'de', name: 'Deutsch'),
  (code: 'es', name: 'Español'),
];

/// Asks for the app language, checking [current] (the stored override, null
/// for the system default). Returns a language code, `'system'` for the
/// system default (null already means dismissed), or null on dismiss.
Future<String?> showLanguageSheet(BuildContext context,
    {required String? current}) {
  final l = AppLocalizations.of(context);
  return showWActionSheet<String>(context,
      title: l.settingsLanguage,
      actions: [
        WSheetAction(
            label: l.languageSystem, value: 'system', selected: current == null),
        for (final lang in appLanguages)
          WSheetAction(
            label: lang.name,
            value: lang.code,
            labelLocale: Locale(lang.code),
            selected: lang.code == current,
          ),
      ]);
}
```

- [ ] **Step 6: Wire the Profile screen.** In `app/lib/ui/profile_screen.dart`:

Imports, old:
```dart
import '../l10n/app_localizations.dart';
import '../settings/bodyweight_goal.dart';
```
new:
```dart
import '../l10n/app_localizations.dart';
import '../settings/app_languages.dart';
import '../settings/bodyweight_goal.dart';
```

Under `// ── Language picker ───…`, replace the whole of `_languageLabel` and `_pickLanguage`. Old:
```dart
  String _languageLabel(BuildContext context, String? code) {
    final l = AppLocalizations.of(context);
    switch (code) {
      case 'en':
        return l.languageEnglish;
      case 'it':
        return l.languageItalian;
      case 'de':
        return l.languageGerman;
      case 'es':
        return l.languageSpanish;
      default:
        return l.languageSystem;
    }
  }

  Future<void> _pickLanguage(
      BuildContext context, SettingsService settings) async {
    final l = AppLocalizations.of(context);
    // showWDialog returns null both on barrier-dismiss AND for a null action
    // value, so "System default" carries a non-null 'system' sentinel and a
    // real null means dismissed (no change).
    final choice = await showWDialog<String>(
      context,
      title: l.settingsLanguage,
      message: '',
      actions: [
        WDialogAction(label: l.languageSystem, value: 'system'),
        WDialogAction(label: l.languageEnglish, value: 'en'),
        WDialogAction(label: l.languageItalian, value: 'it'),
        WDialogAction(label: l.languageGerman, value: 'de'),
        WDialogAction(label: l.languageSpanish, value: 'es'),
      ],
    );
    if (choice == null) return; // dismissed
    await settings.setLocaleOverride(choice == 'system' ? null : choice);
  }
```
new:
```dart
  // The language in its own name, as the sheet lists it; null, or a code the
  // UI can't write, reads as the system default.
  String _languageLabel(BuildContext context, String? code) {
    for (final lang in appLanguages) {
      if (lang.code == code) return lang.name;
    }
    return AppLocalizations.of(context).languageSystem;
  }

  Future<void> _pickLanguage(
      BuildContext context, SettingsService settings) async {
    final choice =
        await showLanguageSheet(context, current: settings.localeOverride);
    if (choice == null) return; // dismissed
    await settings.setLocaleOverride(choice == 'system' ? null : choice);
  }
```

In `_pickGoal`, old:
```dart
              icon: g == settings.bodyweightGoal ? WIcons.check : WIcons.target,
            ),
```
new:
```dart
              icon: WIcons.target,
              selected: g == settings.bodyweightGoal,
            ),
```

Keep the `../widgets/w_dialog.dart` import: `showWConfirm` still uses it.

- [ ] **Step 7: Delete the translated language names and put English first.** In each ARB, delete the four lines right under `"@@locale"`. None of them has `@` metadata.

`app/lib/l10n/app_en.arb`, delete:
```json
  "languageEnglish": "English",
  "languageItalian": "Italiano",
  "languageGerman": "Deutsch",
  "languageSpanish": "Español",
```
`app/lib/l10n/app_it.arb`, delete:
```json
  "languageEnglish": "Inglese",
  "languageItalian": "Italiano",
  "languageGerman": "Tedesco",
  "languageSpanish": "Spagnolo",
```
`app/lib/l10n/app_de.arb`, delete:
```json
  "languageEnglish": "Englisch",
  "languageItalian": "Italienisch",
  "languageGerman": "Deutsch",
  "languageSpanish": "Spanisch",
```
`app/lib/l10n/app_es.arb`, delete:
```json
  "languageEnglish": "Inglés",
  "languageItalian": "Italiano",
  "languageGerman": "Alemán",
  "languageSpanish": "Español",
```
After this, each file starts `{`, then `"@@locale": "<code>",`, then `"languageSystem": …`.

Append to `app/l10n.yaml`, after `nullable-getter: false`:
```yaml
# Flutter falls back to the first supported locale; without this gen_l10n
# sorts them, and a device with no app language got German.
preferred-supported-locales: [en]
```

Regenerate the gitignored l10n:
- Run: `make -C app get > /tmp/claude-1000/language-get.log 2>&1; echo EXIT=$?`
- Expected: EXIT=0.
- Check: `grep -n "supportedLocales = " -A5 app/lib/l10n/app_localizations.dart` lists `Locale('en')` first, then de, es, it.

- [ ] **Step 8: Run the tests to verify they pass.** This runs the three new files, the sheet test, ARB parity, and every Profile test (the layout sweep and row layouts) that the sub-label and goal-sheet change can reach.
  - Run: `timeout 900 make -C app test TEST="test/settings/app_languages_test.dart test/l10n/locale_fallback_test.dart test/ui/profile_pickers_test.dart test/widgets/w_action_sheet_test.dart test/l10n/arb_parity_test.dart test/settings/locale_override_test.dart test/ui/profile_layout_test.dart test/layout/profile_layout_test.dart test/ui/plan_profile_layout_test.dart test/main_routing_test.dart" > /tmp/claude-1000/language-green.log 2>&1; echo EXIT=$?`
  - Then: `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/language-green.log | tail -5`
  - Expected: EXIT=0 and `+62: All tests passed!`.

- [ ] **Step 9: Analyze.** Run `make -C app analyze > /tmp/claude-1000/language-analyze.log 2>&1; echo EXIT=$?`. Expected: EXIT=0 and "No issues found!". Analyze covers `test/` too, so this also proves that no file still uses a deleted getter.

- [ ] **Step 10: Commit.**
  - `git add app/lib/settings/app_languages.dart app/lib/ui/profile_screen.dart app/lib/l10n/app_en.arb app/lib/l10n/app_it.arb app/lib/l10n/app_de.arb app/lib/l10n/app_es.arb app/l10n.yaml app/test/l10n/locale_fallback_test.dart app/test/ui/profile_pickers_test.dart app/test/settings/app_languages_test.dart`
  - `git commit -m "fix(app): name each language in its own language and fall back to English"`


### Task 10: Profile shows the user's real training history

**Files:**
- Modify: `app/lib/data/stats_repository.dart` (`StatsRepository`: new `watchTrainingSummary()` inserted between `lastTrainedExerciseId()` and the `// ── List streams` banner)
- Modify: `app/lib/util/dates.dart` (new top-level `fmtMonthYear` after `fmtDate`)
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_it.arb`, `app/lib/l10n/app_de.arb`, `app/lib/l10n/app_es.arb` (the `"profileTrainingSince"` line; new `profileSplitDays`)
- Modify: `app/lib/ui/profile_screen.dart` (imports; new top-level `profileTrainingLine` above the `// ── ProfileScreen ──` banner; the `ProfileScreen` doc bullet list; `_ProfileScreenState` fields, `initState`, `dispose`; `_buildProfileHeader`)
- Test: `app/test/data/stats_repository_integration_test.dart` (modify: new `watchTrainingSummary` group)
- Test: `app/test/util/dates_test.dart` (modify: three `fmtMonthYear` tests)
- Test: `app/test/ui/profile_training_line_test.dart` (create: pure)
- Test: `app/test/ui/profile_header_test.dart` (create: real DB through ScreenHarness)
- Test: `app/test/layout/profile_layout_test.dart` (modify: wait for the line, plus an es case)

**Interfaces:**
- Consumes: nothing new. Other areas' tasks also edit `profile_screen.dart`:
  - the language-picker task changes `_languageLabel` / `_pickLanguage` and the goal picker;
  - the lb-formatter task switches `_QuickStats`' bodyweight text to `fmtBw`.
- They also edit the ARBs: the language-picker task deletes the `language*` keys, and the discard task adds the `planDiscard*` keys.
- None of the anchors below overlap those edits. Every anchor is a unique literal that is still there after them:
  - the `profileTrainingSince` ARB line;
  - the `dart:io`, `session_repository` and `update_ui` imports;
  - the `// ── ProfileScreen ──` banner;
  - `_ProfileScreenState`, from its `_version` field through `dispose`;
  - `_buildProfileHeader`.
- No other task edits `test/layout/profile_layout_test.dart`, `test/util/dates_test.dart` or `test/data/stats_repository_integration_test.dart`.
- Produces:
  - `Stream<({String? firstSessionDate, int dayCount})> StatsRepository.watchTrainingSummary()` (re-listenable, `triggerOnTables: ['sessions', 'day_templates']`)
  - `String? fmtMonthYear(String? iso, String localeName)` in `app/lib/util/dates.dart`
  - `String? profileTrainingLine(AppLocalizations l, String localeName, {String? firstSessionDate, int? dayCount})`, top-level in `app/lib/ui/profile_screen.dart`
  - ARB messages `String profileTrainingSince(String month)` and `String profileSplitDays(int count)`
  - the widget key `Key('profile-training-line')` on the header's line `Text`

**Accepted spec deviation, data test (e):** the spec says test (e) "proves `triggerOnTables`". On the pinned powersync 2.2.0 / sqlite_async 0.14.2, no behaviour test can prove that:
- PowerSync infers both tables from the query plan through the scalar subqueries.
- With the parameter removed, (e) still passes.
- What (e) does catch is an explicit list that leaves `day_templates` out. With `const ['sessions']`, it fails with `TimeoutException after 0:00:05`.
- The explicit `triggerOnTables: ['sessions', 'day_templates']` stays, as the spec requires. Read (e) as a pin on the days-only re-emit, not as a guard that the parameter is present.

- [ ] **Step 1: Write the failing data tests**

In `app/test/data/stats_repository_integration_test.dart`, add `dart:async` above the `dart:io` import:

```dart
import 'dart:async';
import 'dart:io';
```

Replace the file's doc line `/// [StatsRepository.lastTrainedExerciseId] against a REAL PowerSync database.` with:

```dart
/// [StatsRepository.lastTrainedExerciseId] and
/// [StatsRepository.watchTrainingSummary] against a REAL PowerSync database.
```

Then replace the last test and `main`'s closing brace:

```dart
  test('ties within the same session break on the highest set number', () async {
    await seedSession('s1', '2026-09-01');
    await seedSet('a1', 's1', 'squat', 1);
    await seedSet('a2', 's1', 'bench', 2);
    expect(await repo.lastTrainedExerciseId(), 'bench');
  });
}
```

with:

```dart
  test('ties within the same session break on the highest set number', () async {
    await seedSession('s1', '2026-09-01');
    await seedSet('a1', 's1', 'squat', 1);
    await seedSet('a2', 's1', 'bench', 2);
    expect(await repo.lastTrainedExerciseId(), 'bench');
  });

  group('watchTrainingSummary', () {
    Future<void> seedDay(String id, int? isTemplate) => db.execute(
        'INSERT INTO day_templates (id, name, position, is_template) '
        'VALUES (?, ?, 0, ?)',
        [id, 'Day $id', isTemplate]);

    test('counts only owned days: a template day sits next to its absorbed '
        'copy, and a NULL flag counts as owned', () async {
      await seedDay('tpl', 1);
      await seedDay('copy', 0);
      await seedDay('legacy', null);
      final summary = await repo.watchTrainingSummary().first;
      expect(summary.dayCount, 2);
    });

    test('an empty database emits no date and no days', () async {
      expect(await repo.watchTrainingSummary().first,
          (firstSessionDate: null, dayCount: 0));
    });

    test('sessions inserted out of date order give the earliest date',
        () async {
      await seedSession('s2', '2026-05-02');
      await seedSession('s1', '2026-03-14');
      await seedSession('s3', '2026-04-20');
      final summary = await repo.watchTrainingSummary().first;
      expect(summary.firstSessionDate, '2026-03-14');
    });

    test('one stream can be listened to twice', () async {
      await seedSession('s1', '2026-03-14');
      final stream = repo.watchTrainingSummary();
      final first = await stream.first; // listens, then cancels
      final second = await stream.first; // re-listens
      expect(first.firstSessionDate, '2026-03-14');
      expect(second.firstSessionDate, '2026-03-14');
    });

    // PowerSync also infers both tables from the query plan, so this passes
    // with or without triggerOnTables; it fails if an explicit list leaves
    // day_templates out. The listen can still catch the seeding write's late
    // notification and re-emit the old count first, so skip emissions until
    // the count moves.
    test('a change to day_templates alone re-emits with one more day',
        () async {
      await seedSession('s1', '2026-03-14');
      await seedDay('d1', 0);
      final emissions = StreamIterator(repo.watchTrainingSummary());
      addTearDown(emissions.cancel);
      expect(await emissions.moveNext(), isTrue);
      expect(emissions.current, (firstSessionDate: '2026-03-14', dayCount: 1));
      await seedDay('d2', 0);
      do {
        expect(
            await emissions.moveNext().timeout(const Duration(seconds: 5)),
            isTrue);
      } while (emissions.current.dayCount == 1);
      expect(emissions.current, (firstSessionDate: '2026-03-14', dayCount: 2));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 900 make -C app test TEST=test/data/stats_repository_integration_test.dart > /tmp/claude-1000/profile-stats.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-stats.log | tail -5`

Expected: EXIT=2 with a compile error: `Error: The method 'watchTrainingSummary' isn't defined for the type 'StatsRepository'.`

- [ ] **Step 3: Implement `watchTrainingSummary`**

In `app/lib/data/stats_repository.dart`, replace:

```dart
    if (rs.isEmpty) return null;
    return rs.first['exercise_id'] as String?;
  }

  // ── List streams ──────────────────────────────────────────────────────────
```

with:

```dart
    if (rs.isEmpty) return null;
    return rs.first['exercise_id'] as String?;
  }

  // ── Profile header ────────────────────────────────────────────────────────

  /// First logged session date (YYYY-MM-DD, or null with no sessions) and the
  /// number of the user's own training days.
  ///
  /// The days filter `is_template IS NOT 1`, as `watchDays` does: synced
  /// template days stay in the local DB next to their absorbed copies, so a
  /// raw count would double them (NULL counts as owned). The query always
  /// returns exactly one row, so an empty DB emits `(null, 0)`.
  Stream<({String? firstSessionDate, int dayCount})> watchTrainingSummary() {
    // Both tables are named rather than left to PowerSync to infer from the
    // subqueries, so a days-only change always refreshes the line.
    return reListenable(() => db
        .watch(
          'SELECT (SELECT MIN(date) FROM sessions) AS first, '
          '(SELECT COUNT(*) FROM day_templates WHERE is_template IS NOT 1) AS days',
          triggerOnTables: const ['sessions', 'day_templates'],
        )
        .map((rs) => (
              firstSessionDate: rs.first['first'] as String?,
              dayCount: rs.first['days'] as int? ?? 0,
            )));
  }

  // ── List streams ──────────────────────────────────────────────────────────
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 make -C app test TEST=test/data/stats_repository_integration_test.dart > /tmp/claude-1000/profile-stats.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-stats.log | tail -5`

Expected: EXIT=0, `+9: All tests passed!`

- [ ] **Step 5: Write the failing tests for the line, its month and its rendering**

(a) In `app/test/util/dates_test.dart`, replace the end of the last test and `main`'s closing brace:

```dart
    expect(fmtDate('2026-05-31', 'en'), '31 May');
  });
}
```

with:

```dart
    expect(fmtDate('2026-05-31', 'en'), '31 May');
  });
  test('fmtMonthYear: the localized short month and the year', () {
    expect(fmtMonthYear('2026-03-14', 'en'), 'Mar 2026');
    expect(fmtMonthYear('2026-03-14', 'it'), 'mar 2026');
    expect(fmtMonthYear('2026-03-14', 'de'), 'März 2026');
    expect(fmtMonthYear('2026-03-14', 'es'), 'mar 2026');
    // The locale data's own abbreviations, kept as they are.
    expect(fmtMonthYear('2026-09-30', 'de'), 'Sept. 2026');
    expect(fmtMonthYear('2026-01-05', 'es'), 'ene 2026');
    expect(fmtMonthYear('2026-09-30', 'it'), 'set 2026');
  });
  test('fmtMonthYear: the first and last day stay in their month', () {
    expect(fmtMonthYear('2026-03-01', 'en'), 'Mar 2026');
    expect(fmtMonthYear('2026-03-31', 'en'), 'Mar 2026');
  });
  test('fmtMonthYear: null, empty or garbage gives null, never a throw', () {
    expect(fmtMonthYear(null, 'en'), isNull);
    expect(fmtMonthYear('', 'en'), isNull);
    expect(fmtMonthYear('garbage', 'en'), isNull);
  });
}
```

(b) Create `app/test/ui/profile_training_line_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

void main() {
  setUpAll(() async {
    // DateFormat for non-system locales needs the symbol tables loaded.
    await initializeDateFormatting();
  });

  for (final (code, since, split, oneDay) in [
    ('en', 'Training since Mar 2026', '4-day split', '1-day split'),
    ('it', 'Ti alleni da mar 2026', 'split di 4 giorni', 'split di 1 giorno'),
    ('de', 'Training seit März 2026', '4-Tage-Split', '1-Tag-Split'),
    ('es', 'Entrenando desde mar 2026', 'rutina de 4 días', 'rutina de 1 día'),
  ]) {
    group('profileTrainingLine ($code)', () {
      final l = lookupAppLocalizations(Locale(code));

      test('both parts, joined by a middle dot', () {
        expect(
            profileTrainingLine(l, code,
                firstSessionDate: '2026-03-14', dayCount: 4),
            '$since · $split');
      });

      test('a one-day split is singular', () {
        expect(
            profileTrainingLine(l, code,
                firstSessionDate: '2026-03-14', dayCount: 1),
            '$since · $oneDay');
      });

      test('no training days: "since" alone', () {
        expect(
            profileTrainingLine(l, code,
                firstSessionDate: '2026-03-14', dayCount: 0),
            since);
        expect(profileTrainingLine(l, code, firstSessionDate: '2026-03-14'),
            since);
      });

      test('no workouts: the split alone', () {
        expect(profileTrainingLine(l, code, dayCount: 4), split);
      });

      test('neither part: null, so the line is hidden', () {
        expect(profileTrainingLine(l, code), isNull);
        expect(profileTrainingLine(l, code, dayCount: 0), isNull);
      });

      test('a date that does not parse drops "since"', () {
        expect(
            profileTrainingLine(l, code,
                firstSessionDate: 'garbage', dayCount: 4),
            split);
        expect(
            profileTrainingLine(l, code, firstSessionDate: '', dayCount: 0),
            isNull);
      });
    });
  }
}
```

(c) Create `app/test/ui/profile_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

/// Two owned training days.
Future<void> seedTwoDays(PowerSyncDatabase d) async {
  await seedDay(d, 'd1', 'Upper', position: 0);
  await seedDay(d, 'd2', 'Lower', position: 1);
}

/// Two finished workouts on fixed dates, inserted latest first; the first
/// one is in March 2026.
Future<void> seedTwoSessions(PowerSyncDatabase d) async {
  await seedSession(d, 's2',
      date: DateTime(2026, 5, 2), label: 'Lower', sets: const []);
  await seedSession(d, 's1',
      date: DateTime(2026, 3, 14), label: 'Upper', sets: const []);
}

Future<void> seedDaysAndSessions(PowerSyncDatabase d) async {
  await seedTwoDays(d);
  await seedTwoSessions(d);
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  final line = find.byKey(const Key('profile-training-line'));
  String lineText(WidgetTester tester) => tester.widget<Text>(line).data!;

  Future<void> pumpProfile(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(harness.wrap(
        ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
        locale: locale));
  }

  testWidgets('shows the first workout month and the number of training days',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'Profile en');
    expect(lineText(tester), 'Training since Mar 2026 · 2-day split');
    await harness.unmount(tester);
  });

  testWidgets('reads in the UI language', (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester, locale: const Locale('de'));
    await settleUntilFound(tester, line, where: 'Profile de');
    expect(lineText(tester), 'Training seit März 2026 · 2-Tage-Split');
    await harness.unmount(tester);
  });

  testWidgets('a fresh install shows no line, and no made-up one',
      (tester) async {
    await harness.open(tester, seed: (_) async {});
    await pumpProfile(tester);
    await settleReal(tester);
    expect(line, findsNothing);
    expect(find.textContaining('Training since'), findsNothing);
    // The line is live, not stalled: the first training day brings it in.
    await tester.runAsync(
        () => seedDay(harness.database, 'd1', 'Upper', position: 0));
    await settleUntilFound(tester, line, where: 'after the first day');
    expect(lineText(tester), '1-day split');
    await harness.unmount(tester);
  });

  testWidgets('training days without a workout show the split alone',
      (tester) async {
    await harness.open(tester, seed: seedTwoDays);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'days only');
    expect(lineText(tester), '2-day split');
    await harness.unmount(tester);
  });

  testWidgets('workouts without a training day show "since" alone',
      (tester) async {
    await harness.open(tester, seed: seedTwoSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'sessions only');
    expect(lineText(tester), 'Training since Mar 2026');
    await harness.unmount(tester);
  });

  testWidgets('deleting the first workout moves "since" forward',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(
        tester, find.text('Training since Mar 2026 · 2-day split'),
        where: 'before the delete');
    await tester.runAsync(() =>
        harness.database.execute("DELETE FROM sessions WHERE id = 's1'"));
    await settleUntilFound(
        tester, find.text('Training since May 2026 · 2-day split'),
        where: 'after the delete');
    await harness.unmount(tester);
  });

  testWidgets('editing the name hides the line, and saving brings it back',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'before editing');
    await tester.tap(find.text('Athlete'));
    await settleReal(tester, ticks: 2);
    expect(line, findsNothing);
    await tester.tap(find.text('Save'));
    // No new query: the line comes back from the value already held.
    await settleReal(tester, ticks: 2);
    expect(lineText(tester), 'Training since Mar 2026 · 2-day split');
    await harness.unmount(tester);
  });
}
```

(d) Replace `app/test/layout/profile_layout_test.dart` with this complete file:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  // The header's training line comes from its own query: wait for it, or the
  // header is checked without its longest line. Never match on ' · ': the
  // sync status and the local-first hint contain it too.
  final trainingLine = find.byKey(const Key('profile-training-line'));

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('Profile holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
          locale: c.locale));
      await settleReal(tester);
      await settleUntilFound(tester, trainingLine, where: 'Profile $name');
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProfileScreen), 'Profile $name');
      await harness.unmount(tester);
    });

    // Signed in with sync on, offline, last synced 3h ago: the longest
    // sync status ("Offline · synchronisiert vor 3 Std").
    testWidgets('Profile signed in holds at $name', (tester) async {
      await harness.open(tester,
          prefs: syncOnPrefs,
          lastSyncedAt:
              DateTime.now().subtract(const Duration(hours: 3, minutes: 5)));
      setPhone(tester, width: c.width, textScale: c.textScale);
      final auth = await signedInAuth(tester);
      await tester.pumpWidget(harness.wrap(
          ProfileScreen(onClose: () {}, onLogout: () async {}, auth: auth),
          locale: c.locale));
      await settleReal(tester);
      await settleUntilFound(tester, trainingLine,
          where: 'Profile signed in $name');
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProfileScreen), 'Profile signed in $name');
      await harness.unmount(tester);
    });
  }

  // Spanish is not in the sweep's locales, and its training line is the
  // longest of the four ("Entrenando desde … · rutina de 3 días").
  testWidgets('Profile holds at 320dp 2.0x es', (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 320, textScale: 2.0);
    await tester.pumpWidget(harness.wrap(
        ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
        locale: const Locale('es')));
    await settleReal(tester);
    await settleUntilFound(tester, trainingLine, where: 'Profile 320dp 2.0x es');
    await expectLayoutHoldsWhileScrolling(
        tester, find.byType(ProfileScreen), 'Profile 320dp 2.0x es');
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 6: Run them to verify they fail**

Run each, then grep its log:
- `timeout 900 make -C app test TEST=test/util/dates_test.dart > /tmp/claude-1000/profile-dates.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-dates.log | tail -5`. Expected: EXIT=2 with `Error: Method not found: 'fmtMonthYear'.`
- `timeout 900 make -C app test TEST=test/ui/profile_training_line_test.dart > /tmp/claude-1000/profile-line.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-line.log | tail -5`. Expected: EXIT=2 with `Error: Method not found: 'profileTrainingLine'.`
- `timeout 900 make -C app test TEST=test/ui/profile_header_test.dart > /tmp/claude-1000/profile-header.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error|seeded content|containing" /tmp/claude-1000/profile-header.log | tail -12`. Expected: EXIT=2 and `+0 -7: Some tests failed.`
  - Six tests fail with `<where>: seeded content never rendered`, because the key `profile-training-line` is never built.
  - The fresh-install test fails with `Found 1 widget with text containing Training since`. That text is the fixed placeholder.
- `timeout 900 make -C app test TEST=test/layout/profile_layout_test.dart > /tmp/claude-1000/profile-layout.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/profile-layout.log | tail -3`. Expected: EXIT=2, `+0 -25: Some tests failed.`, and every case fails with `seeded content never rendered`. This run takes about 2.5 minutes, because each case waits out its 150 ticks.

- [ ] **Step 7: Implement the month formatter, the strings, the line and its rendering**

(a) In `app/lib/util/dates.dart`, replace the end of `fmtDate`:

```dart
  final pattern = weekday ? 'E d MMM' : 'd MMM';
  return DateFormat(pattern, localeName).format(d);
}
```

with:

```dart
  final pattern = weekday ? 'E d MMM' : 'd MMM';
  return DateFormat(pattern, localeName).format(d);
}

/// Formats an ISO date string as a localized short month and year
/// (en `'Mar 2026'`, de `'März 2026'`), or null for a null, empty or
/// unparseable [iso].
///
/// The date is read at local midnight, so no timezone shift can move it into
/// another month. It uses [DateTime.tryParse], never [DateTime.parse]: this
/// runs during build, where a throw renders the gray ErrorWidget.
String? fmtMonthYear(String? iso, String localeName) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse('${iso}T00:00:00');
  if (d == null) return null;
  return DateFormat.yMMM(localeName).format(d);
}
```

(b) ARBs. Replace the single `profileTrainingSince` line in each file.

`app/lib/l10n/app_en.arb`: `  "profileTrainingSince": "Training since Mar 2026 · 4-day split",` becomes:

```json
  "profileTrainingSince": "Training since {month}",
  "@profileTrainingSince": {
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "profileSplitDays": "{count, plural, =1{1-day split} other{{count}-day split}}",
  "@profileSplitDays": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
```

`app/lib/l10n/app_it.arb`: `  "profileTrainingSince": "Allenamenti da mar 2026 · split 4 giorni",` becomes:

```json
  "profileTrainingSince": "Ti alleni da {month}",
  "@profileTrainingSince": {"placeholders": {"month": {"type": "String"}}},
  "profileSplitDays": "{count, plural, =1{split di 1 giorno} other{split di {count} giorni}}",
```

`app/lib/l10n/app_de.arb`: `  "profileTrainingSince": "Training seit März 2026 · 4-Tage-Split",` becomes:

```json
  "profileTrainingSince": "Training seit {month}",
  "@profileTrainingSince": {"placeholders": {"month": {"type": "String"}}},
  "profileSplitDays": "{count, plural, =1{1-Tag-Split} other{{count}-Tage-Split}}",
```

`app/lib/l10n/app_es.arb`: `  "profileTrainingSince": "Entrenando desde mar 2026 · split de 4 días",` becomes:

```json
  "profileTrainingSince": "Entrenando desde {month}",
  "@profileTrainingSince": {"placeholders": {"month": {"type": "String"}}},
  "profileSplitDays": "{count, plural, =1{rutina de 1 día} other{rutina de {count} días}}",
```

(c) Regenerate l10n: `make -C app get > /tmp/claude-1000/profile-get.log 2>&1; echo EXIT=$?`. Expected: EXIT=0.

(d) `app/lib/ui/profile_screen.dart`:

Imports. Replace `import 'dart:io' show Platform;` with:

```dart
import 'dart:async';
import 'dart:io' show Platform;
```

Replace `import '../data/session_repository.dart';` with:

```dart
import '../data/session_repository.dart';
import '../data/stats_repository.dart';
```

Replace `import '../update/update_ui.dart';` with:

```dart
import '../update/update_ui.dart';
import '../util/dates.dart';
```

The pure line builder. Replace:

```dart
// ── ProfileScreen ─────────────────────────────────────────────────────────────

/// Full-screen Profile & Settings overlay, pushed on the root navigator.
```

with:

```dart
// ── Training line ─────────────────────────────────────────────────────────────

/// The Profile header's second line, or null to hide it.
///
/// "Since" is the month of the first logged workout, dropped when
/// [firstSessionDate] is null or doesn't parse; the split is the number of
/// the user's own training days, dropped when [dayCount] is null or 0.
String? profileTrainingLine(AppLocalizations l, String localeName,
    {String? firstSessionDate, int? dayCount}) {
  final month = fmtMonthYear(firstSessionDate, localeName);
  final parts = [
    if (month != null) l.profileTrainingSince(month),
    if (dayCount != null && dayCount > 0) l.profileSplitDays(dayCount),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

// ── ProfileScreen ─────────────────────────────────────────────────────────────

/// Full-screen Profile & Settings overlay, pushed on the root navigator.
```

The `ProfileScreen` doc. Replace:

```dart
///   • Editable profile name → SettingsService
///   • Quick stats (Sessions / PRs / Bodyweight) from the local DB
```

with:

```dart
///   • Editable profile name → SettingsService
///   • Training line (first workout month · training days) from the local DB
///   • Quick stats (Sessions / PRs / Bodyweight) from the local DB
```

`_ProfileScreenState`: the fields, the subscription and its cancel. Replace:

```dart
  // Runtime app version (footer; reused by the Updates group).
  String _version = '';

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _nameCtrl = TextEditingController(text: settings.profileName);
    _serverCtrl = TextEditingController(text: settings.serverUrl);
    _currentServerUrl = settings.serverUrl;
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }
```

with:

```dart
  // Runtime app version (footer; reused by the Updates group).
  String _version = '';

  // The header's training line data; null until the first value arrives, and
  // the header shows no line until then. Held here, not in the header: the
  // header is a ListView child swapped out while the name is edited, and a
  // stream it owned would re-query on every remount and make the line blink.
  ({String? firstSessionDate, int dayCount})? _training;
  StreamSubscription<({String? firstSessionDate, int dayCount})>? _trainingSub;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _nameCtrl = TextEditingController(text: settings.profileName);
    _serverCtrl = TextEditingController(text: settings.serverUrl);
    _currentServerUrl = settings.serverUrl;
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
    // onError hides the line rather than leaving it stale; the subscription
    // stays open, so the next emission brings it back.
    _trainingSub = StatsRepository(db).watchTrainingSummary().listen((t) {
      if (mounted) setState(() => _training = t);
    }, onError: (Object e, StackTrace st) {
      debugPrint('profile: training summary stream error: $e');
      if (mounted) setState(() => _training = null);
    });
  }

  @override
  void dispose() {
    _trainingSub?.cancel();
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }
```

`_buildProfileHeader`, the top. Replace:

```dart
  Widget _buildProfileHeader(SettingsService settings, WorkoutTokens tokens) {
    final l = AppLocalizations.of(context);
    return Row(
```

with:

```dart
  Widget _buildProfileHeader(SettingsService settings, WorkoutTokens tokens) {
    final l = AppLocalizations.of(context);
    final training = _training;
    final trainingLine = training == null
        ? null
        : profileTrainingLine(
            l,
            Localizations.localeOf(context).toLanguageTag(),
            firstSessionDate: training.firstSessionDate,
            dayCount: training.dayCount,
          );
    return Row(
```

`_buildProfileHeader`, the line itself. Replace:

```dart
              ] else ...[
                const SizedBox(height: 3),
                Text(
                  l.profileTrainingSince,
                  style: WorkoutType.mono(size: 11, color: tokens.faint),
                ),
              ],
```

with:

```dart
              ] else if (trainingLine != null) ...[
                const SizedBox(height: 3),
                Text(
                  trainingLine,
                  key: const Key('profile-training-line'),
                  style: WorkoutType.mono(size: 11, color: tokens.faint),
                ),
              ],
```

- [ ] **Step 8: Run the tests to verify they pass**

- `timeout 900 make -C app test TEST=test/data/stats_repository_integration_test.dart > /tmp/claude-1000/profile-stats.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-stats.log | tail -5`. Expected: EXIT=0, `+9: All tests passed!`
- `timeout 900 make -C app test TEST=test/util/dates_test.dart > /tmp/claude-1000/profile-dates.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-dates.log | tail -5`. Expected: EXIT=0, `+7: All tests passed!`
- `timeout 900 make -C app test TEST=test/ui/profile_training_line_test.dart > /tmp/claude-1000/profile-line.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-line.log | tail -5`. Expected: EXIT=0, `+24: All tests passed!`
- `timeout 900 make -C app test TEST=test/ui/profile_header_test.dart > /tmp/claude-1000/profile-header.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-header.log | tail -5`. Expected: EXIT=0, `+7: All tests passed!`
- `timeout 900 make -C app test TEST=test/layout/profile_layout_test.dart > /tmp/claude-1000/profile-layout.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-layout.log | tail -5`. Expected: EXIT=0, `+25: All tests passed!`
- Existing files the change can break: the other Profile mounts, ARB key parity and the re-listen guard. Run `timeout 900 make -C app test TEST="test/ui/profile_layout_test.dart test/ui/plan_profile_layout_test.dart test/l10n/arb_parity_test.dart test/data/repo_relisten_integration_test.dart" > /tmp/claude-1000/profile-neighbours.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-neighbours.log | tail -5`. Expected: EXIT=0, `+15: All tests passed!`
- Full suite: `timeout 900 make -C app test > /tmp/claude-1000/profile-full.log 2>&1; echo EXIT=$?` then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/profile-full.log | tail -5`. Expected: EXIT=0, `All tests passed!`

- [ ] **Step 9: Analyze**

`make -C app analyze > /tmp/claude-1000/profile-analyze.log 2>&1; echo EXIT=$?` then `grep -E "No issues found|issues? found" /tmp/claude-1000/profile-analyze.log`. Expected: "No issues found!"

- [ ] **Step 10: Commit**

```
git add app/lib/data/stats_repository.dart app/lib/util/dates.dart app/lib/l10n/app_en.arb app/lib/l10n/app_it.arb app/lib/l10n/app_de.arb app/lib/l10n/app_es.arb app/lib/ui/profile_screen.dart app/test/data/stats_repository_integration_test.dart app/test/util/dates_test.dart app/test/ui/profile_training_line_test.dart app/test/ui/profile_header_test.dart app/test/layout/profile_layout_test.dart
git commit -m "fix(app): show the user's real training history on Profile"
```


### Task 11: Plan editors know when they hold unsaved edits

**Files:**
- Create: `app/lib/ui/editor_guard.dart`
- Modify: `app/lib/ui/day_editor.dart`. Anchors:
  - the imports (`import '../widgets/w_dialog.dart';`) and the `DayEditor` constructor;
  - the `_DayEditorState` fields after `bool _saving = false;`, `initState`, and a new `didUpdateWidget`;
  - the three `setState` calls in `_loadData`, and a new "unsaved edits" section after `_loadData`;
  - the draft built in `_save`, and the `deleteDay` call in `_delete`.
- Modify: `app/lib/ui/exercise_editor.dart`. Anchors:
  - the imports (`import '../widgets/w_dialog.dart';`) and the `ExerciseEditor` constructor;
  - the `_ExerciseEditorState` fields after `bool _saving = false;`, `initState`, and a new `didUpdateWidget`;
  - the three `setState` calls in `_loadData`, and a new "unsaved edits" section above `// ── save`;
  - the draft built in `_save`, the two `deleteExercise` calls in `_delete`, and a new `_deleteConfirmed`.
- Test: `app/test/ui/editor_guard_test.dart` (create; pure snapshot tests)
- Test: `app/test/ui/plan_editor_dirty_test.dart` (create; tests the editor wiring over the real DB)

**Interfaces:**
- Consumes only existing code:
  - `DayDraft`, `SlotDraft` and `ExerciseDraft` (`data/models.dart`);
  - `UnitService.fromKg/toKg` and `UnitService.setUnit`;
  - `clampRound2` (`util/number_input.dart`);
  - from `test/support/screen_harness.dart`: `ScreenHarness` (including `harness.units`), `settleReal`, `settleUntilFound`, `scrollIntoView` and `setPhone`.
- Other tasks touch other lines in both editors. The earlier RIR task changes the stepper `min`/`max` to `rirMin`/`rirMax`. The formatter task changes the start-weight `format`/`formatForEdit` to `fmtLoad` and swaps the `util/format.dart` import. Every edit here is anchored on the constructor, the fields, `initState`, `_loadData`, `_save` and `_delete`, never on those lines.
- Produces (in `app/lib/ui/editor_guard.dart`):
  - `class EditorGuard { bool Function() isDirty; }`. A fresh guard's `isDirty()` returns false.
  - `typedef SlotValues = ({String? itemId, String exerciseId, int? workSets, int? warmupSets, int? repLow, int? repHigh, int? rirLow, int? rirHigh});`
  - `class DaySnapshot`, with `name`, `focus`, `weekday` and `List<SlotValues> slots`. Its `==` compares the slots with `listEquals`, and its `hashCode` matches. Built by `DaySnapshot daySnapshot(DayDraft d)`.
  - `class ExerciseSnapshot`, with `==` and `hashCode` over every field. Weights are kg `toStringAsFixed(2)` strings. Built by `ExerciseSnapshot exerciseSnapshot(ExerciseDraft d)`.
  - `DayEditor({Key? key, required String? id, required VoidCallback onBack, EditorGuard? guard})`
  - `ExerciseEditor({Key? key, required String? id, required VoidCallback onBack, EditorGuard? guard})`
  - Both editors set `guard.isDirty` in `initState`, and set it again in `didUpdateWidget` when `widget.guard` changes.

- [ ] **Step 1: Write the failing snapshot tests.** Create `app/test/ui/editor_guard_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/ui/editor_guard.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/util/number_input.dart';

SlotDraft _slot(String exerciseId, {String? itemId}) => SlotDraft(
      itemId: itemId,
      exerciseId: exerciseId,
      workSets: 3,
      warmupSets: 1,
      repLow: 6,
      repHigh: 10,
      rirLow: 1,
      rirHigh: 2,
    );

DayDraft _day({String name = 'Push', String? focus = 'Chest'}) => DayDraft(
      name: name,
      focus: focus,
      weekday: 0,
      slots: [_slot('ex1', itemId: 'i1'), _slot('ex2', itemId: 'i2')],
    );

ExerciseDraft _exercise({
  String name = 'Bench Press',
  String? equip = 'barbell',
  double? baseWeightKg = 20,
  int? restSeconds,
}) =>
    ExerciseDraft(
      name: name,
      muscleGroup: 'chest',
      equip: equip,
      compound: true,
      baseWeightKg: baseWeightKg,
      plateStepKg: 2.5,
      defaultRepLow: 6,
      defaultRepHigh: 10,
      defaultWarmupSets: 1,
      defaultWorkingSets: 3,
      defaultRirLow: 1,
      defaultRirHigh: 2,
      defaultRestSeconds: restSeconds,
    );

void main() {
  group('daySnapshot', () {
    test('an untouched day equals its baseline', () {
      final d = _day();
      final baseline = daySnapshot(d);
      expect(daySnapshot(d), baseline);
      expect(daySnapshot(d).hashCode, baseline.hashCode);
      expect(daySnapshot(_day()), baseline);
    });

    test('reordering slots and back again equals the baseline', () {
      final d = _day();
      final baseline = daySnapshot(d);
      d.slots.insert(0, d.slots.removeAt(1));
      expect(daySnapshot(d), isNot(baseline));
      d.slots.insert(1, d.slots.removeAt(0));
      expect(daySnapshot(d), baseline);
    });

    test('removing an exercise and adding it back is a change', () {
      final d = _day();
      final baseline = daySnapshot(d);
      d.slots.removeAt(1);
      // A re-added slot has no item id: Save would write a new row.
      d.slots.add(_slot('ex2'));
      expect(daySnapshot(d), isNot(baseline));
    });

    test('surrounding whitespace is ignored and a blank focus is none', () {
      expect(daySnapshot(_day(name: '  Push ', focus: 'Chest  ')),
          daySnapshot(_day()));
      expect(daySnapshot(_day(focus: '   ')), daySnapshot(_day(focus: null)));
    });

    test('a slot draft changed in place after a snapshot differs from it', () {
      final d = _day();
      final before = daySnapshot(d);
      d.slots.first.workSets = 4;
      expect(daySnapshot(d), isNot(before));
    });
  });

  group('exerciseSnapshot', () {
    test('an untouched exercise equals its baseline', () {
      final baseline = exerciseSnapshot(_exercise());
      expect(exerciseSnapshot(_exercise()), baseline);
      expect(exerciseSnapshot(_exercise()).hashCode, baseline.hashCode);
    });

    test('surrounding whitespace is ignored and blank equipment is none', () {
      expect(
          exerciseSnapshot(_exercise(name: ' Bench Press  ', equip: ' barbell')),
          exerciseSnapshot(_exercise()));
      expect(exerciseSnapshot(_exercise(equip: '  ')),
          exerciseSnapshot(_exercise(equip: null)));
    });

    test('a rest of 0 equals the default', () {
      expect(exerciseSnapshot(_exercise(restSeconds: 0)),
          exerciseSnapshot(_exercise()));
      expect(exerciseSnapshot(_exercise(restSeconds: 90)),
          isNot(exerciseSnapshot(_exercise())));
    });

    test('a start weight stepped up and back down in lb is not a change', () {
      for (final kg in const [20.0, 60.0, 102.5]) {
        for (final plateKg in const [1.0, 1.25, 2.5, 5.0]) {
          // The editor's lb stepper: display value, plate step in lb, each
          // step rounded to two decimals; Save converts the result to kg.
          final s = UnitService.fromKg(plateKg, Unit.lb);
          final shown = clampRound2(
              clampRound2(UnitService.fromKg(kg, Unit.lb) + s) - s);
          expect(
              exerciseSnapshot(
                  _exercise(baseWeightKg: UnitService.toKg(shown, Unit.lb))),
              exerciseSnapshot(_exercise(baseWeightKg: kg)),
              reason: '$kg kg ± a $plateKg kg plate in lb');
        }
      }
    });

    test('a different start weight is a change, and none stays none', () {
      expect(exerciseSnapshot(_exercise(baseWeightKg: 22.5)),
          isNot(exerciseSnapshot(_exercise())));
      expect(exerciseSnapshot(_exercise(baseWeightKg: null)).baseWeightKg,
          isNull);
    });
  });

  test('a fresh guard reports no unsaved edits', () {
    expect(EditorGuard().isDirty(), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**
  - Run `timeout 900 make -C app test TEST=test/ui/editor_guard_test.dart > /tmp/claude-1000/guard-snapshot.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/guard-snapshot.log | tail -5`.
  - Expected: EXIT=2. The log first shows the compile error `test/ui/editor_guard_test.dart:3:8: Error: Error when reading 'lib/ui/editor_guard.dart': No such file or directory`. Then come `Error: Method not found: 'daySnapshot'.`, the same for `'exerciseSnapshot'` and `'EditorGuard'`, and finally `Some tests failed.`

- [ ] **Step 3: Implement the guard and snapshots.** Create `app/lib/ui/editor_guard.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../data/models.dart';

/// Lets PlanScreen ask the open editor whether leaving would lose edits.
/// One instance per open editor: never reused across opens.
class EditorGuard {
  bool Function() isDirty = _never;
}

bool _never() => false;

// ── Snapshots ─────────────────────────────────────────────────────────────

/// One slot's values, copied out of its [SlotDraft]: the day editor's rows
/// mutate their drafts in place, so a snapshot holding the drafts themselves
/// would change along with every edit.
typedef SlotValues = ({
  String? itemId,
  String exerciseId,
  int? workSets,
  int? warmupSets,
  int? repLow,
  int? repHigh,
  int? rirLow,
  int? rirHigh,
});

/// What saving a [DayDraft] would write, compared by value.
@immutable
class DaySnapshot {
  const DaySnapshot({
    required this.name,
    required this.focus,
    required this.weekday,
    required this.slots,
  });

  final String name;
  final String? focus;
  final int? weekday;
  final List<SlotValues> slots;

  // Element-wise: a record or class holding a List compares it by identity,
  // so two snapshots would never be equal.
  @override
  bool operator ==(Object other) =>
      other is DaySnapshot &&
      other.name == name &&
      other.focus == focus &&
      other.weekday == weekday &&
      listEquals(other.slots, slots);

  @override
  int get hashCode => Object.hash(name, focus, weekday, Object.hashAll(slots));

  @override
  String toString() =>
      'DaySnapshot($name, focus: $focus, weekday: $weekday, slots: $slots)';
}

/// The day as Save would persist it: trimmed text (an empty focus is none)
/// and each slot's values in order.
DaySnapshot daySnapshot(DayDraft d) {
  final focus = d.focus?.trim();
  return DaySnapshot(
    name: d.name.trim(),
    focus: focus == null || focus.isEmpty ? null : focus,
    weekday: d.weekday,
    slots: List.unmodifiable([
      for (final s in d.slots)
        (
          itemId: s.itemId,
          exerciseId: s.exerciseId,
          workSets: s.workSets,
          warmupSets: s.warmupSets,
          repLow: s.repLow,
          repHigh: s.repHigh,
          rirLow: s.rirLow,
          rirHigh: s.rirHigh,
        ),
    ]),
  );
}

/// What saving an [ExerciseDraft] would write, compared by value.
@immutable
class ExerciseSnapshot {
  const ExerciseSnapshot({
    required this.name,
    required this.muscleGroup,
    required this.equip,
    required this.compound,
    required this.baseWeightKg,
    required this.plateStepKg,
    required this.repLow,
    required this.repHigh,
    required this.workingSets,
    required this.warmupSets,
    required this.rirLow,
    required this.rirHigh,
    required this.restSeconds,
  });

  final String name;
  final String muscleGroup;
  final String? equip;
  final bool compound;

  /// Weights in their persisted form, kg to two decimals.
  final String? baseWeightKg;
  final String plateStepKg;

  final int? repLow;
  final int? repHigh;
  final int? workingSets;
  final int? warmupSets;
  final int? rirLow;
  final int? rirHigh;
  final int? restSeconds;

  @override
  bool operator ==(Object other) =>
      other is ExerciseSnapshot &&
      other.name == name &&
      other.muscleGroup == muscleGroup &&
      other.equip == equip &&
      other.compound == compound &&
      other.baseWeightKg == baseWeightKg &&
      other.plateStepKg == plateStepKg &&
      other.repLow == repLow &&
      other.repHigh == repHigh &&
      other.workingSets == workingSets &&
      other.warmupSets == warmupSets &&
      other.rirLow == rirLow &&
      other.rirHigh == rirHigh &&
      other.restSeconds == restSeconds;

  @override
  int get hashCode => Object.hash(
        name,
        muscleGroup,
        equip,
        compound,
        baseWeightKg,
        plateStepKg,
        repLow,
        repHigh,
        workingSets,
        warmupSets,
        rirLow,
        rirHigh,
        restSeconds,
      );

  @override
  String toString() => 'ExerciseSnapshot($name, $muscleGroup, equip: $equip, '
      'compound: $compound, base: $baseWeightKg, step: $plateStepKg, '
      'reps: $repLow-$repHigh, sets: $workingSets+$warmupSets, '
      'rir: $rirLow-$rirHigh, rest: $restSeconds)';
}

/// The exercise as Save would persist it: trimmed text (empty equipment is
/// none), weights as kg strings, and a 0 rest as the default (null). The kg
/// string is the stored form, so a weight stepped up and back down in lb is
/// not a change.
ExerciseSnapshot exerciseSnapshot(ExerciseDraft d) {
  final equip = d.equip?.trim();
  final rest = d.defaultRestSeconds;
  return ExerciseSnapshot(
    name: d.name.trim(),
    muscleGroup: d.muscleGroup,
    equip: equip == null || equip.isEmpty ? null : equip,
    compound: d.compound,
    baseWeightKg: d.baseWeightKg?.toStringAsFixed(2),
    plateStepKg: d.plateStepKg.toStringAsFixed(2),
    repLow: d.defaultRepLow,
    repHigh: d.defaultRepHigh,
    workingSets: d.defaultWorkingSets,
    warmupSets: d.defaultWarmupSets,
    rirLow: d.defaultRirLow,
    rirHigh: d.defaultRirHigh,
    restSeconds: rest == 0 ? null : rest,
  );
}
```

- [ ] **Step 4: Run it to verify it passes.** Run `timeout 900 make -C app test TEST=test/ui/editor_guard_test.dart > /tmp/claude-1000/guard-snapshot.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/guard-snapshot.log | tail -5`. Expected: EXIT=0 and `+11: All tests passed!`

- [ ] **Step 5: Write the failing editor-wiring tests.** Create `app/test/ui/plan_editor_dirty_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/ui/day_editor.dart';
import 'package:workout_tracker/ui/editor_guard.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/screen_harness.dart';

final _l = lookupAppLocalizations(const Locale('en'));

// Field renders its label upper-cased.
Finder _stepperButton(String label, String key) => find.descendant(
      of: find.ancestor(
          of: find.text(label.toUpperCase()), matching: find.byType(Field)),
      matching: find.byKey(Key(key)),
    );

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _mountDay(WidgetTester tester, ScreenHarness harness,
    EditorGuard guard, {String? id = 'd1', VoidCallback? onBack}) async {
  await tester.pumpWidget(harness.wrap(Scaffold(
      body: DayEditor(id: id, onBack: onBack ?? () {}, guard: guard))));
  // Loading needs real database work, so nothing has loaded yet.
  expect(guard.isDirty(), isFalse, reason: 'before loading');
  await settleUntilFound(
      tester,
      find.descendant(
          of: find.byType(DayEditor), matching: find.byType(ListView)),
      where: 'day editor');
}

Future<void> _mountExercise(WidgetTester tester, ScreenHarness harness,
    EditorGuard guard, {String? id, VoidCallback? onBack}) async {
  await tester.pumpWidget(harness.wrap(Scaffold(
      body: ExerciseEditor(id: id, onBack: onBack ?? () {}, guard: guard))));
  expect(guard.isDirty(), isFalse, reason: 'before loading');
  await settleUntilFound(
      tester,
      find.descendant(
          of: find.byType(ExerciseEditor), matching: find.byType(ListView)),
      where: 'exercise editor');
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('a loaded day is clean, dirty after an edit, clean once undone',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    await _mountDay(tester, harness, guard);
    expect(guard.isDirty(), isFalse);

    await tester.tap(find.text('Bench Press'));
    await settleReal(tester, ticks: 3);
    await _tapVisible(
        tester, _stepperButton(_l.dayEditorWorkingSets, 'stepper-inc'));
    expect(guard.isDirty(), isTrue);
    await _tapVisible(
        tester, _stepperButton(_l.dayEditorWorkingSets, 'stepper-dec'));
    expect(guard.isDirty(), isFalse);
    await harness.unmount(tester);
  });

  testWidgets('an untouched new day and an untouched new exercise are clean',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final dayGuard = EditorGuard();
    await _mountDay(tester, harness, dayGuard, id: null);
    expect(dayGuard.isDirty(), isFalse);

    final exerciseGuard = EditorGuard();
    await _mountExercise(tester, harness, exerciseGuard);
    expect(exerciseGuard.isDirty(), isFalse);
    await harness.unmount(tester);
  });

  testWidgets('a day being saved reports no unsaved edits', (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    var closed = 0;
    await _mountDay(tester, harness, guard, onBack: () => closed++);
    await tester.enterText(
        find.descendant(
            of: find.byType(DayEditor), matching: find.byType(TextField)).first,
        'Renamed day');
    await tester.pump();
    expect(guard.isDirty(), isTrue);

    await _tapVisible(tester, find.text(_l.dayEditorSaveChanges));
    expect(guard.isDirty(), isFalse, reason: 'while the save is in flight');
    await settleReal(tester, ticks: 10);
    expect(closed, 1);
    await harness.unmount(tester);
  });

  testWidgets('a day being deleted reports no unsaved edits', (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    var closed = 0;
    await _mountDay(tester, harness, guard, onBack: () => closed++);
    await tester.enterText(
        find.descendant(
            of: find.byType(DayEditor), matching: find.byType(TextField)).first,
        'Renamed day');
    await tester.pump();

    await _tapVisible(tester, find.text(_l.dayEditorDeleteButton));
    await settleReal(tester, ticks: 5);
    expect(guard.isDirty(), isTrue, reason: 'the delete is not confirmed yet');
    await tester.tap(find.text(_l.commonDelete));
    await tester.pump();
    expect(guard.isDirty(), isFalse, reason: 'while the delete is in flight');
    await settleReal(tester, ticks: 10);
    expect(closed, 1);
    await harness.unmount(tester);
  });

  testWidgets('a loaded exercise is clean, dirty after an edit, clean once '
      'undone, and clean while its delete is in flight', (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    var closed = 0;
    // Brand New Movement has no logged sets, so it can be deleted.
    await _mountExercise(tester, harness, guard,
        id: 'ex4', onBack: () => closed++);
    expect(guard.isDirty(), isFalse);

    await _tapVisible(
        tester, _stepperButton(_l.exerciseEditorStartWeight, 'stepper-inc'));
    expect(guard.isDirty(), isTrue);
    await _tapVisible(
        tester, _stepperButton(_l.exerciseEditorStartWeight, 'stepper-dec'));
    expect(guard.isDirty(), isFalse);
    await _tapVisible(
        tester, _stepperButton(_l.exerciseEditorStartWeight, 'stepper-inc'));
    expect(guard.isDirty(), isTrue);

    await _tapVisible(tester, find.text(_l.exerciseEditorDeleteButton));
    await settleReal(tester, ticks: 5);
    await tester.tap(find.text(_l.commonDelete));
    await tester.pump();
    expect(guard.isDirty(), isFalse, reason: 'while the delete is in flight');
    await settleReal(tester, ticks: 10);
    expect(closed, 1);
    await harness.unmount(tester);
  });

  testWidgets('an exercise being saved reports no unsaved edits',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    var closed = 0;
    await _mountExercise(tester, harness, guard,
        id: 'ex3', onBack: () => closed++);
    await _tapVisible(
        tester, _stepperButton(_l.exerciseEditorStartWeight, 'stepper-inc'));
    expect(guard.isDirty(), isTrue);

    final save = find.text(_l.exerciseEditorSave);
    await scrollIntoView(tester, find.byType(ExerciseEditor), save);
    await tester.tap(save);
    await tester.pump();
    expect(guard.isDirty(), isFalse, reason: 'while the save is in flight');
    await settleReal(tester, ticks: 10);
    expect(closed, 1);
    await harness.unmount(tester);
  });

  testWidgets('an untouched exercise stays clean when the unit switches',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    final guard = EditorGuard();
    await _mountExercise(tester, harness, guard, id: 'ex3');
    expect(guard.isDirty(), isFalse);

    harness.units.setUnit(Unit.lb);
    expect(guard.isDirty(), isFalse,
        reason: 'before the editor rebuilds in lb');
    await settleReal(tester, ticks: 3);
    expect(guard.isDirty(), isFalse, reason: 'after it rebuilds in lb');
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 6: Run it to verify it fails.**
  - Run `timeout 900 make -C app test TEST=test/ui/plan_editor_dirty_test.dart > /tmp/claude-1000/guard-wiring.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/guard-wiring.log | tail -5`.
  - Expected: EXIT=2, with the compile error `Error: No named parameter with the name 'guard'.` at both editor constructions: `test/ui/plan_editor_dirty_test.dart:31:56` in `_mountDay` and `:44:61` in `_mountExercise`.

- [ ] **Step 7: Implement in `app/lib/ui/day_editor.dart`.** Seven edits.

7a. Imports. Replace:
```dart
import '../widgets/w_dialog.dart';
import 'exercise_sheet.dart';
```
with:
```dart
import '../widgets/w_dialog.dart';
import 'editor_guard.dart';
import 'exercise_sheet.dart';
```

7b. Constructor. Replace:
```dart
/// [onBack] is called after save or delete so the parent can return to the list.
class DayEditor extends StatefulWidget {
  const DayEditor({super.key, required this.id, required this.onBack});

  final String? id;
  final VoidCallback onBack;
```
with:
```dart
/// [onBack] is called after save or delete so the parent can return to the list.
/// [guard], when given, is bound to report whether leaving would lose edits.
class DayEditor extends StatefulWidget {
  const DayEditor({
    super.key,
    required this.id,
    required this.onBack,
    this.guard,
  });

  final String? id;
  final VoidCallback onBack;
  final EditorGuard? guard;
```

7c. Fields, binding and re-binding. Replace:
```dart
  List<Exercise> _catalog = [];
  bool _saving = false;

  DayTemplateRepository get _dayRepo => DayTemplateRepository(db);
  ExerciseRepository get _exRepo => ExerciseRepository(db);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _focusCtrl = TextEditingController();
    _loadData();
  }
```
with:
```dart
  List<Exercise> _catalog = [];
  bool _saving = false;

  // From the delete confirm until the delete lands: leaving then loses
  // nothing, because the day is going away.
  bool _deleting = false;

  // What Save would have written right after loading; null until loaded.
  DaySnapshot? _baseline;

  DayTemplateRepository get _dayRepo => DayTemplateRepository(db);
  ExerciseRepository get _exRepo => ExerciseRepository(db);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _focusCtrl = TextEditingController();
    widget.guard?.isDirty = _isDirty;
    _loadData();
  }

  @override
  void didUpdateWidget(DayEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.guard != oldWidget.guard) widget.guard?.isDirty = _isDirty;
  }
```

7d. Take the baseline in the new-day branch of `_loadData`. Replace:
```dart
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _editId = null;
          _loaded = true;
        });
      }
      return;
```
with:
```dart
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _editId = null;
          _baseline = daySnapshot(_currentDraft());
          _loaded = true;
        });
      }
      return;
```

7e. Take the baseline in the day-not-found branch. Replace:
```dart
      // Day not found (edge case) — treat as new.
      setState(() {
        _catalog = catalog;
        _editId = null;
        _loaded = true;
      });
```
with:
```dart
      // Day not found (edge case) — treat as new.
      setState(() {
        _catalog = catalog;
        _editId = null;
        _baseline = daySnapshot(_currentDraft());
        _loaded = true;
      });
```

7f. Take the baseline in the existing-day branch, after the slots are normalised, and add the unsaved-edits section. Replace:
```dart
      _weekday = day.scheduledWeekday;
      _slots.addAll(slots);
      _loaded = true;
    });
  }
```
with:
```dart
      _weekday = day.scheduledWeekday;
      _slots.addAll(slots);
      _baseline = daySnapshot(_currentDraft());
      _loaded = true;
    });
  }

  // ── unsaved edits ─────────────────────────────────────────────────────────

  /// What Save would write now.
  DayDraft _currentDraft() => DayDraft(
        name: _nameCtrl.text.trim(),
        focus: _focusCtrl.text.trim().isEmpty ? null : _focusCtrl.text.trim(),
        weekday: _weekday,
        slots: _slots.map((s) => s.draft).toList(),
      );

  /// Whether leaving now would lose edits. Never while loading, saving or
  /// deleting: back then closes as before and the write still lands.
  bool _isDirty() {
    final baseline = _baseline;
    if (baseline == null || _saving || _deleting) return false;
    return daySnapshot(_currentDraft()) != baseline;
  }
```

7g. Make `_save` use the shared draft, and flag the in-flight delete. In `_save`, replace:
```dart
    final draft = DayDraft(
      name: _nameCtrl.text.trim(),
      focus: _focusCtrl.text.trim().isEmpty ? null : _focusCtrl.text.trim(),
      weekday: _weekday,
      slots: _slots.map((s) => s.draft).toList(),
    );
```
with:
```dart
    final draft = _currentDraft();
```
In `_delete`, replace:
```dart
    if (confirmed != true) return;
    await _dayRepo.deleteDay(_editId!);
    if (mounted) widget.onBack();
```
with:
```dart
    if (confirmed != true) return;
    _deleting = true;
    try {
      await _dayRepo.deleteDay(_editId!);
    } finally {
      _deleting = false;
    }
    if (mounted) widget.onBack();
```

- [ ] **Step 8: Implement in `app/lib/ui/exercise_editor.dart`.** Eight edits.

8a. Imports. Replace:
```dart
import '../widgets/w_dialog.dart';
```
with:
```dart
import '../widgets/w_dialog.dart';
import 'editor_guard.dart';
```

8b. Constructor. Replace:
```dart
/// [onBack] is called after save so the parent returns to the list.
class ExerciseEditor extends StatefulWidget {
  const ExerciseEditor({
    super.key,
    required this.id,
    required this.onBack,
  });

  final String? id;
  final VoidCallback onBack;
```
with:
```dart
/// [onBack] is called after save so the parent returns to the list.
/// [guard], when given, is bound to report whether leaving would lose edits.
class ExerciseEditor extends StatefulWidget {
  const ExerciseEditor({
    super.key,
    required this.id,
    required this.onBack,
    this.guard,
  });

  final String? id;
  final VoidCallback onBack;
  final EditorGuard? guard;
```

8c. Fields, binding and re-binding. Replace:
```dart
  bool _saving = false;

  ExerciseRepository get _repo => ExerciseRepository(db);

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _equipCtrl = TextEditingController();
    _loadData();
  }
```
with:
```dart
  bool _saving = false;

  // From the delete confirm until the delete lands: leaving then loses
  // nothing, because the exercise is going away.
  bool _deleting = false;

  // What Save would have written right after loading; null until loaded.
  ExerciseSnapshot? _baseline;

  ExerciseRepository get _repo => ExerciseRepository(db);

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _equipCtrl = TextEditingController();
    widget.guard?.isDirty = _isDirty;
    _loadData();
  }

  @override
  void didUpdateWidget(ExerciseEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.guard != oldWidget.guard) widget.guard?.isDirty = _isDirty;
  }
```

8d. New-exercise branch of `_loadData`. Replace:
```dart
          _baseWeightDisplay = 0;
          _stepDisplay = stepDisplay;
          _loaded = true;
```
with:
```dart
          _baseWeightDisplay = 0;
          _stepDisplay = stepDisplay;
          _baseline = exerciseSnapshot(_currentDraft());
          _loaded = true;
```

8e. Not-found branch. Replace:
```dart
      // Not found — treat as new.
      setState(() {
        _editId = null;
        _loaded = true;
      });
```
with:
```dart
      // Not found — treat as new.
      setState(() {
        _editId = null;
        _baseline = exerciseSnapshot(_currentDraft());
        _loaded = true;
      });
```

8f. Existing-exercise branch. The baseline is taken after all the load normalisation: the `rirOrdered` / half-set → null rule, the `?? 8 / 12 / 3 / 0` defaults and the rest sentinel. Replace:
```dart
      _prKg = prKg;
      _extraMuscle = extra;
      _loaded = true;
    });
  }
```
with:
```dart
      _prKg = prKg;
      _extraMuscle = extra;
      _baseline = exerciseSnapshot(_currentDraft());
      _loaded = true;
    });
  }
```

8g. Extract the draft out of `_save`. `_currentDraft` converts with the unit that `_baseWeightDisplay` is actually held in (`_lastUnit`, which only `build` updates). The context's unit is wrong between a unit switch and the editor's next build. Replace the block from the save section header to the end of the `ExerciseDraft` constructor call in `_save`:
```dart
  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    // This screen does not own any of its steppers, so nothing else unfocuses
    // an open one on Android (tap-outside only unfocuses for touch on web,
    // and this button's own tap handler never requests focus). Flush focus
    // BEFORE _baseWeightDisplay (and the other stepper-backed fields below)
    // are read — the stepper's focus-loss listener commits synchronously.
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    setState(() => _saving = true);

    final unit = context.read<UnitService>().unit;

    // Convert display weight back to kg; 0 → null (write NULL, not 0.00).
    final baseKg = _baseWeightDisplay <= 0
        ? null
        : UnitService.toKg(_baseWeightDisplay, unit);

    final draft = ExerciseDraft(
      name: _nameCtrl.text.trim(),
      muscleGroup: _muscleGroup,
      equip: _equipCtrl.text.trim().isEmpty ? null : _equipCtrl.text.trim(),
      compound: _compound,
      baseWeightKg: baseKg,
      plateStepKg: _plateStepKg,
      defaultRepLow: _repLow,
      defaultRepHigh: _repHigh,
      defaultWarmupSets: _warmupSets,
      defaultWorkingSets: _workSets,
      defaultRirLow: _rirLow,
      defaultRirHigh: _rirHigh,
      defaultRestSeconds: _restSeconds == 0 ? null : _restSeconds,
    );
```
with:
```dart
  // ── unsaved edits ──────────────────────────────────────────────────────────

  /// What Save would write now, in kg.
  ExerciseDraft _currentDraft() {
    // The unit _baseWeightDisplay is held in: right after a unit switch it
    // is still the old one, until the next build converts the value.
    final unit = _lastUnit ?? context.read<UnitService>().unit;

    // Convert display weight back to kg; 0 → null (write NULL, not 0.00).
    final baseKg = _baseWeightDisplay <= 0
        ? null
        : UnitService.toKg(_baseWeightDisplay, unit);

    return ExerciseDraft(
      name: _nameCtrl.text.trim(),
      muscleGroup: _muscleGroup,
      equip: _equipCtrl.text.trim().isEmpty ? null : _equipCtrl.text.trim(),
      compound: _compound,
      baseWeightKg: baseKg,
      plateStepKg: _plateStepKg,
      defaultRepLow: _repLow,
      defaultRepHigh: _repHigh,
      defaultWarmupSets: _warmupSets,
      defaultWorkingSets: _workSets,
      defaultRirLow: _rirLow,
      defaultRirHigh: _rirHigh,
      defaultRestSeconds: _restSeconds == 0 ? null : _restSeconds,
    );
  }

  /// Whether leaving now would lose edits. Never while loading, saving or
  /// deleting: back then closes as before and the write still lands.
  bool _isDirty() {
    final baseline = _baseline;
    // _currentDraft can read the unit from context.
    if (!mounted || baseline == null || _saving || _deleting) return false;
    return exerciseSnapshot(_currentDraft()) != baseline;
  }

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    // This screen does not own any of its steppers, so nothing else unfocuses
    // an open one on Android (tap-outside only unfocuses for touch on web,
    // and this button's own tap handler never requests focus). Flush focus
    // BEFORE _baseWeightDisplay (and the other stepper-backed fields below)
    // are read — the stepper's focus-loss listener commits synchronously.
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    setState(() => _saving = true);

    final draft = _currentDraft();
```

8h. Flag the in-flight delete. In `_delete`, replace:
```dart
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: true);
```
with:
```dart
        if (ok != true) return;
        await _deleteConfirmed(id, removeFromDays: true);
```
Then replace:
```dart
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: false);
    }
    if (mounted) widget.onBack();
  }
```
with:
```dart
        if (ok != true) return;
        await _deleteConfirmed(id, removeFromDays: false);
    }
    if (mounted) widget.onBack();
  }

  /// Runs a confirmed delete. Until it lands the editor reports no unsaved
  /// edits, so a back press closes it as before.
  Future<void> _deleteConfirmed(String id,
      {required bool removeFromDays}) async {
    _deleting = true;
    try {
      await _repo.deleteExercise(id, removeFromDays: removeFromDays);
    } finally {
      _deleting = false;
    }
  }
```

- [ ] **Step 9: Run the tests to verify they pass.**
  - Run `timeout 900 make -C app test TEST="test/ui/editor_guard_test.dart test/ui/plan_editor_dirty_test.dart test/ui/exercise_editor_rir_test.dart test/ui/day_editor_slot_row_test.dart" > /tmp/claude-1000/guard-editors.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/guard-editors.log | tail -5`.
  - Expected: EXIT=0. In isolation this gave `+27: All tests passed!`.
  - `exercise_editor_rir_test` still builds `ExerciseEditor(id:, onBack:)` with no guard, which proves the parameter is optional.

- [ ] **Step 10: Analyze.** Run `make -C app analyze > /tmp/claude-1000/guard-editors-analyze.log 2>&1; echo EXIT=$?`, then `tail -3 /tmp/claude-1000/guard-editors-analyze.log`. Expected: "No issues found!"

- [ ] **Step 11: Commit.**
```bash
git add app/lib/ui/editor_guard.dart app/lib/ui/day_editor.dart app/lib/ui/exercise_editor.dart app/test/ui/editor_guard_test.dart app/test/ui/plan_editor_dirty_test.dart
git commit -m "feat(app): track unsaved edits in the plan editors"
```

### Task 12: Leaving a Plan editor asks before discarding edits

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_it.arb`, `app/lib/l10n/app_de.arb` and `app/lib/l10n/app_es.arb`. Insert after the `"commonDiscard"` line and after the `"planNewExercise"` line.
- Modify: `app/lib/shell/back_dispatch.dart` (whole file)
- Modify: `app/lib/ui/plan_screen.dart`. Anchors: the imports, `class _EditorRoute`, `PlanScreenState`'s `_openEditor` / `_onBack` / `handleBack`, the `_BackButton(...)` call in `_buildHeader`, and the body routing at the top of `_buildBody`.
- Modify: `app/lib/shell/app_shell.dart`. Anchors: the imports, a new `_confirmExit` above `// ── Build`, and the `onPopInvokedWithResult` of the root `PopScope` in `build`.
- Test: `app/test/shell/back_dispatch_test.dart` (rewrite)
- Test: `app/test/shell/plan_discard_test.dart` (create)

**Interfaces:**
- Consumes from Task 11: `EditorGuard` (`ui/editor_guard.dart`), and the optional `guard:` parameter on `DayEditor` and `ExerciseEditor`.
- Consumes existing code:
  - `commitPendingInput()` (`widgets/pending_input.dart`);
  - `showWConfirm(context, {title, message, cancelLabel, confirmLabel, destructive})` (`widgets/w_dialog.dart`);
  - `l.commonDiscard` and `l.commonBack`;
  - `PrimaryBtn` (`widgets/plan_form.dart`, public `enabled`) and `SplitDayCard` (`ui/split_tab.dart`, public `name`);
  - `PowerSyncDatabase.writeLock` through `harness.database`;
  - from `test/support/screen_harness.dart`: `ScreenHarness`, `seedLong`, `openTab`, `settleReal`, `settleUntilFound` and `scrollIntoView`. In `seedLong`, `longDay` is d1, whose four slots include Bench Press = ex3, and 'Pull' is d2.
- Produces:
  - `enum BackAction { none, goHome, exit, confirmExit }`
  - `BackAction decideBack({required bool tabHandled, required int tabIndex, required bool planEditsAtRisk})`
  - `PlanScreenState.requestClose()`, returning `Future<bool>`: true when the editor closed.
  - `PlanScreenState.hasUnsavedEdits` (`bool`).
  - `PlanScreenState.handleBack()` keeps its `bool` signature.
  - The l10n getters `planDiscardTitle`, `planDiscardDayMessage`, `planDiscardExerciseMessage` and `commonKeepEditing`.

- [ ] **Step 1: Add the strings.** Insert each line directly after its anchor.
  - `app/lib/l10n/app_en.arb`:
    - after `  "commonDiscard": "Discard",`, insert `  "commonKeepEditing": "Keep editing",`
    - after `  "planNewExercise": "New exercise",`, insert:
```json
  "planDiscardTitle": "Discard changes?",
  "planDiscardDayMessage": "Your changes to this training day will be lost.",
  "planDiscardExerciseMessage": "Your changes to this exercise will be lost.",
```
  - `app/lib/l10n/app_it.arb`:
    - after `  "commonDiscard": "Scarta",`, insert `  "commonKeepEditing": "Continua a modificare",`
    - after `  "planNewExercise": "Nuovo esercizio",`, insert:
```json
  "planDiscardTitle": "Scartare le modifiche?",
  "planDiscardDayMessage": "Le modifiche a questo giorno di allenamento andranno perse.",
  "planDiscardExerciseMessage": "Le modifiche a questo esercizio andranno perse.",
```
  - `app/lib/l10n/app_de.arb`:
    - after `  "commonDiscard": "Verwerfen",`, insert `  "commonKeepEditing": "Weiter bearbeiten",`
    - after `  "planNewExercise": "Neue Übung",`, insert:
```json
  "planDiscardTitle": "Änderungen verwerfen?",
  "planDiscardDayMessage": "Deine Änderungen an diesem Trainingstag gehen verloren.",
  "planDiscardExerciseMessage": "Deine Änderungen an dieser Übung gehen verloren.",
```
  - `app/lib/l10n/app_es.arb`:
    - after `  "commonDiscard": "Descartar",`, insert `  "commonKeepEditing": "Seguir editando",`
    - after `  "planNewExercise": "Nuevo ejercicio",`, insert:
```json
  "planDiscardTitle": "¿Descartar los cambios?",
  "planDiscardDayMessage": "Se perderán los cambios de este día de entrenamiento.",
  "planDiscardExerciseMessage": "Se perderán los cambios de este ejercicio.",
```

  Then regenerate the gitignored l10n: `make -C app get > /tmp/claude-1000/guard-get.log 2>&1; echo EXIT=$?`. Expected: EXIT=0.

- [ ] **Step 2: Write the failing tests.** Replace `app/test/shell/back_dispatch_test.dart` with the file below. The three existing cases now pass `planEditsAtRisk: false`, and three cases are new.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/back_dispatch.dart';

void main() {
  test('a tab that handled back wins (stay put)', () {
    expect(
        decideBack(tabHandled: true, tabIndex: 3, planEditsAtRisk: false),
        BackAction.none);
  });
  test('non-home tab goes home', () {
    for (final i in [1, 2, 3]) {
      expect(
          decideBack(tabHandled: false, tabIndex: i, planEditsAtRisk: false),
          BackAction.goHome);
    }
  });
  test('home exits', () {
    expect(
        decideBack(tabHandled: false, tabIndex: 0, planEditsAtRisk: false),
        BackAction.exit);
  });
  test('home asks first while a Plan editor holds unsaved edits', () {
    expect(
        decideBack(tabHandled: false, tabIndex: 0, planEditsAtRisk: true),
        BackAction.confirmExit);
  });
  test('unsaved Plan edits leave back on the other tabs unchanged', () {
    for (final i in [1, 2, 3]) {
      expect(
          decideBack(tabHandled: false, tabIndex: i, planEditsAtRisk: true),
          BackAction.goHome);
    }
  });
  test('a Plan tab that handled back still wins with edits at risk', () {
    expect(
        decideBack(tabHandled: true, tabIndex: 3, planEditsAtRisk: true),
        BackAction.none);
  });
}
```

Create `app/test/shell/plan_discard_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/day_editor.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/ui/plan_screen.dart';
import 'package:workout_tracker/ui/split_tab.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/screen_harness.dart';

final _l = lookupAppLocalizations(const Locale('en'));

Finder get _discardTitle => find.text(_l.planDiscardTitle);

// Field renders its label upper-cased.
Finder _inField(String label, Finder matching) => find.descendant(
      of: find.ancestor(
          of: find.text(label.toUpperCase()), matching: find.byType(Field)),
      matching: matching,
    );

Finder get _workingSetsInc =>
    _inField(_l.dayEditorWorkingSets, find.byKey(const Key('stepper-inc')));
Finder get _workingSetsDec =>
    _inField(_l.dayEditorWorkingSets, find.byKey(const Key('stepper-dec')));
Finder _workingSetsShows(String v) =>
    _inField(_l.dayEditorWorkingSets, find.text(v));

Finder get _startWeightInc => _inField(
    _l.exerciseEditorStartWeight, find.byKey(const Key('stepper-inc')));
Finder get _startWeightDec => _inField(
    _l.exerciseEditorStartWeight, find.byKey(const Key('stepper-dec')));

Finder _dayCard(String name) =>
    find.byWidgetPredicate((w) => w is SplitDayCard && w.name == name);

/// The ids of the day editors mounted now, fading ones included.
List<String?> _dayEditorIds(WidgetTester tester) => [
      for (final e in tester.widgetList<DayEditor>(find.byType(DayEditor)))
        e.id,
    ];

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settleReal(tester, ticks: 3);
}

/// Mounts the shell and switches to the Plan tab.
Future<void> _openPlan(WidgetTester tester, ScreenHarness harness) async {
  await tester.pumpWidget(
      harness.wrap(AppShell(onLogout: () async {}, auth: AuthStore())));
  await settleReal(tester);
  await openTab(tester, WIcons.plan);
}

/// Opens seedLong's four-slot day.
Future<void> _openDay(WidgetTester tester) async {
  await settleUntilFound(tester, _dayCard(longDay), where: 'Plan split');
  await tester.tap(_dayCard(longDay));
  await settleUntilFound(tester, find.byType(DaySlotRow), where: 'day editor');
}

/// Expands the open day's Bench Press slot, scrolling it to the top.
Future<void> _expandBenchPress(WidgetTester tester) => _tapVisible(
    tester,
    find.descendant(
        of: find.byType(DayEditor), matching: find.text('Bench Press')));

/// Opens Bench Press from the Exercises sub-tab.
Future<void> _openExercise(WidgetTester tester) async {
  await tester.tap(find
      .descendant(
          of: find.byType(PlanScreen), matching: find.text(_l.planTabExercises))
      .first);
  final row = find.descendant(
      of: find.byType(PlanScreen), matching: find.text('Bench Press'));
  await settleUntilFound(tester, row, where: 'exercise library');
  await tester.tap(row.first);
  await settleUntilFound(
      tester,
      find.descendant(
          of: find.byType(ExerciseEditor), matching: find.byType(ListView)),
      where: 'exercise editor');
}

/// A system back press, as the platform delivers it.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settleReal(tester, ticks: 10);
}

/// An Android predictive back gesture, started at the left edge and committed.
Future<void> _predictiveBack(WidgetTester tester) async {
  Future<void> send(String method, [Object? arguments]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        SystemChannels.backGesture.codec
            .encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
  await send('startBackGesture', <String, Object?>{
    'touchOffset': <double>[5.0, 300.0],
    'progress': 0.0,
    'swipeEdge': 0,
  });
  await send('commitBackGesture');
  await settleReal(tester, ticks: 10);
}

/// Real-async ticks with short frames until [until] holds: database work
/// lands, but a 220ms editor fade does not finish.
Future<void> _shortTicks(WidgetTester tester,
    {required bool Function() until}) async {
  for (var i = 0; i < 30 && !until(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 4));
  }
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  group('day editor', () {
    testWidgets('untouched, back closes it without asking', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a stepped count asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      expect(find.text(_l.planDiscardDayMessage), findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a count stepped up and back down does not ask',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);
      await _tapVisible(tester, _workingSetsDec);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a half-typed count asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsShows('3'));
      final field = _inField(_l.dayEditorWorkingSets, find.byType(TextField));
      expect(field, findsOneWidget);
      // Still focused: nothing has committed the typed value yet.
      await tester.enterText(field, '5');
      await tester.pump();

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('an edited day name asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await tester.enterText(
          _inField(_l.dayEditorName, find.byType(TextField)), 'Renamed day');
      await tester.pump();

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('Keep editing keeps the edit; Discard closes and drops it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);
      expect(_workingSetsShows('4'), findsOneWidget);

      await _back(tester);
      await tester.tap(find.text(_l.commonKeepEditing));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(_workingSetsShows('4'), findsOneWidget);

      await _back(tester);
      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);

      await _openDay(tester);
      await _expandBenchPress(tester);
      expect(_workingSetsShows('3'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('Save closes without asking', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final save = find.text(_l.dayEditorSaveChanges);
      await scrollIntoView(tester, find.byType(DayEditor), save);
      await tester.tap(save);
      await settleReal(tester, ticks: 15);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('an edit survives a trip to another tab, with no prompt',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await openTab(tester, WIcons.history);
      expect(find.text(_l.planDiscardTitle, skipOffstage: false), findsNothing);
      expect(find.byType(DayEditor, skipOffstage: false), findsOneWidget);

      await openTab(tester, WIcons.plan);
      expect(_discardTitle, findsNothing);
      expect(_workingSetsShows('4'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a tap that falls through to the outgoing list keeps the '
        'opened editor', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await settleUntilFound(tester, _dayCard('Pull'), where: 'Plan split');
      await tester.tap(_dayCard(longDay));
      await tester.pump(const Duration(milliseconds: 50));
      // The new editor still shows its spinner; the list is fading out.
      await tester.tap(_dayCard('Pull'), warnIfMissed: false);
      await tester.pump();

      await settleUntilFound(tester, find.byType(DaySlotRow),
          where: 'day editor');
      expect(_dayEditorIds(tester), ['d1']);
      await harness.unmount(tester);
    });

    testWidgets('a save that lands after its editor closed leaves the next '
        'editor open', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await settleUntilFound(tester, _dayCard('Pull'), where: 'Plan split');
      await tester.tap(_dayCard('Pull'));
      await settleUntilFound(tester, find.byType(DaySlotRow),
          where: 'day editor');
      final save = find.text(_l.dayEditorSaveChanges);
      await scrollIntoView(tester, find.byType(DayEditor), save);
      final pullSave = find.descendant(
          of: find.byWidgetPredicate((w) => w is DayEditor && w.id == 'd2'),
          matching: find.byType(PrimaryBtn));
      bool pullSaveEnabled() => tester.widget<PrimaryBtn>(pullSave).enabled;

      // Hold the database's write lock, so the save waits for it.
      final release = Completer<void>();
      late Future<void> held;
      await tester.runAsync(() async {
        final locked = Completer<void>();
        held = harness.database.writeLock((_) async {
          locked.complete();
          await release.future;
        });
        await locked.future;
      });
      await tester.tap(save);
      await tester.pump();
      expect(pullSaveEnabled(), isFalse, reason: 'the save is waiting');

      // Saving, it closes on back without asking, then fades out for 220ms.
      await tester.binding.handlePopRoute();
      await tester.pump();
      final card = _dayCard(longDay).hitTestable();
      await _shortTicks(tester, until: () => card.evaluate().isNotEmpty);
      await tester.tap(card);
      await tester.pump();

      await tester.runAsync(() async {
        release.complete();
        await held;
      });
      // The closed editor re-enables its Save right after calling back, and
      // only while it is still mounted.
      await _shortTicks(tester, until: pullSaveEnabled);
      expect(pullSaveEnabled(), isTrue,
          reason: 'the save finished while its editor was fading out');
      await settleReal(tester, ticks: 10);
      expect(_dayEditorIds(tester), ['d1']);
      await harness.unmount(tester);
    });

    testWidgets('two back presses queued together ask once', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final first = tester.binding.handlePopRoute();
      final second = tester.binding.handlePopRoute();
      await first;
      await second;
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a predictive back gesture asks before discarding',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await _predictiveBack(tester);
      expect(_discardTitle, findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('exercise editor', () {
    testWidgets('the header chevron closes it untouched and asks once edited',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);
      // The Back muscle chip carries the same label further down the tree.
      final chevron = find.bySemanticsLabel(_l.commonBack).first;

      await tester.tap(chevron);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);

      await _openExercise(tester);
      await _tapVisible(tester, _startWeightInc);
      await tester.tap(chevron);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(find.text(_l.planDiscardExerciseMessage), findsOneWidget);
      await tester.tap(find.text(_l.commonKeepEditing));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);

      // A screen reader's activation goes through the same check.
      tester.semantics.tap(find.semantics.byLabel(_l.commonBack).first);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(find.byType(ExerciseEditor), findsNothing);
      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a start weight stepped up and back down in lb does not ask',
        (tester) async {
      await harness.open(tester, prefs: {'unit': 'lb'});
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);
      await _tapVisible(tester, _startWeightInc);
      await _tapVisible(tester, _startWeightDec);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('switching to lb behind an untouched editor does not ask',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);

      await openTab(tester, WIcons.home);
      harness.units.setUnit(Unit.lb);
      await settleReal(tester, ticks: 5);
      await openTab(tester, WIcons.plan);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);
      await harness.unmount(tester);
    });
  });

  testWidgets('back on Today with unsaved Plan edits asks before exiting',
      (tester) async {
    final pops = <MethodCall>[];
    // The channel also carries haptics and SystemChrome calls.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') pops.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await harness.open(tester);
    setPhone(tester, width: 412);
    await _openPlan(tester, harness);
    await _openDay(tester);
    await _expandBenchPress(tester);
    await _tapVisible(tester, _workingSetsInc);
    await openTab(tester, WIcons.home);

    await _back(tester);
    expect(_discardTitle, findsOneWidget);
    // The shell switched to Plan, so the editor is on screen again.
    expect(find.byType(DayEditor), findsOneWidget);
    expect(pops, isEmpty);

    await tester.tap(find.text(_l.commonKeepEditing));
    await settleReal(tester, ticks: 10);
    expect(_workingSetsShows('4'), findsOneWidget);
    expect(pops, isEmpty);

    await openTab(tester, WIcons.home);
    await _back(tester);
    await tester.tap(find.text(_l.commonDiscard));
    await settleReal(tester, ticks: 10);
    expect(pops, hasLength(1));
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 3: Run them to verify they fail.**
  - **back_dispatch_test:**
    - Run `timeout 900 make -C app test TEST=test/shell/back_dispatch_test.dart > /tmp/claude-1000/guard-backdispatch.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Error" /tmp/claude-1000/guard-backdispatch.log | tail -5`.
    - Expected: EXIT=2, with the compile errors `Error: Member not found: 'confirmExit'.` and `Error: No named parameter with the name 'planEditsAtRisk'.`
  - **plan_discard_test:**
    - Run `timeout 900 make -C app test TEST=test/shell/plan_discard_test.dart > /tmp/claude-1000/guard-discard.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|Expected|Actual|\[E\]" /tmp/claude-1000/guard-discard.log | tail -30`.
    - Expected: EXIT=2 and `+6 -10: Some tests failed.`
  - Seven tests fail with `Expected: exactly one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets with text "Discard changes?": []>`:
    - "a stepped count asks…"
    - "a half-typed count asks…"
    - "an edited day name asks…"
    - "two back presses queued together ask once"
    - "a predictive back gesture asks…"
    - "the header chevron closes it untouched and asks once edited"
    - "back on Today with unsaved Plan edits asks before exiting"
  - Three tests fail for other reasons:
    - "Keep editing keeps the edit…" fails on `The finder "Found 0 widgets with text "Keep editing": []" (used in a call to "tap()") could not find any matching widgets`.
    - "a tap that falls through to the outgoing list keeps the opened editor" fails with `Expected: ['d1'] / Actual: ['d2']`: today a second open replaces the first.
    - "a save that lands after its editor closed leaves the next editor open" fails with `Expected: ['d1'] / Actual: []`. Its earlier `pullSaveEnabled()` precondition passes, which proves the save landed while its editor was still mounted. The late save then closed d1.
  - Six tests pass already, because no prompt exists yet. They are **regression guards** against a prompt that must not appear:
    - "untouched, back closes it…"
    - "a count stepped up and back down…"
    - "Save closes without asking"
    - "an edit survives a trip to another tab…"
    - "a start weight stepped up and back down in lb…"
    - "switching to lb behind an untouched editor…"

- [ ] **Step 4: Implement.**

4a. Replace `app/lib/shell/back_dispatch.dart` with:
```dart
/// What the shell should do with an Android back press.
enum BackAction { none, goHome, exit, confirmExit }

/// Priority: a tab that consumed the press wins; otherwise non-home tabs go
/// home; home exits the app, or first asks to discard a Plan editor's
/// unsaved edits ([planEditsAtRisk]), which the exit would lose.
BackAction decideBack({
  required bool tabHandled,
  required int tabIndex,
  required bool planEditsAtRisk,
}) {
  if (tabHandled) return BackAction.none;
  if (tabIndex != 0) return BackAction.goHome;
  return planEditsAtRisk ? BackAction.confirmExit : BackAction.exit;
}
```

4b. The imports in `app/lib/ui/plan_screen.dart`. Replace:
```dart
import 'package:flutter/material.dart';

import '../data/day_template_repository.dart';
```
with:
```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/day_template_repository.dart';
```
Then replace:
```dart
import '../widgets/fit_label.dart';
import '../widgets/pressable.dart';
import 'day_editor.dart';
import 'exercise_editor.dart';
```
with:
```dart
import '../widgets/fit_label.dart';
import '../widgets/pending_input.dart';
import '../widgets/pressable.dart';
import '../widgets/w_dialog.dart';
import 'day_editor.dart';
import 'editor_guard.dart';
import 'exercise_editor.dart';
```

4c. `_EditorRoute`. Replace:
```dart
/// Describes which in-place editor is currently open.
/// [kind] is `'day'` or `'exercise'`; [id] is the row id (null = new).
class _EditorRoute {
  const _EditorRoute({required this.kind, required this.id});
  final String kind; // 'day' | 'exercise'
  final String? id;
}
```
with:
```dart
/// Describes which in-place editor is currently open.
/// [kind] is `'day'` or `'exercise'`; [id] is the row id (null = new).
/// Built fresh for every open, so an editor still fading out can never
/// answer for, or close, the one that replaced it.
class _EditorRoute {
  _EditorRoute({required this.kind, required this.id});
  final String kind; // 'day' | 'exercise'
  final String? id;

  /// Bound by this route's editor to report unsaved edits.
  final EditorGuard guard = EditorGuard();
}
```

4d. The open and close flow in `PlanScreenState`. Each guard here has its own test:
- the ignored second `_openEditor` is pinned by "a tap that falls through…";
- `_closeEditor`'s identity check is pinned by "a save that lands after…";
- `requestClose` has no re-entrancy flag yet. Steps 6–8 add one.

Replace:
```dart
  void _openEditor(_EditorRoute route) => setState(() => _editor = route);

  void _onBack() => setState(() => _editor = null);

  /// Consumes a back press when the in-tab editor is open. Returns true if handled.
  bool handleBack() {
    if (_editor == null) return false;
    _onBack();
    return true;
  }
```
with:
```dart
  /// Opens an editor. Ignored while one is open: the list can then only be
  /// reached by a tap that fell through to the outgoing list while the new
  /// editor was still loading.
  void _openEditor(String kind, String? id) {
    if (_editor != null) return;
    setState(() => _editor = _EditorRoute(kind: kind, id: id));
  }

  /// Closes [route]'s editor if it is still the open one, so a late Save or
  /// Delete never closes an editor opened since.
  void _closeEditor(_EditorRoute route) {
    if (!identical(_editor, route)) return;
    setState(() => _editor = null);
  }

  /// Whether the open editor would lose edits if closed now.
  bool get hasUnsavedEdits => _editor?.guard.isDirty() ?? false;

  /// Closes the open editor, asking first if it holds unsaved edits.
  /// Returns true if the editor closed.
  Future<bool> requestClose() async {
    final route = _editor;
    if (route == null) return false;
    // A typed value still in a focused stepper counts as an edit.
    commitPendingInput();
    if (route.guard.isDirty()) {
      final l = AppLocalizations.of(context);
      final discard = await showWConfirm(
        context,
        title: l.planDiscardTitle,
        message: route.kind == 'day'
            ? l.planDiscardDayMessage
            : l.planDiscardExerciseMessage,
        cancelLabel: l.commonKeepEditing,
        confirmLabel: l.commonDiscard,
        destructive: true,
      );
      // Keep editing, a dismissed dialog, or an editor that changed or
      // closed meanwhile: leave everything as it is.
      if (discard != true || !mounted || !identical(_editor, route)) {
        return false;
      }
    }
    _closeEditor(route);
    return true;
  }

  /// Consumes a back press when the in-tab editor is open. Returns true if
  /// handled; the editor then closes, or asks first, on its own.
  bool handleBack() {
    if (_editor == null) return false;
    unawaited(requestClose());
    return true;
  }
```

4e. The header chevron. In `_buildHeader`, replace:
```dart
                      _BackButton(tokens: tokens, onBack: _onBack),
```
with:
```dart
                      _BackButton(
                        tokens: tokens,
                        onBack: () => unawaited(requestClose()),
                      ),
```
`_BackButton` passes the same `onBack` to its `Semantics.onTap` and to its `GestureDetector.onTap`, so both now go through `requestClose`.

4f. Body routing: each editor gets its route's guard and a close bound to that route. In `_buildBody`, replace:
```dart
    final Widget body;
    if (_editor != null) {
      if (_editor!.kind == 'day') {
        body = DayEditor(id: _editor!.id, onBack: _onBack);
      } else {
        body = ExerciseEditor(id: _editor!.id, onBack: _onBack);
      }
    } else if (_activeTab == 'split') {
      body = SplitTab(
        onOpenEditor: (id) => _openEditor(_EditorRoute(kind: 'day', id: id)),
      );
    } else if (_activeTab == 'targets') {
      body = const TargetsTab();
    } else {
      body = LibraryTab(
        onOpenEditor: (id) =>
            _openEditor(_EditorRoute(kind: 'exercise', id: id)),
      );
    }
```
with:
```dart
    final Widget body;
    final editor = _editor;
    if (editor != null) {
      if (editor.kind == 'day') {
        body = DayEditor(
          id: editor.id,
          onBack: () => _closeEditor(editor),
          guard: editor.guard,
        );
      } else {
        body = ExerciseEditor(
          id: editor.id,
          onBack: () => _closeEditor(editor),
          guard: editor.guard,
        );
      }
    } else if (_activeTab == 'split') {
      body = SplitTab(onOpenEditor: (id) => _openEditor('day', id));
    } else if (_activeTab == 'targets') {
      body = const TargetsTab();
    } else {
      body = LibraryTab(onOpenEditor: (id) => _openEditor('exercise', id));
    }
```
After this edit, `grep -n "_onBack" app/lib/ui/plan_screen.dart` must print nothing.

4g. `app/lib/shell/app_shell.dart`. Replace:
```dart
import 'dart:io' show Platform;
```
with:
```dart
import 'dart:async';
import 'dart:io' show Platform;
```
Then replace:
```dart
  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tabHandled =
            _index == 3 && (_planKey.currentState?.handleBack() ?? false);
        switch (decideBack(tabHandled: tabHandled, tabIndex: _index)) {
          case BackAction.none:
            break;
          case BackAction.goHome:
            setState(() => _index = 0);
          case BackAction.exit:
            SystemNavigator.pop();
        }
      },
```
with:
```dart
  /// Back on Today while a Plan editor holds unsaved edits: shows the
  /// editor and asks, and finishes the exit only if the edits are discarded.
  Future<void> _confirmExit() async {
    setState(() => _index = 3);
    final closed = await _planKey.currentState?.requestClose() ?? false;
    if (!mounted) return;
    if (closed) SystemNavigator.pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tabHandled =
            _index == 3 && (_planKey.currentState?.handleBack() ?? false);
        switch (decideBack(
          tabHandled: tabHandled,
          tabIndex: _index,
          // The hidden tab's typed values are already committed: it lost
          // focus when it was left.
          planEditsAtRisk: _planKey.currentState?.hasUnsavedEdits ?? false,
        )) {
          case BackAction.none:
            break;
          case BackAction.goHome:
            setState(() => _index = 0);
          case BackAction.confirmExit:
            unawaited(_confirmExit());
          case BackAction.exit:
            SystemNavigator.pop();
        }
      },
```

- [ ] **Step 5: Run the tests to verify they pass.** Run `timeout 900 make -C app test TEST="test/shell/back_dispatch_test.dart test/shell/plan_discard_test.dart" > /tmp/claude-1000/guard-discard.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|\[E\]" /tmp/claude-1000/guard-discard.log | tail -3`. Expected: EXIT=0 and `+22: All tests passed!`

- [ ] **Step 6: Write the failing re-entrancy test.** In `app/test/shell/plan_discard_test.dart`, inside `group('day editor', …)`, insert this test immediately before `testWidgets('a predictive back gesture asks before discarding',`:
```dart
    testWidgets('a close requested while one is asking is refused',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final plan = tester.state<PlanScreenState>(find.byType(PlanScreen));
      final first = plan.requestClose();
      final second = plan.requestClose();
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(await second, isFalse);

      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(await first, isTrue);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

```

- [ ] **Step 7: Run it to verify it fails.** Run `timeout 900 make -C app test TEST=test/shell/plan_discard_test.dart > /tmp/claude-1000/guard-reentry.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|\[E\]|Actual" /tmp/claude-1000/guard-reentry.log | tail -4`. Expected: EXIT=2. "a close requested while one is asking is refused" fails with `Actual: _TextWidgetFinder:<Found 2 widgets with text "Discard changes?"`, and the summary reads `+16 -1: Some tests failed.`

- [ ] **Step 8: Make `requestClose` re-entrant-safe.** In `app/lib/ui/plan_screen.dart`, replace:
```dart
  /// Opens an editor. Ignored while one is open: the list can then only be
```
with:
```dart
  /// True while [requestClose] runs: a second call is refused rather than
  /// stacking a second prompt.
  bool _closing = false;

  /// Opens an editor. Ignored while one is open: the list can then only be
```
Then replace the whole `requestClose` method:
```dart
  Future<bool> requestClose() async {
    final route = _editor;
    if (route == null) return false;
    // A typed value still in a focused stepper counts as an edit.
    commitPendingInput();
    if (route.guard.isDirty()) {
      final l = AppLocalizations.of(context);
      final discard = await showWConfirm(
        context,
        title: l.planDiscardTitle,
        message: route.kind == 'day'
            ? l.planDiscardDayMessage
            : l.planDiscardExerciseMessage,
        cancelLabel: l.commonKeepEditing,
        confirmLabel: l.commonDiscard,
        destructive: true,
      );
      // Keep editing, a dismissed dialog, or an editor that changed or
      // closed meanwhile: leave everything as it is.
      if (discard != true || !mounted || !identical(_editor, route)) {
        return false;
      }
    }
    _closeEditor(route);
    return true;
  }
```
with:
```dart
  Future<bool> requestClose() async {
    final route = _editor;
    if (route == null || _closing) return false;
    _closing = true;
    try {
      // A typed value still in a focused stepper counts as an edit.
      commitPendingInput();
      if (route.guard.isDirty()) {
        final l = AppLocalizations.of(context);
        final discard = await showWConfirm(
          context,
          title: l.planDiscardTitle,
          message: route.kind == 'day'
              ? l.planDiscardDayMessage
              : l.planDiscardExerciseMessage,
          cancelLabel: l.commonKeepEditing,
          confirmLabel: l.commonDiscard,
          destructive: true,
        );
        // Keep editing, a dismissed dialog, or an editor that changed or
        // closed meanwhile: leave everything as it is.
        if (discard != true || !mounted || !identical(_editor, route)) {
          return false;
        }
      }
      _closeEditor(route);
      return true;
    } finally {
      _closing = false;
    }
  }
```

- [ ] **Step 9: Run the tests to verify they pass.** This also runs every existing file the change can break: the editors' and Plan's tests, the harness's shell test, the shell layout sweep, ARB parity and main routing.
  - Run `timeout 900 make -C app test TEST="test/shell/back_dispatch_test.dart test/shell/plan_discard_test.dart test/ui/plan_editor_dirty_test.dart test/ui/editor_guard_test.dart test/ui/exercise_editor_rir_test.dart test/ui/day_editor_slot_row_test.dart test/ui/plan_layout_test.dart test/ui/plan_profile_layout_test.dart test/support/screen_harness_test.dart test/l10n/arb_parity_test.dart test/layout/shell_layout_test.dart test/main_routing_test.dart" > /tmp/claude-1000/guard-final.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed|\[E\]" /tmp/claude-1000/guard-final.log | tail -3`.
  - Expected: EXIT=0. In isolation this was `+75: All tests passed!`; the count changes once other tasks add cases to the shared files.
  - Then run the full suite: `timeout 900 make -C app test > /tmp/claude-1000/guard-full.log 2>&1; echo EXIT=$?`. Expected: EXIT=0.

- [ ] **Step 10: Analyze.** Run `make -C app analyze > /tmp/claude-1000/guard-final-analyze.log 2>&1; echo EXIT=$?`, then `tail -3 /tmp/claude-1000/guard-final-analyze.log`. Expected: "No issues found!"

- [ ] **Step 11: Commit.**
```bash
git add app/lib/l10n/app_en.arb app/lib/l10n/app_it.arb app/lib/l10n/app_de.arb app/lib/l10n/app_es.arb app/lib/shell/back_dispatch.dart app/lib/shell/app_shell.dart app/lib/ui/plan_screen.dart app/test/shell/back_dispatch_test.dart app/test/shell/plan_discard_test.dart
git commit -m "fix(app): ask before back or exit discards unsaved plan edits"
```


### Task 13: Record the new rules and verify the whole branch

**Files:**
- Modify: `app/AGENTS.md`. Append three bullets to the `**UI/motion:**` list, directly after the bullet that starts `- Steppers (\`WStepper\`) hold values in the CALLER's space`, and one bullet to the `**Data:**` list, after its last bullet.

**Interfaces:**
- Consumes everything above:
  - `units/unit_format.dart`: `fmtLoad`, `fmtBodyweight`, `fmtVolume`, `fmtCount` and the `round…` helpers;
  - `UnitService.fmtBw` / `fmtVol`;
  - `chartLabelStyle` / `chartChipStyle`;
  - `WSheetAction.selected` / `labelLocale`;
  - `showLanguageSheet`;
  - `EditorGuard`, `daySnapshot` / `exerciseSnapshot`, and `PlanScreenState.requestClose` / `hasUnsavedEdits`;
  - `rirMin` / `rirMax`.
- Produces: nothing new in code.

- [ ] **Step 1: Write the rules down.** In `app/AGENTS.md`, append to the `**UI/motion:**` list, after the long `Steppers (\`WStepper\`)…` bullet:

```markdown
- Every displayed quantity goes through `units/unit_format.dart`, one formatter per quantity:
  - set, top, PR and e1RM weights: `fmtLoad` / `UnitService.fmtWt`. Kg up to 2 dp trimmed, lb whole. This rule is byte-frozen, because the ruler's echo detection and the stepper's untouched-seed check compare its strings.
  - bodyweight: `fmtBodyweight` / `UnitService.fmtBw`, 1 dp with `.0` trimmed, on every screen.
  - volume tiles: `fmtVolume` / `UnitService.fmtVol` (`850kg`, `1.5t`, `3.3k lb`). It takes kg.
  - counts: `fmtCount`, grouped. Display only, never an edit seed.

  A delta is the difference of two `round…` values (`roundLoad`, `roundBodyweight`, `roundCount`), so it is the change the user can read between the numbers on screen. Never subtract raw values and format the result. Never add a second formatter for one of these quantities.
- Never name a font family (`fontFamily:`) in a style. google_fonts registers one family per weight (`HankenGrotesk_600`) and nothing registers the plain name, so a named family silently draws in the platform font. `test/theme/font_family_source_test.dart` fails on any match. Styles come from `WorkoutType`; Material's text theme is `WorkoutType.hankenTextTheme`, always built from its size table.
- `showWActionSheet` is also the app's single-choice picker. Mark the current row with `WSheetAction(selected: true)`, which draws a trailing `accentText` check and sets selected semantics. A row whose label is written in another language (the language sheet's endonyms) passes `labelLocale`. The sheet then wraps the row's own `Semantics` in an outer `Semantics(localeForSubtree:)`. Never put the locale on the label or on the row's own `Semantics`, and never use `MergeSemantics` or `Localizations.override`: each of those splits the node or drops the locale.
- The Plan tab's in-tab editors report unsaved edits through a per-open `EditorGuard` (`ui/editor_guard.dart`).
  - What counts is `daySnapshot` / `exerciseSnapshot` of `_currentDraft()`, the draft Save writes, against a baseline taken right after `_loadData` normalises. A new editor field must flow through `_currentDraft()`, or the discard prompt can't see it.
  - Back from an editor, and back on Today while Plan holds edits, go through `PlanScreenState.requestClose()`.
  - Save and Delete close only their own route.
```

Then append to the `**Data:**` list, after its last bullet:

```markdown
- The RIR range is `rirMin..rirMax` (`data/models.dart`, 0–5) everywhere: the `RirPicker` chips and all four editor steppers read it. A stored RIR outside it (old free-text data, a restore) selects no chip and is never rewritten. A null working-set RIR is a valid "no RIR" and shows no RIR text.
```

- [ ] **Step 2: Verify the whole branch.**
  - Run: `timeout 900 make -C app test > /tmp/claude-1000/branch-full.log 2>&1; echo EXIT=$?`, then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/branch-full.log | tail -2`. Expected: EXIT=0 and `All tests passed!`.
  - Run: `make -C app analyze > /tmp/claude-1000/branch-analyze.log 2>&1; echo EXIT=$?`, then `grep -E "issues? found" /tmp/claude-1000/branch-analyze.log`. Expected: EXIT=0 and `No issues found!`.
  - Run: `grep -rn "fmtPlain\|fmtThousands\|fmtSigned\|util/format.dart\|languageEnglish\|languageGerman\|profileTrainingSince\b.*Mar 2026" app/lib app/test`. Expected: no output.

- [ ] **Step 3: Commit.**
  - `git add app/AGENTS.md`
  - `git commit -m "docs(app): record the formatter, font, sheet, RIR and editor-guard rules"`

### Task 14: Whole-branch review, preview build and device checks (orchestrator)

This task is run by the session that drives the plan, not by an implementer subagent. It needs the user's phone.

**Files:** none changed, unless the review finds something. A fix goes in as its own commit with its own test, then this task restarts at Step 1.

- [ ] **Step 1: Whole-branch review.** A fresh reviewer reads `git diff main...HEAD` against the spec and `app/AGENTS.md`. Confirmed findings are fixed test-first before going on.

- [ ] **Step 2: Push and open the PR so CI runs.**
  - `git push -u origin feat/stop-showing-wrong-things`
  - `gh pr create --base main --head feat/stop-showing-wrong-things --title "fix(app): stop showing wrong things" --body-file /tmp/claude-1000/pr-body.md`. The body lists the five fixes and links the spec and plan. A "Device checks" section is filled in at Step 6.
  - Wait for `app-ci` with `gh pr checks --watch`. Expected: analyze and test pass.

- [ ] **Step 3: Build the preview APK.**
  - Ask the user for the phone's current Wi-Fi adb IP:port (it changes), then `adb connect <ip:port>`.
  - `adb shell dumpsys package io.github.psychonaut0.reps | grep versionCode` (0.17.0 is 37).
  - `gh workflow run android-preview.yml --ref feat/stop-showing-wrong-things -f build_number=<N>`, with N ≥ the installed versionCode and ≤ the next android-release run number (38).
  - `gh run download <run-id> -n reps-preview-apk -D /tmp/claude-1000/preview`, then `adb install -r /tmp/claude-1000/preview/app-release.apk`.

- [ ] **Step 4: Prepare the phone.**
  - Record the current values first: `adb shell settings get global stay_on_while_plugged_in`, `adb shell settings get global zen_mode`, and the app's unit and language as Profile shows them.
  - Then `adb shell svc power stayon true` and `adb shell cmd notification set_dnd priority`.

- [ ] **Step 5: Run the checks, view only.**
  - **Guard:** before every tap and screenshot, check that `adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"` names `io.github.psychonaut0.reps`, and stop if it doesn't.
  - **Never** log a set, save, delete or sign out.
  - Screenshots: `adb exec-out screencap -p > /tmp/claude-1000/shots/<name>.png`.

  The spec's six checks:
  1. **Profile line:** the real first-workout month and day count, in the current language.
  2. **Fonts:** at 1.0× and 2.0× font scale, these are in Hanken Grotesk / JetBrains Mono:
     - login;
     - a SnackBar;
     - the export date-range picker (open, then cancel);
     - the Progress and Bodyweight chart labels.

     Onboarding only if it can be reached without resetting anything. For 2.0×, use `adb shell settings put system font_scale 2.0` and restore the recorded value afterwards.
  3. **lb:** switch the unit to lb in Profile, temporarily. Summary or History volume reads "…k lb", Progress shows whole pounds, and the Today tile matches the bodyweight view. Then switch back.
  4. **RIR:** in History, open a past workout's set editor. The 0–5 picker shows in one row or two, as the phone's width dictates. Do not tap a chip: the sheet autosaves.
  5. **Language:** the sheet shows endonyms with the current one checked. If TalkBack's tutorial can be skipped, check that it reads "Deutsch" in German. Restore the original language.
  6. **Discard:**
     - Open a Plan day and step a count. The chevron asks, the back gesture asks, and Today → back asks. At that last prompt choose Keep editing: Discard there completes the exit and closes the app.
     - Keep editing keeps the change, and Discard throws it away.
     - An untouched editor closes silently.
     - Never tap Save.

- [ ] **Step 6: Restore the phone and report.**
  - `adb shell svc power stayon <recorded>`, `adb shell settings put global zen_mode <recorded>`, and `font_scale` back to the recorded value. The app's unit and language should already be restored.
  - Write each check's result, with its screenshot names, into the PR body's "Device checks" section: `gh pr edit --body-file …`.

- [ ] **Step 7: Stop.** Hand the PR to the user to merge and release. The recommended version is 0.18.0, with the pubspec bumped to `0.18.0+N` at release time. Do not merge, tag or bump.
