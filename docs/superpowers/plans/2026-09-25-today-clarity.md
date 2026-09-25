# Today Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Today tell one story. It follows the rotation only; the week strip selects the hero's day (no more pager dots or arrows); the greeting reflects an active workout; the stat tiles compare against last week; and the misleading Recent-PRs count goes away.

**Architecture:**
- The wording logic lives in pure functions in a new `app/lib/ui/today_labels.dart` (unit-tested).
- `WeekStrip` and `SplitCard` gain an optional, parent-controlled selection (widget-tested). Leaving the selection out keeps the old behaviour.
- `TodayScreen` wires them together. It owns PowerSync watch streams, so it cannot be mounted in a widget test (project rule); it is verified through the helpers, the widgets, analyze, and a device check.

**Tech Stack:** Flutter via fvm (always `make -C app …`), provider, flutter_test, gen-l10n ARB (en/it/de/es).

**Spec:** `docs/superpowers/specs/2026-09-25-today-clarity-design.md`

## Global Constraints

- **Commands:**
  - Run everything from the repo root as `make -C app …`. Never `cd`, and never run `flutter` directly.
  - Run `make -C app get` first, and again after editing ARB files. The generated `app_localizations*.dart` files are gitignored; never commit them.
  - Harness gotcha: a bare `make -C app test` gets auto-backgrounded. Always run `timeout 400 make -C app test [TEST=…] > /tmp/x.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/x.log`.
  - `make -C app analyze` must report "No issues found".
- **Strings:** every new string goes into all four ARB files (`arb_parity_test` enforces this). Edit the ARB files as text: insert only the new lines, and delete keys only when nothing references them.
- **Project rules:** every duration goes through `Motion.of(context, …)`. `Expanded`/`Flexible` must be direct children of their Row/Column. Never create `db.watch()` streams in `build()`: cache them in `late final` fields initialised in `initState`, as `TodayScreen` already does.
- **Formatting:** the signed minus is U+2212 (`−`), never a hyphen.
- **Tap targets:** every new tappable is at least 48dp tall, and any icon-only tappable gets a Semantics label.
- **Commits:** Conventional Commits, subject line only, no body, no trailer lines (no "Claude-Session:"). No plan or task numbers in code.

## Review Focus

1. **Finishing a workout while a non-next day is selected.** The rotation moves on, so the selection must reset and follow the new next day. The reset lives in `_recomputeRotation` (Task 4) and is covered by a device check.
2. **The strip and the hero staying in sync both ways.** A chip tap moves the hero; a hero swipe moves the chip. Task 3 covers the SplitCard side (an external `selectedIndex` animates the pager; a swipe calls `onSelectedChanged`). Task 2 covers the strip side (`onSelect`).
3. **Many days on a narrow phone.** The strip must not overflow at 320dp and 1.3×. Task 2 has an overflow test with 6 days in Italian.
4. **No training days at all.** There is no strip, the hero shows only Custom, and the header shows only the date. Task 1's helper test covers the header; the strip already renders nothing for an empty list.
5. **The week-over-week delta at zero and in both directions.** Task 1's `setsVsLastWeek` test covers +, − and "same".

---

### Task 1: Strings, label helpers and the last-week query

**Files:**
- Create: `app/lib/ui/today_labels.dart`
- Test: `app/test/ui/today_labels_test.dart`
- Modify: `app/lib/data/stats_repository.dart`, `app/lib/l10n/app_{en,it,de,es}.arb`

**Interfaces produced:**
- `String todayHeaderLine(AppLocalizations l, {required String date, String? nextName, String? activeName})`
- `String setsVsLastWeek(AppLocalizations l, int thisWeek, int lastWeek)`
- `Stream<int> StatsRepository.watchSetsLastWeek({required DateTime weekStart})`
- Strings:
  - `todayNext(String name)`
  - `todayWorkoutInProgress`
  - `todaySetsThisWeek`
  - `todayPrsThisWeek`
  - `todayVsLastWeek(String delta)`
  - `todaySameAsLastWeek`
  - `todayLastPr(String name)`
  - `todayNoPrsShort`
  - `weekStripCustom`

