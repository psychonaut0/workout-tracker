# Chart & Data Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Put the weekly-volume target tick where it belongs.
- Show bodyweight deltas signed and coloured by a new Cut / Bulk / Maintain goal.
- Space line charts by date.
- Keep the last-point value label off the line.

**Architecture:** The logic lives in small pure functions, each unit-tested:
- `dateFractions` and `valueLabelOrigin` in `line_chart.dart`;
- `bodyweightDeltaTone` and `fmtSigned`;
- `BodyweightGoal`, persisted by `SettingsService`.

The widgets only consume those functions. The bodyweight history card is made public so it can be widget-tested; the screen itself owns a PowerSync watch stream and cannot be mounted in tests.

**Tech Stack:** Flutter via fvm (always `make -C app …`), provider, shared_preferences, flutter_test, gen-l10n ARB (en/it/de/es).

**Spec:** `docs/superpowers/specs/2026-09-25-chart-correctness-design.md`

## Global Constraints

- Run every command from the repo root as `make -C app …`. Never `cd`, and never call `flutter` directly.
- `make -C app analyze` must report "No issues found".
- Harness gotcha: a bare `make -C app test` gets auto-backgrounded. Always run it as `timeout 400 make -C app test [TEST=…] > /tmp/x.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/x.log`.
- New user-visible strings go into all four ARB files; `app/test/l10n/arb_parity_test.dart` enforces it. The generated `app_localizations*.dart` files are gitignored: run `make -C app get` to regenerate them and never commit them.
- Confirm dialogs use `showWConfirm`/`showWDialog` only, and action menus use `showWActionSheet`. Every duration goes through `Motion.of(context, …)`, and every `Expanded`/`Flexible` must be a direct child of its Row/Column.
- Commits are Conventional Commits with a subject line only: no body, no trailer lines (no "Claude-Session:"). No plan or task numbers in code or comments.
- The signed minus is U+2212 (`−`), never a hyphen.
- The goal persists under the key `settings.bodyweight_goal` as the enum name. An absent or unknown value → `maintain`.

## Review Focus

1. **A goal switched while Bodyweight is open:** colours must update without a restart. `BodyweightView` must `context.watch<SettingsService>()`; this is covered in Task 4 by the history-card widget test taking the goal as a parameter, and by a device check.
2. **Several bodyweight entries on the same date, or one entry:** `dateFractions` must not divide by zero. Task 2 covers equal dates and a single date.
3. **The last point at the top-right corner of the chart:** the label must flip left or below and stay inside the canvas. Task 2 covers both edges.
4. **A zero delta:** it shows "0", neutral, never "−0" or "+0". Covered by the `fmtSigned` test in Task 3.
5. **An existing install with no stored goal:** it reads `maintain` and nothing is coloured. Covered by the defaults test in Task 3.

---

### Task 1: Volume target tick at the right end

**Files:**
- Modify: `app/lib/widgets/volume_bars.dart`
- Test: `app/test/widgets/volume_bars_test.dart`

- [ ] **Step 1: Write the failing test.** Append inside `main()` of `app/test/widgets/volume_bars_test.dart`:

```dart
  testWidgets('the target tick sits at the right end of the track', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      home: const Scaffold(
        body: VolumeBars(rows: [(muscle: 'chest', sets: 11, target: 12)]),
      ),
    ));
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byKey(const Key('volume-track')));
    final tick = tester.getRect(find.byKey(const Key('volume-target-tick')));
    expect(tick.center.dx, closeTo(track.right, 1.0));
    expect(tick.height, greaterThan(track.height)); // overhangs the track
  });
```

- [ ] **Step 2: Run it and confirm it fails.** `timeout 400 make -C app test TEST=test/widgets/volume_bars_test.dart > /tmp/t1.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|Expected|Actual" /tmp/t1.log`. Expected: FAIL, because no widget with key `volume-track` exists yet.

- [ ] **Step 3: Implement.** In `_VolumeRow.build`:
  - Delete the `const tickFraction = 1.0;` line and its comment.
  - Give the background track `Container` the key `Key('volume-track')`.
  - Replace the whole `Align(alignment: …, child: OverflowBox(…))` target-tick block with:

