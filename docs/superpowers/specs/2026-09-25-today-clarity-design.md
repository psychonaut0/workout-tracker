# Today clarity: design

Date: 2026-09-25
Status: approved (decisions confirmed in session)
Origin: UI/UX critique (`.impeccable/critique/2026-09-24T16-58-17Z__app-lib.md`), priority issue P2 "Today contradicts itself, and the PR vocabulary doesn't line up".

## Problem

The Today screen tells you three different things about what to train, and its numbers are hard to read.

1. **Two scheduling models fight.**
   - The header line is "THU 24 SEP · UPPER B", the day whose `scheduledWeekday` matches today (`today_screen.dart`, `trainDay`).
   - The hero and the week strip show the next day in rotation: the day after the last one trained (`selectNextDay`).
   - The result is that the header says Upper B while the hero says Lower B.
2. **The rotation is shown twice, with two navigation systems.** The hero pager has dots and arrows, and the week strip underneath repeats the same days. The strip isn't tappable. The Custom slide is only discoverable through the dots.
3. **The greeting says "Ready to train" while a workout is in progress.**
4. **The stat tiles are cryptic.**
   - "Sets / wk 23 · 3 muscles": the sub-line refers to the muscle count, which only makes sense next to Weekly Volume.
   - "PRs / wk 0 · new top sets": the sub-line merely restates the label.
5. **The "6" beside RECENT PRS is the query limit (`watchRecentPrs(limit: 6)`), not a count.** It reads 6 for anyone with six or more PRs.
6. **Week strip names have their spaces stripped** ("UpperA"), which reads as a typo.

The PR data itself is consistent across screens: every count means "a new best top set for an exercise in a session". Only the windows differ (this week, 4 weeks, all time), and Today's labels hide which window they use.

## Decisions

- **Rotation is the only scheduling model on Today.**
  - The hero opens on the next day in rotation.
  - The header line reads "{date} · Next: {day name}".
  - Weekdays are just labels on the strip's chips; nothing on Today reads the weekday schedule to decide what comes next.
- **The week strip is the day selector.**
  - Tapping a chip shows that day in the hero. Swiping the hero moves the strip's selection too.
  - The hero's dots and arrows are removed.
  - A compact "+" chip at the end of the strip selects the Custom slide.
- **Chip states.**
  - The **selected** chip (the day shown in the hero) is accent-filled.
  - The **NEXT** label stays on the day that is next in rotation, whichever chip is selected.
  - A **done** check marks a day trained this week, as today.
- **While a workout is active,** the greeting title reads "Workout in progress", and the header line reads "{date} · {active workout name}". The hero already swaps to the resume card.
- **Stat tiles compare against last week.**
  - Sets tile: label "Sets this week", sub-line "+5 vs last wk" / "−8 vs last wk" / "same as last wk".
  - PRs tile: label "PRs this week", sub-line "last: {exercise name}" for the most recent PR, or "none yet".
- **The misleading count beside RECENT PRS is removed.**
- **Day names keep their spaces** in the strip ("Upper A"), scaling down to fit instead of being stripped.

## Design

### WeekStrip (`app/lib/widgets/week_strip.dart`)

- The `days` records are unchanged: `name`, `weekday`, `isNext`, `done`.
- New optional `int? selectedIndex` and `ValueChanged<int>? onSelect`.
  - When `onSelect` is null, the strip behaves as today: the `isNext` chip is filled, nothing is tappable, and there is no Custom chip. This keeps any other caller unaffected.
  - When `onSelect` is set:
    - each day chip is a tap target (the whole chip, at least 48dp tall) that calls `onSelect(i)`;
    - a trailing Custom chip, 48dp wide with the `WIcons.plus` icon and the Semantics label "Custom", calls `onSelect(days.length)`;
    - the filled chip is `selectedIndex`, falling back to the `isNext` chip when it is null.
- The NEXT label renders on the `isNext` chip. It uses `accentInk` when that chip is filled and `accent` otherwise.
- Day names are no longer space-stripped. They are single-line, wrapped in a `FittedBox(fit: BoxFit.scaleDown)`.