- [ ] **Step 1: Write the failing test.** Create `app/test/ui/today_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/ui/today_labels.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  group('todayHeaderLine', () {
    test('names the next day in rotation', () {
      expect(todayHeaderLine(l, date: 'Thu 24 Sep', nextName: 'Lower B'),
          'Thu 24 Sep · Next: Lower B');
    });
    test('an active workout wins over the rotation', () {
      expect(
          todayHeaderLine(l, date: 'Thu 24 Sep', nextName: 'Lower B', activeName: 'Upper B'),
          'Thu 24 Sep · Upper B');
    });
    test('no training days: the date alone', () {
      expect(todayHeaderLine(l, date: 'Thu 24 Sep'), 'Thu 24 Sep');
    });
  });

  group('setsVsLastWeek', () {
    test('more sets than last week', () {
      expect(setsVsLastWeek(l, 28, 23), '+5 vs last wk');
    });
    test('fewer sets, with a true minus', () {
      expect(setsVsLastWeek(l, 23, 31), '−8 vs last wk');
    });
    test('the same', () {
      expect(setsVsLastWeek(l, 12, 12), 'same as last wk');
    });
    test('nothing last week', () {
      expect(setsVsLastWeek(l, 23, 0), '+23 vs last wk');
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** `timeout 400 make -C app test TEST=test/ui/today_labels_test.dart > /tmp/t1.log 2>&1; echo EXIT=$?; grep -E "All tests passed|Some tests failed|Error" /tmp/t1.log`. Expected: a compile failure.

- [ ] **Step 3: Implement.**

**Strings.** Insert after `"todayResumeWorkout"` (and its metadata, if it has any) in `app_en.arb`:

```json
  "todayNext": "Next: {name}",
  "@todayNext": {"placeholders": {"name": {"type": "String"}}},
  "todayWorkoutInProgress": "Workout in progress",
  "todaySetsThisWeek": "Sets this week",
  "todayPrsThisWeek": "PRs this week",
  "todayVsLastWeek": "{delta} vs last wk",
  "@todayVsLastWeek": {"placeholders": {"delta": {"type": "String"}}},
  "todaySameAsLastWeek": "same as last wk",
  "todayLastPr": "last: {name}",
  "@todayLastPr": {"placeholders": {"name": {"type": "String"}}},
  "todayNoPrsShort": "none yet",
  "weekStripCustom": "Custom",
```

Insert the same keys, values only with no `@` metadata, after `"todayResumeWorkout"` in the other three files:
- it: `"todayNext": "Prossimo: {name}"`, `"todayWorkoutInProgress": "Allenamento in corso"`, `"todaySetsThisWeek": "Serie questa settimana"`, `"todayPrsThisWeek": "PR questa settimana"`, `"todayVsLastWeek": "{delta} vs sett. scorsa"`, `"todaySameAsLastWeek": "come la sett. scorsa"`, `"todayLastPr": "ultimo: {name}"`, `"todayNoPrsShort": "ancora nessuno"`, `"weekStripCustom": "Libero"`
- de: `"todayNext": "Als Nächstes: {name}"`, `"todayWorkoutInProgress": "Training läuft"`, `"todaySetsThisWeek": "Sätze diese Woche"`, `"todayPrsThisWeek": "PRs diese Woche"`, `"todayVsLastWeek": "{delta} ggü. Vorwoche"`, `"todaySameAsLastWeek": "wie Vorwoche"`, `"todayLastPr": "zuletzt: {name}"`, `"todayNoPrsShort": "noch keine"`, `"weekStripCustom": "Frei"`
- es: `"todayNext": "Siguiente: {name}"`, `"todayWorkoutInProgress": "Entrenamiento en curso"`, `"todaySetsThisWeek": "Series esta semana"`, `"todayPrsThisWeek": "PR esta semana"`, `"todayVsLastWeek": "{delta} vs sem. pasada"`, `"todaySameAsLastWeek": "igual que sem. pasada"`, `"todayLastPr": "último: {name}"`, `"todayNoPrsShort": "ninguno aún"`, `"weekStripCustom": "Libre"`

Validate each file with `python3 -m json.tool FILE > /dev/null && echo ok`, then run `timeout 300 make -C app get > /tmp/g.log 2>&1; echo EXIT=$?`.

**Helpers.** Create `app/lib/ui/today_labels.dart`:

```dart
import '../l10n/app_localizations.dart';

/// Today's header line: the date, then either the workout in progress or the
/// next day in rotation. Today follows the rotation only — the weekday
/// schedule never decides what comes next.
String todayHeaderLine(
  AppLocalizations l, {
  required String date,
  String? nextName,
  String? activeName,
}) {
  if (activeName != null) return '$date · $activeName';
  if (nextName != null) return '$date · ${l.todayNext(nextName)}';
  return date;
}