```dart
                // Target tick at the track's right end (bars are scaled to
                // their own target), overhanging it by 3 px above and below.
                Positioned(
                  right: -0.75,
                  top: -3,
                  bottom: -3,
                  child: Container(
                    key: const Key('volume-target-tick'),
                    width: 1.5,
                    color: tokens.text.withValues(alpha: 0.4),
                  ),
                ),
```

  Then update the class doc bullet to: "with the 1.5 px target tick at the right end of the track".

- [ ] **Step 4: Run and confirm it passes.** Run the same command. Expected: PASS, and the other tests in the file still pass.

- [ ] **Step 5: Commit.** `git add app/lib/widgets/volume_bars.dart app/test/widgets/volume_bars_test.dart && git commit -m "fix(app): draw the weekly volume target tick at the end of the bar"`

---

### Task 2: Date-spaced line charts and an off-line value label

**Files:**
- Modify: `app/lib/widgets/line_chart.dart`
- Test: `app/test/widgets/line_chart_math_test.dart` (new)

**Interfaces produced:**
- `List<double> dateFractions(List<String> isoDates)`
- `Offset valueLabelOrigin({required Offset point, required Size label, required Size canvas, double gap = 8})`

- [ ] **Step 1: Write the failing tests.** Create `app/test/widgets/line_chart_math_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/line_chart.dart';

void main() {
  group('dateFractions', () {
    test('positions points by date, not by index', () {
      final f = dateFractions(['2026-06-01', '2026-06-02', '2026-06-11']);
      expect(f[0], 0);
      expect(f[1], closeTo(0.1, 1e-9));
      expect(f[2], 1);
    });

    test('points on the same date share an x', () {
      final f = dateFractions(['2026-06-01', '2026-06-05', '2026-06-05', '2026-06-09']);
      expect(f[1], f[2]);
      expect(f[1], closeTo(0.5, 1e-9));
    });

    test('all dates equal falls back to even spacing by index', () {
      expect(dateFractions(['2026-06-01', '2026-06-01', '2026-06-01']), [0, 0.5, 1]);
    });

    test('an unparseable date falls back to its index fraction', () {
      final f = dateFractions(['2026-06-01', 'garbage', '2026-06-03']);
      expect(f[1], closeTo(0.5, 1e-9));
    });

    test('a single point sits at 0', () {
      expect(dateFractions(['2026-06-01']), [0]);
    });
  });

  group('valueLabelOrigin', () {
    const canvas = Size(300, 200);
    const label = Size(60, 20);

    test('prefers above-right of the point', () {
      final o = valueLabelOrigin(point: const Offset(100, 100), label: label, canvas: canvas);
      expect(o, const Offset(108, 72));
    });

    test('flips to the left when it would overflow the right edge', () {
      final o = valueLabelOrigin(point: const Offset(290, 100), label: label, canvas: canvas);
      expect(o.dx, 290 - 8 - 60);
      expect(o.dy, 72);
    });

    test('drops below the point when it would overflow the top', () {
      final o = valueLabelOrigin(point: const Offset(100, 10), label: label, canvas: canvas);
      expect(o.dy, 10 + 8);
    });

    test('never leaves the canvas', () {
      final o = valueLabelOrigin(point: const Offset(295, 5), label: label, canvas: canvas);
      expect(o.dx, inInclusiveRange(0, canvas.width - label.width));
      expect(o.dy, inInclusiveRange(0, canvas.height - label.height));
    });
  });
}
```

- [ ] **Step 2: Run them and confirm they fail.** `timeout 400 make -C app test TEST=test/widgets/line_chart_math_test.dart > /tmp/t2.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|Error" /tmp/t2.log`. Expected: a compile failure, because the functions are undefined.

- [ ] **Step 3: Implement.** In `app/lib/widgets/line_chart.dart`, add these top-level functions above `class LineChart`:

```dart
/// Each ISO date's position in [0, 1] between the first and last date, so a
/// chart's x spacing reflects time rather than entry order. Equal dates share
/// an x. When every date is the same (or there is one point) the points are
/// spaced evenly by index instead; an unparseable date also falls back to its
/// index fraction.
List<double> dateFractions(List<String> isoDates) {
  final n = isoDates.length;
  if (n == 1) return const [0];
  double byIndex(int i) => i / (n - 1);
  // Calendar days in UTC, so a daylight-saving change can't make a day 23 or
  // 25 hours long.
  final days = isoDates.map((d) {
    final p = DateTime.tryParse(d);
    return p == null ? null : DateTime.utc(p.year, p.month, p.day);
  }).toList();
  final valid = days.whereType<DateTime>().toList();
  if (valid.length < 2) return [for (var i = 0; i < n; i++) byIndex(i)];
  final first = valid.reduce((a, b) => a.isBefore(b) ? a : b);
  final last = valid.reduce((a, b) => a.isAfter(b) ? a : b);
  final span = last.difference(first).inHours;
  if (span == 0) return [for (var i = 0; i < n; i++) byIndex(i)];
  return [
    for (var i = 0; i < n; i++)
      days[i] == null ? byIndex(i) : days[i]!.difference(first).inHours / span,
  ];
}

/// Where to put the chart's last-point value label so it never covers the
/// line: above-right of [point], flipped left when that overflows the right
/// edge, dropped below the point when it overflows the top, and always
/// clamped inside [canvas].
Offset valueLabelOrigin({
  required Offset point,
  required Size label,
  required Size canvas,
  double gap = 8,
}) {
  var x = point.dx + gap;
  if (x + label.width > canvas.width) x = point.dx - gap - label.width;
  var y = point.dy - gap - label.height;
  if (y < 0) y = point.dy + gap;
  return Offset(
    x.clamp(0.0, math.max(0.0, canvas.width - label.width)),
    y.clamp(0.0, math.max(0.0, canvas.height - label.height)),
  );
}
```

Then make these changes:
- Change `import 'dart:math';` to `import 'dart:math' as math;` and prefix the existing uses: `math.min`, `math.max`, `values.reduce(math.min)`, `values.reduce(math.max)`.
- In `paint`, replace `double xAt(int i) => _padL + (i / (n - 1)) * iw;` with:

```dart
    final fractions = dateFractions([for (final s in series) s.date]);
    double xAt(int i) => _padL + fractions[i] * iw;
```

- Replace the floating value label block (from `// Floating value label` through its `_paintText(...)` call) with:

```dart
    // Value label on a small chip beside the last point — placed so it never
    // covers the line's final segment.
    final label =
        '${fmtPlain(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}';
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
    const chipPad = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final chipSize = Size(tp.width + chipPad.horizontal, tp.height + chipPad.vertical);
    final origin = valueLabelOrigin(
      point: Offset(lastX, lastY),
      label: chipSize,
      canvas: size,
      gap: 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(origin & chipSize, const Radius.circular(6)),
      Paint()..color = bg,
    );
    tp.paint(canvas, origin + Offset(chipPad.left, chipPad.top));
```

- Update the class doc so it mentions that x is spaced by date and the label sits on a chip beside the last point.

- [ ] **Step 4: Run and confirm the tests pass.** Run the Step 2 command. Expected: PASS. Then run the full suite (see Global Constraints) and `timeout 300 make -C app analyze > /tmp/a.log 2>&1; echo EXIT=$?; tail -5 /tmp/a.log`. Expected: all tests green and "No issues found".

- [ ] **Step 5: Commit.** `git add app/lib/widgets/line_chart.dart app/test/widgets/line_chart_math_test.dart && git commit -m "fix(app): space line charts by date and keep the value label off the line"`

---

### Task 3: Bodyweight goal setting, delta tone and signed formatting

**Files:**
- Create: `app/lib/settings/bodyweight_goal.dart`
- Modify: `app/lib/settings/settings_service.dart`, `app/lib/util/format.dart`, `app/lib/ui/profile_screen.dart`, `app/lib/l10n/app_{en,it,de,es}.arb`
- Test: `app/test/settings/bodyweight_goal_test.dart` (new), `app/test/util/format_signed_test.dart` (new)

**Interfaces produced:**
- `enum BodyweightGoal { cut, bulk, maintain }`
- `enum DeltaTone { good, neutral }`
- `DeltaTone bodyweightDeltaTone(double delta, BodyweightGoal goal)`
- `SettingsService.bodyweightGoal` and `Future<void> setBodyweightGoal(BodyweightGoal)`
- `String fmtSigned(double v)` in `util/format.dart`
- Strings: `profileGroupBodyweight`, `profileGoal`, `goalCut`, `goalBulk`, `goalMaintain`

- [ ] **Step 1: Write the failing tests.**