### SplitCard (`app/lib/widgets/split_card.dart`)

- New optional `int? selectedIndex` (0…days.length, where `days.length` is Custom) and `ValueChanged<int>? onSelectedChanged`.
  - When `selectedIndex` changes from the parent (via `didUpdateWidget`), the pager animates to that page. Every duration goes through `Motion.of`.
  - A user swipe calls `onSelectedChanged(page)`.
- The dots and arrows row and `_ArrowButton` are deleted. The pager and the Start button are unchanged.

### Today (`app/lib/ui/today_screen.dart`)

- State: `int? _selectedIndex`. Null means the hero follows the rotation's next day. It is reset to null whenever the rotation pick changes, for example after a workout is finished.
- The strip gets `selectedIndex: _selectedIndex ?? nextIndex` and `onSelect: (i) => setState(() => _selectedIndex = i)`. The SplitCard gets the same value, plus `onSelectedChanged` doing the same update.
- The header line comes from a pure function:

  ```dart
  String todayHeaderLine(AppLocalizations l, {required String date, String? nextName, String? activeName})
  ```

  - An active workout gives "{date} · {activeName}".
  - Otherwise, a next day gives "{date} · Next: {nextName}".
  - Otherwise, the result is just "{date}".
- The greeting title is `todayWorkoutInProgress` when a session is active, and `todayGreeting` otherwise.
- The weekday-schedule `trainDay` / `todayRestDay` logic is removed.
- Stat tiles:
  - `StatsRepository.watchSetsLastWeek({required DateTime weekStart})` counts working sets with `date >= weekStart − 7d AND date < weekStart`.
  - A pure function `setsVsLastWeek(AppLocalizations l, int thisWeek, int lastWeek)` returns `todayVsLastWeek(+N / −N)` with a U+2212 minus, or `todaySameAsLastWeek`.
  - The PRs sub-line uses the first row of the recent-PRs stream mapped through the catalog: `todayLastPr(name)`, or `todayNoPrsShort`.
  - The now-unused `watchDistinctMusclesThisWeek` stream is removed from Today. The repository method stays in case anything else uses it.
- Recent PRs: the `action:` count beside the section label is dropped.

### Strings (en/it/de/es)

- **Add:** `todayNext(name)`, `todayWorkoutInProgress`, `todaySetsThisWeek`, `todayPrsThisWeek`, `todayVsLastWeek(delta)`, `todaySameAsLastWeek`, `todayLastPr(name)`, `todayNoPrsShort`, `weekStripCustom`.
- **Delete, once unused:** `todayRestDay`, `todaySetsPerWeek`, `todayPrsPerWeek`, `todayMusclesCount`, `todayNewTopSets`.

## Out of scope

- The Plan tab's weekday scheduling. It still exists as data and still labels the chips.
- History and Profile PR tiles. They already name their windows ("PRs · 4wk"; Profile's stats are all-time).
- 48dp targets elsewhere, which is the next increment.

## States

- **No training days:** no strip; the hero shows only the Custom slide, as today; the header shows the date only.
- **One day:** a single chip plus the Custom chip.
- **Many days (6+):** the chips shrink and their names scale down; the strip never overflows at 320dp and 1.3× text scale.
- **No sets last week:** "+23 vs last wk". **No PRs ever:** "none yet".
- **Finishing a workout** moves the rotation on; the selection resets to follow it.

## Acceptance

- Widget tests cover:
  - WeekStrip: selection fill, NEXT label on a non-selected chip, `onSelect` for a day and for Custom, names keeping their spaces, and legacy behaviour without `onSelect`.
  - SplitCard: animates to an externally set `selectedIndex`, reports swipes through `onSelectedChanged`, and has no dots or arrows.
- Unit tests cover `todayHeaderLine` and `setsVsLastWeek`, including zero, negative and positive deltas.
- The strip does not overflow at 320dp and 1.3× text scale in Italian.
- `make -C app analyze` is clean and `make -C app test` is green.