/// The sets tile's comparison with last week: "+5 vs last wk", "−8 vs last
/// wk" (U+2212), or "same as last wk".
String setsVsLastWeek(AppLocalizations l, int thisWeek, int lastWeek) {
  final d = thisWeek - lastWeek;
  if (d == 0) return l.todaySameAsLastWeek;
  return l.todayVsLastWeek(d > 0 ? '+$d' : '−${-d}');
}
```

**Query.** In `app/lib/data/stats_repository.dart`, add after `watchSetsThisWeek`. Mirror that method's exact style: the same `db.watch` call shape, named `parameters:`, and the same `.map` to the first row's `n`.

```dart
  /// Live count of working sets logged in the week before [weekStart]
  /// (`[weekStart − 7 days, weekStart)`), for Today's week-over-week line.
  Stream<int> watchSetsLastWeek({required DateTime weekStart}) {
    final from = isoDate(weekStart.subtract(const Duration(days: 7)));
    final to = isoDate(weekStart);
    // SQL: SELECT COUNT(*) AS n FROM sets s JOIN sessions se ON se.id = s.session_id
    //      WHERE s.is_warmup = 0 AND se.date >= ? AND se.date < ?
  }
```

Write the body by copying `watchSetsThisWeek`, adding the upper bound, and binding `[from, to]`. Use the same JOIN that `watchSetsThisWeek` uses; read it and match it exactly. Import `../util/dates.dart` for `isoDate` if the file doesn't already.

- [ ] **Step 4: Run and confirm it passes.** Run the Step 2 command, then `test/l10n/arb_parity_test.dart`, then analyze. Expected: all green.

- [ ] **Step 5: Commit.** `git add app/lib/ui/today_labels.dart app/test/ui/today_labels_test.dart app/lib/data/stats_repository.dart app/lib/l10n/ && git commit -m "feat(app): add Today header and week-over-week wording"`

---

### Task 2: A selectable week strip with a Custom chip

**Files:**
- Modify: `app/lib/widgets/week_strip.dart`
- Test: `app/test/widgets/today_widgets_test.dart`

**Interfaces produced:** `WeekStrip({super.key, required days, int? selectedIndex, ValueChanged<int>? onSelect})`. `onSelect(days.length)` means Custom.

- [ ] **Step 1: Write the failing tests.** In `app/test/widgets/today_widgets_test.dart`, inside `group('WeekStrip', …)`:
  - Replace the `'strips spaces from day names'` test with one asserting that names keep their spaces: `find.text('Upper A')` findsOneWidget.
  - Append:

```dart
    testWidgets('without onSelect it behaves as before: no Custom chip, nothing tappable',
        (tester) async {
      await pumpWithTheme(tester, const WeekStrip(days: days));
      expect(find.bySemanticsLabel('Custom'), findsNothing);
    });

    testWidgets('tapping a chip selects that day; the Custom chip selects past the end',
        (tester) async {
      final picked = <int>[];
      await pumpWithTheme(tester, WeekStrip(days: days, selectedIndex: 0, onSelect: picked.add));
      await tester.tap(find.text('Upper B'));
      await tester.tap(find.bySemanticsLabel('Custom'));
      expect(picked, [2, days.length]);
      expect(tester.getSize(find.byKey(const ValueKey('week-chip-2'))).height,
          greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('week-chip-custom'))).width,
          greaterThanOrEqualTo(48));
    });

    testWidgets('the selected chip is filled; NEXT stays on the rotation day', (tester) async {
      await pumpWithTheme(tester, WeekStrip(days: days, selectedIndex: 2, onSelect: (_) {}));
      final tokens = tester.element(find.byType(WeekStrip)).tokens;
      BoxDecoration deco(int i) => tester
          .widget<Container>(find.descendant(
              of: find.byKey(ValueKey('week-chip-$i')), matching: find.byType(Container)).first)
          .decoration! as BoxDecoration;
      expect(deco(2).color, tokens.accent);
      expect(deco(0).color, tokens.surface);
      expect(find.text('NEXT'), findsOneWidget); // on Upper A (isNext), not selected
    });

    testWidgets('six days fit a narrow phone at large text (Italian)', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const six = [
        (name: 'Upper A', weekday: 0, isNext: true, done: false),
        (name: 'Lower A', weekday: 1, isNext: false, done: true),
        (name: 'Upper B', weekday: 2, isNext: false, done: false),
        (name: 'Lower B', weekday: 3, isNext: false, done: false),
        (name: 'Arms', weekday: 4, isNext: false, done: false),
        (name: 'Conditioning', weekday: 5, isNext: false, done: false),
      ];
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
        child: wrapL10n(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WeekStrip(days: six, selectedIndex: 0, onSelect: (_) {}),
          ),
          locale: const Locale('it'),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
```

(Add `import 'package:workout_tracker/theme/app_theme.dart';` for `.tokens` if it isn't imported.)

- [ ] **Step 2: Run them and confirm they fail.** `timeout 400 make -C app test TEST=test/widgets/today_widgets_test.dart > /tmp/t2.log 2>&1; echo EXIT=$?; grep -E "All tests passed|Some tests failed|Error" /tmp/t2.log`. Expected: compile or assertion failures.

- [ ] **Step 3: Implement.** In `app/lib/widgets/week_strip.dart`:
  - Add `this.selectedIndex, this.onSelect` to the constructor, with fields `final int? selectedIndex;` and `final ValueChanged<int>? onSelect;`. Document that a null `onSelect` keeps the non-interactive strip, and that `onSelect(days.length)` selects Custom.
  - In `build`:
    - compute `final filled = selectedIndex ?? days.indexWhere((d) => d.isNext);`;
    - build each chip as `_DayChip(key: ValueKey('week-chip-$i'), day: days[i], filled: i == filled, onTap: onSelect == null ? null : () => onSelect!(i), …)`;
    - when `onSelect != null`, append after the day chips a `SizedBox(width: 7)` and a `_CustomChip(key: const ValueKey('week-chip-custom'), filled: filled == days.length, onTap: () => onSelect!(days.length), tokens: tokens, chipRadius: chipRadius)`. It is not wrapped in `Expanded`; it is fixed at 48 wide.
  - `_DayChip`:
    - Take `required this.filled` and `this.onTap`, and add `super.key`.
    - Colours follow `filled`, not `day.isNext`: `bgColor = filled ? tokens.accent : tokens.surface`, `borderColor = filled ? Colors.transparent : tokens.line`, and text and weekday colours key off `filled`.
    - Wrap the container in `GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: …))`.
    - For the name, replace `Text(day.name.replaceAll(' ', ''), … maxLines: 1, overflow: …)` with `FittedBox(fit: BoxFit.scaleDown, child: Text(day.name, maxLines: 1, softWrap: false, style: <same style, colour keyed off filled>))`.
    - Pass `filled` to `_StatusIndicator`.
  - `_StatusIndicator`: take `required this.filled`. The NEXT label renders when `isNext`, coloured `filled ? tokens.accentInk : tokens.accent`. Done and idle are unchanged.
  - Add `_CustomChip`:

```dart
class _CustomChip extends StatelessWidget {
  const _CustomChip({
    super.key,
    required this.filled,
    required this.onTap,
    required this.tokens,
    required this.chipRadius,
  });

