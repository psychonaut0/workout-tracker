# Weight ruler: coarse steps with a slow-drag zoom: design

Date: 2026-09-25
Status: approved (decisions confirmed in session)
Origin: phone feedback on the ruler picker. The fixed 0.5 kg step is too fine for normal changes and too coarse for micro-loading.

## Problem

The weight ruler moves in fixed 0.5 kg (1 lb) steps. A normal change of a few kilograms takes a long swipe past half-kilo values nobody picks. Fractional plates (1.25 kg change plates, 0.25 kg micro-plates) can't be reached at all.

## Decisions

- **Two step sizes on the weight ruler.**
  - Coarse is the default: **1 kg** / **5 lb**.
  - A slow drag, or holding the finger still, **zooms in** to the fine step: **0.25 kg** / **1 lb**.
- **The zoom is a real zoom.** The tape widens around the centre and the fine values and ticks fade in (about 150 ms, `Motion.of`). It zooms back out when the drag speeds up again. The in and out thresholds differ (hysteresis) so the mode doesn't flicker at the boundary. A light haptic marks each mode change.
- **Release snaps to the current mode's grid.**
  - A fast swipe lands on whole kg.
  - A zoomed drag lands on quarters.
- **A fractional value rests zoomed in.**
  - If the value is off the coarse grid (e.g. 60.25 kg), the tape stays in fine mode at rest, so the centre always sits on a labelled value.
  - The next fast drag zooms out and lands on the coarse grid again.
  - A value that is back on the coarse grid after a fine release zooms back out once it settles.
- **Scope.**
  - The weight ruler, in both the live workout and History (both use `SetValuesEditor`).
  - The reps ruler keeps a single step of 1 and never zooms.
  - Typed entry is unchanged.

## Design

### Formatting (`units/unit_service.dart`)

`fmtWt` in kg shows up to **two** decimals, with trailing zeros trimmed:
- `60` → "60", `60.5` → "60.5", `60.25` → "60.25", `60.3` → "60.3".

Today it rounds to one decimal, which would show 60.25 as "60.3". Storage already keeps two decimals. lb display is unchanged (whole pounds).

### RulerPicker (`widgets/ruler_picker.dart`), rewritten on its own gesture handling

`ListWheelScrollView` can't change item spacing while a drag is in progress: `jumpTo` ends the drag, and changing `itemExtent` shifts the selected index. So the tape gets its own model:

- **State.** The tape position is a continuous `double` in value space (the value under the centre). The zoom is a continuous `t ∈ [0, 1]`, with 0 = coarse and 1 = fine.
  - Pixels per value = `lerp(extent / coarseStep, fineExtent / fineStep, t)`.
  - `fineExtent` is at least `itemExtent` and wide enough that a centred fine label like "60.25" doesn't overlap its neighbours (≈ 88).
- **Drag.** A horizontal drag moves the position by `-dx / pxPerValue`, so a leftward swipe moves up the tape, as today. The tape clamps at `min` and at `max`, and `max` still grows to include a larger handed-in value.
- **Fling and snap.**
  - On release, project the end position from the release velocity with a friction simulation, round it to the current mode's grid, and animate there (`Motion.curve`; a spring or ease-out, with no overshoot past the tape ends).
  - Under reduced motion, snap immediately.
- **Reporting.** `onChanged` fires once per grid value of the current mode that crosses the centre, during the drag and the glide. It never fires for a value handed in by the parent, and never twice in a row for the same value. It is followed by `HapticFeedback.selectionClick()`, as today.
- **Zoom triggers** (only when `fineStep` is set):
  - **In:** while dragging, the smoothed drag speed stays below **~120 dp/s** for **~200 ms**, or the pointer is held down with less than 4 dp of movement for **~300 ms**.
  - **Out:** the smoothed speed exceeds **~450 dp/s**.
  - Put these as named constants at the top of the file for tuning after device testing.
  - The zoom animates `t` around the current centre value. The centre stays put while the neighbours spread or close.
