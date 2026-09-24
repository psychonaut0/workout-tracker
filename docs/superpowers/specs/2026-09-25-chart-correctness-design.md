# Chart & data correctness: design

Date: 2026-09-25
Status: approved (decisions confirmed in session)

Origin: the UI/UX critique (`.impeccable/critique/2026-09-24T16-58-17Z__app-lib.md`), priority issue P1 "Two charts show the wrong thing".

## Problem

Three charts misstate their data, and a fourth problem hides a label.

1. **The weekly-volume target tick is always drawn in the middle.**
   - Where: `app/lib/widgets/volume_bars.dart`.
   - Each bar is scaled to its muscle's own target, so the target tick belongs at the right end of the track (`tickFraction = 1.0`).
   - It is drawn at 50% instead: the `OverflowBox` sizes to its parent's full width and centres its child, so the `Align` has no room to move it.
   - Chest at 11/12 therefore looks as if it has overshot a target that sits halfway along.
2. **Bodyweight deltas assume you are always cutting.**
   - Where: `app/lib/ui/bodyweight_view.dart`.
   - In the history list a loss shows unsigned and lime ("1", "0.3"), while a gain shows signed and grey ("+0.3").
   - The 30-day tile is always lime.
   - An unsigned lime "1" reads like a count or a PR, and treating loss as the good direction is wrong for anyone bulking or maintaining.
3. **The chart x-axis is spaced by entry, not by date.**
   - Where: `app/lib/widgets/line_chart.dart`, shared by the Bodyweight and Progress screens.
   - `xAt(i) = i/(n-1)`, so three weigh-ins in August take as much width as one in June, and the trend's shape is distorted.
4. **The last-point value label collides with the line.** Its x is clamped to `W-58`, which pulls it left onto the previous segment ("66.3kg" sitting on the line in the device screenshot).

The history date column (`width: 64`) also wraps "Thu 24 Sep" onto two lines.

## Decisions

- **Volume tick:** bars stay scaled to target. The tick moves to the right end of the track, where the design always meant it to be. Reaching the target is still shown by the lime fill.
- **Bodyweight goal:** a new Profile setting, **Goal: Cut / Bulk / Maintain**. It defaults to **Maintain** for new and existing users.
  - Deltas are always signed: "−1.0" / "+0.3" / "0".
  - A delta is accent-coloured only when it moves the way the goal wants: a loss on Cut, a gain on Bulk. Every other delta is neutral.
  - On Maintain nothing is coloured, because no direction counts as progress.
  - The 30-day tile follows the same rule.
- **Date-spaced x-axis** for every `LineChart`:
  - Each point's x is proportional to its date between the first and last date.
  - Several points on the same date sit at the same x.
  - Month labels sit at the first point of each month, as today.
- **Last-point label** is drawn as a small chip (a background pill in the card surface colour) above the point.
  - It is right-aligned to the point when there is no room to its right, and placed below the point when there is no room above.
  - It never covers the line's final segment.
- **History date column** widened so a weekday + day + month fits on one line at 1.0× text scale. At larger scales it may ellipsize, but it never wraps.

## Design

### Goal setting

- `SettingsService` gains `BodyweightGoal bodyweightGoal` (`enum BodyweightGoal { cut, bulk, maintain }`).
  - It is persisted under `settings.bodyweight_goal` as the enum name. An absent or unknown value means `maintain`.
  - `setBodyweightGoal(g)` persists the value and notifies listeners.
  - The setting is client-local, like every other setting; there is no sync, schema or server change.
- Profile gets a row in a new **Bodyweight** group, placed after the Units group:
  - icon `WIcons.scale`, title "Goal", subtitle = the current goal's name;
  - tapping it opens `showWActionSheet` with the three goals, the current one marked by a check icon;
  - picking one sets the goal.
- Strings (en/it/de/es): `profileGroupBodyweight`, `profileGoal`, `goalCut`, `goalBulk`, `goalMaintain`.

### Delta tone

A pure function drives every bodyweight delta's colour:

```dart
enum DeltaTone { good, neutral }
DeltaTone bodyweightDeltaTone(double delta, BodyweightGoal goal)
```

- It returns `good` only for `delta < 0` on Cut or `delta > 0` on Bulk. Everything else, including a zero delta and any delta on Maintain, returns `neutral`.
- Display: `good` → `tokens.accent`, `neutral` → `tokens.dim`. A zero delta shows as "0", not "=".
- Signed formatting uses a shared `fmtSigned(double)`: "+0.3", "−1" or "0". The minus is U+2212, so it matches the "+" in width and is not a hyphen.

### Line chart

- The x mapping lives in a pure, testable function:

  ```dart
  List<double> dateFractions(List<String> isoDates)
  ```

  - It returns each date's position in [0, 1] between the first and last date.
  - All dates equal → evenly spaced by index (so a single day's points don't collapse onto one x).
  - An unparseable date → its index-based fraction.
- The painter's `xAt(i)` uses `_padL + fractions[i] * iw`.
- Label placement also lives in a pure function:

  ```dart
  Offset valueLabelOrigin({required Offset point, required Size label, required Size canvas, required double padT, required double padR})
  ```

  - It prefers above-right: `(point.dx + 8, point.dy − label.height − 8)`.
  - If that overflows the right edge, it flips to above-left: `(point.dx − label.width − 8, …)`.
  - If that overflows the top, it moves below the point.
  - It is clamped inside the canvas.
- The label is painted on a rounded rect in `bg` with 6px padding.

### Volume bars

- The tick is positioned explicitly: a `Positioned` inside the track's `Stack`, with `right: 0` offset by half the tick width, not an `OverflowBox`.
- It stays 1.5px wide and overhangs the track by 3px above and below.

## Out of scope

- Today's contradictions, the PR vocabulary, and 48dp targets on other screens. These are separate increments.
- A target bodyweight, or goal-based projections.
- The Progress screen's exercise-metric deltas. More weight or reps is always the good direction there, and they are unchanged.

## States

- **Bodyweight:** no entries (tiles show "—"); one entry (no deltas, "0" in the tile); several entries on one date; entries spanning years (month labels repeat per month, as today).
- **Goal** switched while the Bodyweight screen is open: the colours update live through `SettingsService` notifications.
- **Locales:** en/it/de/es; the goal names must fit in an action-sheet row.

## Acceptance

- The volume tick renders at the right end of the track, and a widget test proves its position.
- Bodyweight history and the 30-day tile show signed deltas, coloured only when on-goal. Unit tests cover the tone matrix and signed formatting, and a widget test covers the history colours for Cut vs Maintain.
- `LineChart` x positions are date-proportional, pinned by a unit test of `dateFractions` including the equal-dates and bad-date cases.
- The value label never overlaps the last segment, pinned by unit tests of `valueLabelOrigin` for the right-edge, top-edge and normal cases.
- `make -C app analyze` is clean and `make -C app test` is green.