  final bool filled;
  final VoidCallback onTap;
  final WorkoutTokens tokens;
  final double chipRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).weekStripCustom,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 48,
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: filled ? tokens.accent : tokens.surface,
            borderRadius: BorderRadius.circular(chipRadius),
            border: Border.all(color: filled ? Colors.transparent : tokens.line),
          ),
          child: Icon(WIcons.plus, size: 20, color: filled ? tokens.accentInk : tokens.dim),
        ),
      ),
    );
  }
}
```

  The outer `Row` in `build` needs `crossAxisAlignment: CrossAxisAlignment.stretch` inside an `IntrinsicHeight`, so the Custom chip matches the day chips' height. Wrap the Row in `IntrinsicHeight`.

  Update the class and field docs: `isNext` is "the next day in rotation (carries the NEXT label)", and the fill follows the selection.

- [ ] **Step 4: Run and confirm they pass.** Run the Step 2 command, then the full suite and analyze. Expected: all green. The existing NEXT, check and idle tests still pass, because without `selectedIndex` the `isNext` chip is filled as before.

- [ ] **Step 5: Commit.** `git add app/lib/widgets/week_strip.dart app/test/widgets/today_widgets_test.dart && git commit -m "feat(app): make the week strip select the hero's day"`

---

### Task 3: SplitCard follows an outside selection; dots and arrows removed

**Files:**
- Modify: `app/lib/widgets/split_card.dart`
- Test: `app/test/widgets/split_card_test.dart`

**Interfaces produced:** `SplitCard({…, int? selectedIndex, ValueChanged<int>? onSelectedChanged})`. Index `days.length` is Custom.

- [ ] **Step 1: Write the failing tests.** Append inside `group('SplitCard', …)` in `app/test/widgets/split_card_test.dart`:

```dart
    testWidgets('an outside selection moves the pager', (tester) async {
      Widget card(int? sel) => wrapL10n(SingleChildScrollView(
            child: SplitCard(days: _twodays, nextIndex: 0, selectedIndex: sel, onStart: (_) {}),
          ));
      await tester.pumpWidget(card(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(card(2)); // Custom
      await tester.pumpAndSettle();
      expect(find.text('Start empty'), findsOneWidget);
    });

    testWidgets('a swipe reports the new page', (tester) async {
      final pages = <int>[];
      await pumpWithTheme(
          tester,
          SplitCard(
              days: _twodays, nextIndex: 0, selectedIndex: 0,
              onSelectedChanged: pages.add, onStart: (_) {}));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(pages, [1]);
    });

    testWidgets('no pager dots or arrows remain', (tester) async {
      await pumpWithTheme(tester, SplitCard(days: _twodays, nextIndex: 0, onStart: (_) {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(WIcons.chevron), findsNothing);
    });
```

(Add `import 'package:workout_tracker/theme/icons.dart';`.)

- [ ] **Step 2: Run them and confirm they fail.** `timeout 400 make -C app test TEST=test/widgets/split_card_test.dart > /tmp/t3.log 2>&1; echo EXIT=$?; grep -E "All tests passed|Some tests failed|Error" /tmp/t3.log`.

- [ ] **Step 3: Implement.** In `app/lib/widgets/split_card.dart`:
  - Add `this.selectedIndex, this.onSelectedChanged` with documented fields: "the page to show, from the parent (index `days.length` is Custom); null keeps the pager self-driven from `nextIndex`" and "called when the user swipes to a page".
  - In `initState`, use `_currentPage = (widget.selectedIndex ?? widget.nextIndex).clamp(0, widget.days.length);`.
  - Add:

```dart
  @override
  void didUpdateWidget(SplitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sel = widget.selectedIndex;
    if (sel != null && sel != oldWidget.selectedIndex && sel != _currentPage) {
      _goTo(sel);
    }
  }
```

  - Make `_goTo` use `duration: Motion.of(context, Motion.slow)` and `curve: Motion.curve`, importing `../theme/motion.dart` if needed, instead of the raw 250 ms.
  - In `onPageChanged`, do `setState(() => _currentPage = page); widget.onSelectedChanged?.call(page);`.
  - Delete the whole "Dots + arrows" block: the `SizedBox(height: 13)` and the `Row` after the card. Delete the `_ArrowButton` class, and any imports that become unused.
  - Update the class doc to drop the dots/arrows sentence and mention the outside selection.
  - Remove any existing test in the file that asserts on dots or arrows.

- [ ] **Step 4: Run and confirm they pass.** Run the Step 2 command, then the full suite and analyze. Expected: all green.

- [ ] **Step 5: Commit.** `git add app/lib/widgets/split_card.dart app/test/widgets/split_card_test.dart && git commit -m "feat(app): drive the Today hero from the week strip and drop its dots"`

---

### Task 4: Wire Today (rotation header, selection sync, comparisons, Recent PRs)

**Files:**
- Modify: `app/lib/ui/today_screen.dart`, `app/lib/l10n/app_{en,it,de,es}.arb` (deletions)

**Consumes:** everything from Tasks 1–3.

- [ ] **Step 1: Implement.** In `app/lib/ui/today_screen.dart`:
  - **Imports:** add `today_labels.dart`.
  - **State:** add `int? _selectedIndex;` with a doc comment ("the day the hero shows, chosen on the strip or by swiping; null follows the rotation's next day").
  - **Streams:** add the `late final Stream<int> _setsLastWeekStream;` field, initialised in `initState` next to `_setsWeekStream` as `_stats.watchSetsLastWeek(weekStart: _weekStart)`. Remove the `_musclesWeekStream` field and its initialisation.
  - **`_recomputeRotation`:** when the new pick's id differs from the previous `_nextDay?.id`, set `_selectedIndex = null`, so that finishing a workout makes the hero follow the rotation again:

```dart
  void _recomputeRotation() {
    final previous = _nextDay?.id;
    // …existing lastId / selectNextDay code…
    if (_nextDay?.id != previous) _selectedIndex = null;
  }
```

  - **Header, in `build`:**
    - Delete the whole `trainDay` / `restOrTrain` block.
    - Compute the header line as follows, where `activeName` comes from the active controller's draft name through the same null-safe access `_ResumeHero` uses:

```dart
    final activeName = manager.hasActive ? manager.active!.draftOrNull?.name : null;
    final header = todayHeaderLine(l,
        date: fmtDate(isoDate(now), localeName, weekday: true),
        nextName: _nextDay?.name,
        activeName: activeName);
```

    - Pass `dateLabel: header` and a new `inProgress: manager.hasActive` to `_GreetingHeader`.
  - **`_GreetingHeader`:** add `required this.inProgress` (a bool). The title is `inProgress ? l.todayWorkoutInProgress : l.todayGreeting`.
  - **Selection:** add a small helper `int _nextIndex()` that returns the index of `_nextDay` in `_dayList`, or 0. Use it in `_buildSplitCard` in place of the inline computation.
    - Pass `selectedIndex: _selectedIndex ?? _nextIndex(), onSelectedChanged: (i) => setState(() => _selectedIndex = i)` to `SplitCard`.
    - In `_buildWeekStrip`, pass `selectedIndex: _selectedIndex ?? _nextIndex(), onSelect: (i) => setState(() => _selectedIndex = i)` to `WeekStrip`.
    - Keep the strip's `isNext: _nextDay?.id == day.id` and `done` exactly as they are.
  - **Stat tiles, in `_buildStatTiles`:**
    - **Sets tile:** replace the inner `_musclesWeekStream` StreamBuilder with a `StreamBuilder<int>(stream: _setsLastWeekStream, …)`. Render `StatTile(label: l.todaySetsThisWeek, value: '$v', sub: setsVsLastWeek(l, sets, lastWeek))`, with `lastWeek = snap.data ?? 0`, still inside the `CountUp`.
    - **PRs tile:** wrap it in `StreamBuilder`s over the already-cached `_recentPrsStream` and `_catalogStream` (no new streams). Compute `final lastPr = recent.isEmpty ? null : exMap[recent.first.exerciseId]?.name;` and render `StatTile(label: l.todayPrsThisWeek, value: '$v', sub: lastPr == null ? l.todayNoPrsShort : l.todayLastPr(lastPr))`.
  - **Recent PRs (`_buildRecentPrs`):** remove the `action:` count from the `SectionLabel`, and the now-unused `count` local.

**ARB deletions.** Once nothing references them, delete these keys and their `@` metadata from all four ARB files: `todayRestDay`, `todaySetsPerWeek`, `todayPrsPerWeek`, `todayMusclesCount`, `todayNewTopSets`. First confirm with `grep -rnE "todayRestDay|todaySetsPerWeek|todayPrsPerWeek|todayMusclesCount|todayNewTopSets" app/lib app/test | grep -v "lib/l10n/"`; it should print nothing. Then run `timeout 300 make -C app get > /tmp/g.log 2>&1; echo EXIT=$?`.

- [ ] **Step 2: Verify.** Run the full suite and analyze (see Global Constraints), then `timeout 900 make -C app build > /tmp/b.log 2>&1; echo EXIT=$?; tail -3 /tmp/b.log`. Expected: all green, "No issues found", and a successful build.

- [ ] **Step 3: Commit.** `git add app/lib/ui/today_screen.dart app/lib/l10n/ && git commit -m "feat(app): make Today follow the rotation and compare the week with the last"`

---

## Device checks

1. The header reads "THU 24 SEP · NEXT: LOWER B". It never shows the weekday-scheduled day when that differs from the rotation.
2. Tap Upper A on the strip: the hero slides to Upper A, the chip fills, and NEXT stays on Lower B. Swipe the hero: the chip follows. The "+" chip opens Custom.
3. With a workout active, the title reads "Workout in progress" and the header shows its name.
4. The sets tile reads "±N vs last wk", and the PRs tile reads "last: {exercise}" or "none yet".
5. The Recent PRs header has no number.
6. After finishing a workout from another selected day, the hero returns to the new next day.