`app/test/settings/bodyweight_goal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/bodyweight_goal.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('bodyweightDeltaTone', () {
    test('a loss is good only on cut', () {
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.cut), DeltaTone.good);
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.bulk), DeltaTone.neutral);
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.maintain), DeltaTone.neutral);
    });
    test('a gain is good only on bulk', () {
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.bulk), DeltaTone.good);
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.cut), DeltaTone.neutral);
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.maintain), DeltaTone.neutral);
    });
    test('no change is always neutral', () {
      for (final g in BodyweightGoal.values) {
        expect(bodyweightDeltaTone(0, g), DeltaTone.neutral);
      }
    });
  });

  group('SettingsService goal', () {
    test('defaults to maintain', () async {
      final s = SettingsService();
      await s.load();
      expect(s.bodyweightGoal, BodyweightGoal.maintain);
    });
    test('persists and notifies', () async {
      final s = SettingsService();
      await s.load();
      var notified = 0;
      s.addListener(() => notified++);
      await s.setBodyweightGoal(BodyweightGoal.cut);
      expect(notified, 1);
      final s2 = SettingsService();
      await s2.load();
      expect(s2.bodyweightGoal, BodyweightGoal.cut);
    });
    test('an unknown stored value reads as maintain', () async {
      SharedPreferences.setMockInitialValues({'settings.bodyweight_goal': 'shred'});
      final s = SettingsService();
      await s.load();
      expect(s.bodyweightGoal, BodyweightGoal.maintain);
    });
  });
}
```

`app/test/util/format_signed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/format.dart';

void main() {
  test('fmtSigned signs gains and losses with a true minus, and zero plain', () {
    expect(fmtSigned(0.3), '+0.3');
    expect(fmtSigned(-1), '−1');
    expect(fmtSigned(-1.04), '−1');
    expect(fmtSigned(0), '0');
    expect(fmtSigned(-0.04), '0'); // rounds to zero → unsigned
  });
}
```

- [ ] **Step 2: Run and confirm they fail.** `timeout 400 make -C app test TEST=test/settings/bodyweight_goal_test.dart > /tmp/t3.log 2>&1; echo EXIT=$?; grep -E "All tests passed|Some tests failed|Error" /tmp/t3.log` (and the same for `test/util/format_signed_test.dart`). Expected: compile failures.

- [ ] **Step 3: Implement.**

Create `app/lib/settings/bodyweight_goal.dart`:

```dart
/// What the user wants their bodyweight to do. Drives which direction of
/// change the Bodyweight screen colours as progress.
enum BodyweightGoal { cut, bulk, maintain }

/// Whether a bodyweight change reads as progress ([good]) or is just shown.
enum DeltaTone { good, neutral }

/// A loss is progress on [BodyweightGoal.cut], a gain on [BodyweightGoal.bulk];
/// nothing is on [BodyweightGoal.maintain], and no change never is.
DeltaTone bodyweightDeltaTone(double delta, BodyweightGoal goal) => switch (goal) {
      BodyweightGoal.cut when delta < 0 => DeltaTone.good,
      BodyweightGoal.bulk when delta > 0 => DeltaTone.good,
      _ => DeltaTone.neutral,
    };
```

In `app/lib/util/format.dart`, add after `fmtPlain`:

```dart
/// A signed [fmtPlain]: "+0.3", "−1" (U+2212, the width of "+"), or "0" when
/// the value rounds to zero at one decimal.
String fmtSigned(double v) {
  final s = fmtPlain(v.abs());
  if (s == '0') return '0';
  return v > 0 ? '+$s' : '−$s';
}
```

In `app/lib/settings/settings_service.dart`:
- Import `'bodyweight_goal.dart'`.
- Add the field `BodyweightGoal _bodyweightGoal = BodyweightGoal.maintain;` and the getter `BodyweightGoal get bodyweightGoal => _bodyweightGoal;`.
- In `load()`, after `_lastUpdateCheckMs`, add:

```dart
    final storedGoal = prefs.getString('settings.bodyweight_goal');
    _bodyweightGoal = BodyweightGoal.values
        .firstWhere((g) => g.name == storedGoal, orElse: () => BodyweightGoal.maintain);
```

- Add this setter next to `setAutoCheckUpdates`:

```dart
  /// Set the bodyweight goal and persist.
  Future<void> setBodyweightGoal(BodyweightGoal goal) async {
    if (goal == _bodyweightGoal) return;
    _bodyweightGoal = goal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings.bodyweight_goal', goal.name);
    notifyListeners();
  }
```