- **At rest.** After a snap, `t` settles to 1 if the value is off the coarse grid, else to 0. Grid membership uses a tolerance of 5% of the step, so a converted value like 134.99 lb counts as 135.
- **Grids.** Coarse and fine grids are absolute multiples of their step in the ruler's value space. A value off the fine grid too (60.3 from history or typing) keeps today's anchor behaviour for the fine grid: the grid shifts so the value sits exactly on it. The next coarse move lands on the absolute coarse grid.
- **Rendering.** Paint the tape with a single `CustomPainter` over the visible range:
  - ticks along the bottom ruled edge (coarse: a major tick per coarse value plus minor subdivisions; fine: a major tick per coarse value, a medium tick per fine value);
  - labels via cached `TextPainter`s.
  - Coarse labels are always drawn. Fine-only labels fade in with `t`.
  - Keep today's look: labels scale and fade with distance from the centre, the accent colour and bold weight at the centre, the fixed accent centre marker rising from the ruled edge, and the edge fade `ShaderMask`.
- **Unchanged API.**
  - `value`, `step` (now the coarse step), `format`, `onChanged`, `min`, `max`, `itemExtent`, `onTapValue`, `semanticLabel`, and the new optional `fineStep`.
  - `RulerPicker.settleAll()` and `settle()`: stop any glide and zoom animation and rest on the last reported value, reporting nothing new.
  - The `Key('ruler-centre')` tap target for typed entry, which must still let drags that start on it reach the tape.
  - Slider semantics: increase and decrease move by the coarse step at `t = 0`, and by the fine step when resting zoomed.
- **External changes.** A new `value` from the parent (typed entry, undo) re-centres without reporting. It stops any glide, and sets the rest zoom by the same on-grid rule.
- `RulerScale` may be kept, or replaced by grid helpers. Its unit tests go or move with it; keep tests for the anchor and no-drift behaviour.

### SetValuesEditor (`session/set_values_editor.dart`)

- The weight ruler works in **display units**:
  - `value: unit.fromKg(weightKg)`;
  - `step: unit == lb ? 5 : 1`, `fineStep: unit == lb ? 1 : 0.25`;
  - the format shows the display value (lb whole pounds; kg via the same up-to-two-decimals rule);
  - `onChanged: (v) => onWeight(clampRound2(UnitService.toKg(v, unit.unit)))`;
  - `max` 500 kg, or its lb equivalent.
- The typed-entry guard still compares in kg against `weightKg`.
- Reps are unchanged.

## Out of scope

- Plate-aware steps (per-exercise `plate_step_kg`). Only the weight ruler's fixed steps change.
- A zoom on the reps ruler.
- Any other stepper.

## Acceptance

- **`fmtWt` unit tests:** 60 / 60.5 / 60.25 / 60.3 kg; lb unchanged.
- **RulerPicker widget tests:**
  - A fast swipe moves in coarse steps and snaps onto the coarse grid.
  - A slow timed drag, or a hold followed by a slow move, zooms in and lands on a fine value (e.g. 100.25).
  - Speeding up mid-drag zooms back out.
  - A fractional rest value stays zoomed; an on-grid one rests coarse.
  - External changes re-centre without echo.
  - `settleAll` stops a glide on the last reported value.
  - The centre tap opens typed entry.
  - Slider semantics.
  - No zoom without `fineStep`.
  - The existing ruler behaviours stay covered.
- **SetValuesEditor tests:** kg 1 / 0.25 steps; lb 5 / 1, reporting kg; the untouched-lb no-op still holds.
- The existing `LiveSetCard`, `SetEditorSheet` and session tests stay green, with only the drag distances or speeds adjusted where the step changed.
- `make -C app analyze` is clean and `make -C app test` is green.
- **Device check:** the feel of the thresholds (tuned after the phone test).
