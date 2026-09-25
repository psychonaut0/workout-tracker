# Weight ruler zoom: implementation plan

Spec: `docs/superpowers/specs/2026-09-25-ruler-zoom-design.md`
Branch: `feat/ruler-zoom` from main. Implementers run serially. Every commit is a Conventional Commit with a subject line only.

Commands, always run from the repo root:
- `timeout 400 make -C app test TEST=<file> > /tmp/x.log 2>&1; echo EXIT=$?` for a single file;
- the full suite the same way, without `TEST`;
- `make -C app analyze`.

A bare `make -C app test` gets auto-backgrounded and hangs, so always use `timeout` and redirect.

## Task 1: `fmtWt` shows up to two decimals in kg

- **Files:** `app/lib/units/unit_service.dart`, plus tests (the existing unit_service test file, or a new `test/units/unit_service_test.dart`).
- **TDD:** 60 → "60", 60.5 → "60.5", 60.25 → "60.25", 60.3 → "60.3", 60.10 → "60.1"; lb unchanged (whole pounds).
- **Implementation:** `toStringAsFixed(2)`, then trim trailing zeros and a trailing dot.
- **Check for fallout:** run the full suite. A test that asserted one-decimal rounding of a two-decimal value must be updated only if the new output is the correct one. Grep `fmtWt(` call sites for fixed-width layouts where "100.25" could overflow (History lines, set lines, PR rows) and report anything suspicious; don't restyle.
- **Commit:** `feat(app): show weights to two decimals when they have them`

## Task 2: RulerPicker on its own gesture handling (parity, no zoom yet)

- **Files:** `app/lib/widgets/ruler_picker.dart` and `app/test/widgets/ruler_picker_test.dart`.
- **Replace `ListWheelScrollView`**, per the spec's RulerPicker section:
  - a continuous value-space position;
  - a horizontal drag (a `GestureDetector` with the `onHorizontalDrag*` callbacks, or a `HorizontalDragGestureRecognizer`);
  - a fling projection with a `FrictionSimulation`, rounded to the grid, then an `AnimationController` animating to the snapped value (a spring or ease-out, clamped to the ends; instant under `Motion.of` reduced motion);
  - a single `CustomPainter` for the ticks and labels (cached `TextPainter`s; the same distance-based scale, fade and accent centre as today's `_RulerMark`/`_TicksPainter`);
  - the fixed centre marker, the edge `ShaderMask`, and the `ruler-centre` translucent tap target;
  - slider semantics with increase and decrease;
  - `settleAll`/`settle`;
  - external value re-centring without echo;
  - `onChanged` once per grid crossing, with a selection haptic;
  - the grid anchor behaviour for off-grid values (keep `RulerScale` or equivalent helpers plus their unit tests);
  - a non-positive step falls back to 1.
- **Keep the constructor API, and add `fineStep` as an optional, unused parameter** (Task 3 wires it up), so later tasks don't change signatures.
- **The existing ruler tests must pass unchanged in intent.** Adjust mechanics only (e.g. a drag distance per step equals `itemExtent` at coarse zoom). Add tests:
  - a fling (`tester.fling`) moves several values and ends exactly on the grid;
  - `settleAll` mid-glide stops on the last reported value and reports nothing afterwards;
  - no `onChanged` for a handed-in value.
- The LiveSetCard, SetEditorSheet, set_values_editor, log_set_bar and active_session_screen tests must stay green. They drag `live-weight`/`live-reps` by multiples of `RulerPicker.defaultItemExtent`, so keep a coarse step = `itemExtent` px.
- **Commit:** `refactor(app): drive the ruler picker with its own drag and snap`

## Task 3: The slow-drag zoom

- **Files:** `app/lib/widgets/ruler_picker.dart` and its test.
- **Implement the spec's zoom** when `fineStep != null`:
  - `t ∈ [0, 1]` animated over `Motion.of(context, Motion.fast..base)`;
  - pixels per value interpolate between `itemExtent/step` and `fineExtent/fineStep`, with `fineExtent ≈ max(itemExtent, 88)`;
  - the centre value stays fixed during the zoom;
  - fine labels and ticks fade in with `t`;
  - zoom in: smoothed speed < `kZoomInSpeed` (120 dp/s) for `kZoomInDwell` (200 ms), or held still (< 4 dp) for `kHoldDwell` (300 ms), using a timer started on pointer down/last move;
  - zoom out: speed > `kZoomOutSpeed` (450 dp/s);
  - `HapticFeedback.lightImpact()` on each mode change;
  - release snaps to the current mode's grid;
  - at rest `t` goes to 1 if the value is off the coarse grid (5% tolerance), else to 0;
  - external values follow the same rest rule;
  - semantics increase and decrease use the fine step while resting zoomed.
  - Named constants at the top for tuning.
- **Tests** (bounded pumps on the fake clock; `tester.timedDrag` gives controlled speeds; use `startGesture` + `pump(Duration)` + `moveBy` for holds):
  - a fast swipe gives coarse values only;
  - a slow drag lands on a fine value;
  - a hold then a small move gives a fine step;
  - speeding up mid-drag zooms out;
  - a fractional value rests zoomed, and a fast drag from it lands on the coarse grid;
  - an on-grid value rests coarse;
  - no zoom when `fineStep` is null;
  - reduced motion: no animation asserts.
  Expose the zoom state for tests via `@visibleForTesting` on the state (e.g. `double get zoom`).
- **Commit:** `feat(app): zoom the ruler into fine steps on a slow drag`

## Task 4: Wire the weight ruler

- **Files:** `app/lib/session/set_values_editor.dart` and its test, plus any session/History tests whose weight-drag expectations change.
- **Per the spec:**
  - the ruler value is in display units: `UnitService.fromKg(weightKg, unit.unit)`;
  - `step` is 5 lb / 1 kg, and `fineStep` is 1 lb / 0.25 kg;
  - `max` is 500 kg converted to display units;
  - the format shows the display value (kg using the Task 1 rule, lb as whole pounds; it can reuse `fmtWt(toKg(v))`, but beware double conversion; formatting the display value directly is cleaner);
  - `onChanged` converts back via `clampRound2(UnitService.toKg(v, unit.unit))`;
  - typed entry is unchanged;
  - update the comment about the fixed 0.5 step.
- **Tests:**
  - in kg, a coarse swipe of 2 steps from 60 reports 62;
  - in lb, a coarse swipe from 135 lb reports the kg of 140 lb;
  - a slow drag in kg reports 60.25;
  - the untouched-lb no-op still holds.
  Fix the expectations in live_set_card / set_editor_sheet / active_session_screen tests that assumed 0.5 kg steps (the new values must follow from 1 kg steps).
- Full suite, analyze, and `timeout 900 make -C app build`.
- **Commit:** `feat(app): step weights by the kilo with a quarter-kilo zoom`

## Device checks (phone)

1. A normal swipe moves in whole kg, and a fling travels far and lands exactly on a value.
2. A slow drag zooms in within about ⅕ s, and holding still zooms in. The zoom is smooth, with the centre value fixed.
3. Speeding up zooms back out without flicker at the threshold speed.
4. Releasing while zoomed lands on a quarter, and the tape stays zoomed showing e.g. "60.25". A fast swipe from there lands on whole kg and zooms out.
5. lb mode: 5 lb steps, with a 1 lb zoom.
6. Logging mid-glide still logs the shown value.
7. History set editor: same behaviour, and saves happen after settling.
8. Tune `kZoomInSpeed`/`kZoomOutSpeed`/dwell times to taste.