**Strings.** Insert after `"profileWeightUnitSub"` in each ARB file. The en template needs no metadata because none of these take placeholders.
- en:

```json
  "profileGroupBodyweight": "Bodyweight",
  "profileGoal": "Goal",
  "goalCut": "Cut",
  "goalBulk": "Bulk",
  "goalMaintain": "Maintain",
```

- it: `"profileGroupBodyweight": "Peso corporeo"`, `"profileGoal": "Obiettivo"`, `"goalCut": "Definizione"`, `"goalBulk": "Massa"`, `"goalMaintain": "Mantenimento"`
- de: `"profileGroupBodyweight": "Körpergewicht"`, `"profileGoal": "Ziel"`, `"goalCut": "Diät"`, `"goalBulk": "Aufbau"`, `"goalMaintain": "Halten"`
- es: `"profileGroupBodyweight": "Peso corporal"`, `"profileGoal": "Objetivo"`, `"goalCut": "Definición"`, `"goalBulk": "Volumen"`, `"goalMaintain": "Mantener"`

Then run `timeout 300 make -C app get > /tmp/g.log 2>&1; echo EXIT=$?` to regenerate.

**Profile.** In `app/lib/ui/profile_screen.dart`:
- Import `../settings/bodyweight_goal.dart` and `../widgets/w_action_sheet.dart` (skip either if already imported).
- Add a helper method on the screen's State:

```dart
  String _goalLabel(AppLocalizations l, BodyweightGoal g) => switch (g) {
        BodyweightGoal.cut => l.goalCut,
        BodyweightGoal.bulk => l.goalBulk,
        BodyweightGoal.maintain => l.goalMaintain,
      };

  Future<void> _pickGoal(BuildContext context, SettingsService settings) async {
    final l = AppLocalizations.of(context);
    final picked = await showWActionSheet<BodyweightGoal>(context,
        title: l.profileGoal,
        actions: [
          for (final g in BodyweightGoal.values)
            WSheetAction(
              label: _goalLabel(l, g),
              value: g,
              icon: g == settings.bodyweightGoal ? WIcons.check : WIcons.target,
            ),
        ]);
    if (picked != null) await settings.setBodyweightGoal(picked);
  }
```

- Right after the Units `_Group(...)`, insert:

```dart
                // ── Bodyweight ──────────────────────────────────────────────
                _Group(
                  label: l.profileGroupBodyweight,
                  children: [
                    _Row(
                      icon: WIcons.scale,
                      title: l.profileGoal,
                      sub: _goalLabel(l, settings.bodyweightGoal),
                      onTap: () => _pickGoal(context, settings),
                    ),
                  ],
                ),
```

Confirm that `_Row` renders a chevron or row affordance when `onTap` is set. If it does not, match what the Language row (which has `onTap`) looks like and do nothing extra.

- [ ] **Step 4: Run and confirm they pass.** Run both Step 2 commands, then `test/l10n/arb_parity_test.dart`, the full suite, and analyze. Expected: all green and "No issues found".

- [ ] **Step 5: Commit.** `git add app/lib/settings/ app/lib/util/format.dart app/lib/ui/profile_screen.dart app/lib/l10n/ app/test/settings/bodyweight_goal_test.dart app/test/util/format_signed_test.dart && git commit -m "feat(app): add a cut, bulk or maintain bodyweight goal"`

---

### Task 4: Signed, goal-coloured bodyweight deltas

**Files:**
- Modify: `app/lib/ui/bodyweight_view.dart`
- Test: `app/test/ui/bodyweight_history_card_test.dart` (new)

**Interfaces consumed:** `BodyweightGoal`, `bodyweightDeltaTone`, `DeltaTone`, `fmtSigned`, and `SettingsService.bodyweightGoal`.

**Produced:** `class BodyweightHistoryCard extends StatelessWidget { const BodyweightHistoryCard({super.key, required List<({String date, double value, int reps, bool isPr})> series, required String unit, required BodyweightGoal goal}); }`

- [ ] **Step 1: Write the failing test.** Create `app/test/ui/bodyweight_history_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/settings/bodyweight_goal.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/ui/bodyweight_view.dart';

import '../support/l10n_harness.dart';

final _series = [
  (date: '2026-09-06', value: 67.0, reps: 0, isPr: false),
  (date: '2026-09-18', value: 67.3, reps: 0, isPr: false), // +0.3
  (date: '2026-09-24', value: 66.3, reps: 0, isPr: false), // −1
];

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  testWidgets('deltas are always signed, with a true minus', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.maintain))));
    expect(find.text('−1'), findsOneWidget);
    expect(find.text('+0.3'), findsOneWidget);
  });

  testWidgets('on cut, a loss is accent and a gain is neutral', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.cut))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(_colorOf(tester, '−1'), tokens.accent);
    expect(_colorOf(tester, '+0.3'), tokens.dim);
  });

  testWidgets('on maintain nothing is coloured', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.maintain))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(_colorOf(tester, '−1'), tokens.dim);
    expect(_colorOf(tester, '+0.3'), tokens.dim);
  });

  testWidgets('the date fits on one line', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: SizedBox(width: 360, child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.cut)))));
    // One line of 12pt mono, never wrapped (it may ellipsize at large scales).
    final date = find.textContaining('24');
    expect(tester.getSize(date.first).height, lessThan(24));
  });
}
```

- [ ] **Step 2: Run and confirm it fails.** `timeout 400 make -C app test TEST=test/ui/bodyweight_history_card_test.dart > /tmp/t4.log 2>&1; echo EXIT=$?; grep -E "All tests passed|Some tests failed|Error" /tmp/t4.log`. Expected: a compile failure, because `BodyweightHistoryCard` is undefined.

- [ ] **Step 3: Implement.** In `app/lib/ui/bodyweight_view.dart`:
- Import `../settings/bodyweight_goal.dart` and `../settings/settings_service.dart`.
- In `_BodyweightViewState.build`, next to `unitService`, add `final goal = context.watch<SettingsService>().bodyweightGoal;`.
- Pass `goal: goal` to `_BwStatRow` and to the history card.

Rename `_HistoryCard` to a public `BodyweightHistoryCard`:
- Add `required this.goal` and the field `final BodyweightGoal goal;`.
- Update its call site to `BodyweightHistoryCard(series: series, unit: unit, goal: goal)`.
- In its build, change the date `SizedBox(width: 64, …)` to `width: 92`, and give that `Text` `maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false`.
- Replace the whole three-branch delta block (the `if (diff < 0) … else if (diff > 0) … else …` after `const Spacer(),`) with:

```dart
                // Signed, and accent only when it moves the way the goal wants.
                if (prevValue != null)
                  Text(
                    fmtSigned(diff),
                    style: WorkoutType.mono(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: bodyweightDeltaTone(diff, goal) == DeltaTone.good
                          ? tokens.accent
                          : tokens.dim,
                    ),
                  ),
```

In `_BwStatRow`:
- Add `required this.goal` and `final BodyweightGoal goal;`.
- Delete its local `fmtSigned` function; it now uses the shared one from `util/format.dart`, which is already imported.
- Change the 30-day `BigStat(… value: fmtSigned(delta30), …, accent: true)` to `accent: bodyweightDeltaTone(delta30, goal) == DeltaTone.good`.
- In the empty-series branch, change that tile's `accent: true` to `accent: false`.

Update the class doc of `BodyweightView`: "a scrollable history of the last 24 entries with signed deltas, accent-coloured only when they move toward the Profile goal (cut: loss, bulk: gain, maintain: never)".

- [ ] **Step 4: Run and confirm it passes.** Run the Step 2 command, then the full suite and analyze. Expected: all green and "No issues found".

- [ ] **Step 5: Commit.** `git add app/lib/ui/bodyweight_view.dart app/test/ui/bodyweight_history_card_test.dart && git commit -m "feat(app): sign bodyweight deltas and colour them by goal"`

---

## Device checks (after merge to a preview build)

1. Today: the weekly-volume ticks sit at the right end of each bar, and a muscle at or over target fills in lime.
2. Bodyweight chart: the gaps between points follow the dates, and the last value sits on a chip beside the point, never on the line.
3. Profile → Bodyweight → Goal: the sheet shows three goals with the current one checked.
   - Cut: losses turn lime in History and the 30-day tile.
   - Bulk: gains turn lime.
   - Maintain: everything is neutral.
4. Switch the goal, then go back to Progress → Bodyweight: the colours have changed without restarting the app.
5. History dates show "Thu 24 Sep" on one line.
6. An exercise chart in Progress also spaces its points by session date.
