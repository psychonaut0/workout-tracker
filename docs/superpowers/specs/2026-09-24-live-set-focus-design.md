# Live set focus — design

Date: 2026-09-24
Status: approved (brief confirmed in session)
Origin: UI/UX critique of the shipped app (`.impeccable/critique/2026-09-24T16-58-17Z__app-lib.md`), priority issues P0 (set-row tap targets), P1 (every row control has equal weight), P1 (rest timer floats over content).

## Problem

The live workout screen is where the app is used most, and it is the weakest screen.

- **Tap targets are too small.** Every pending set row carries nine targets: −/+ weight, −/+ reps, four RIR chips and a check. Their sizes:
  - Stepper buttons: 25×34dp (`widgets/stepper.dart`).
  - RIR chips: about 17×30dp (`widgets/rir_picker.dart`).
  - Check: 32×34dp (`session/set_row.dart`).

  The handoff's own rule is at least 44dp (`docs/design_handoff_workout_tracker/README.md`), and Material asks for 48dp. The app is used sweaty and one-handed, and weight/reps −/+ sit 8dp apart.
- **"Done" is the weakest control.** The prefilled values are right most of the time, so the usual decision is just "done?". Yet the check is a faint outline, outweighed by four grey stepper buttons on the same row. With five pending rows visible, the screen shows about 45 targets.
- **The rest timer covers content.** `RestTimerCard` is `Positioned(bottom: 44)` and ignores the safe area. It sits over the last exercise card and clips the in-list "Finish workout" button, and it says nothing about what comes next.
- **Destructive actions sit next to navigation.** A discard trash sits between the title and the timer, at the same weight as minimise. Every block also carries "Remove exercise" and reorder arrows in its footer.

## Goal

Logging a set that went to plan takes **one tap on a large target in the thumb zone**, with no aiming and no reading. Editing stays available but becomes secondary.

## Visual authority

This is a refinement inside the existing world. Tokens, fonts, radius and the lime accent stay (`app/lib/theme/`).

It deliberately departs from the handoff prototype's `SetRow`/`ExerciseBlock`/`RestTimer` layout (`docs/design_handoff_workout_tracker/design/app/screen-log.jsx`). That layout was followed pixel for pixel, and so was the gap to the handoff's own 44dp tap-target rule. This spec supersedes the prototype for the live workout screen.

## Design

### One live set

Exactly one set is **live** at a time.

- By default it is the first not-done set in on-screen order: blocks top to bottom, warm-ups before working sets inside a block.
- Tapping any set row makes that set live. This includes a logged set (to correct it) and a later set (to do sets out of order).
- A set chosen by tap stays live until it is logged, updated or removed. Focus then falls back to the first not-done set.
- When every set is done there is no live set.

The live set renders as a **live card** inside its block, in the position of its row:
- A label: `SET 2`, `WARM-UP`, or `SET 1 · LOGGED` for a logged set being corrected.
- Two large steppers, weight and reps. Buttons are 56×56dp, and the value is 30pt Space Grotesk tabular.
- A visible edit cue (an underline) under each value, because tapping the value opens the keypad. Typing uses the existing `WStepper` commit rules unchanged.
- A reference line: `last 140kg × 9 · 1w ago` from `BlockState.lastTop`, or `No previous data`. It replaces the per-block `LAST` row, which is removed.
- For a logged set being corrected, a secondary `Mark as not done` text action, at least 48dp tall.

Every other set is a **compact line**, at least 48dp tall and tappable as a whole:
- Logged: `1  140kg × 6  RIR 1   [TOP|PR]  ✓`
- Pending: `3  140kg × 6   ○`
- Warm-ups show a `W` index. Pending warm-ups are no longer dimmed to 0.7 opacity; the `W` label is enough.

The block's column header row (`SET WEIGHT REPS RIR`) is removed; the compact lines don't need a grid.

### The log bar

A lime bar pinned to the bottom of the screen replaces the in-list Finish button and the floating rest card. It is 56dp tall, reserves layout space above the system inset (`MediaQuery.padding.bottom`), and never overlaps the list. Its label names exactly what it will do:

| Live set | Label | Action |
|---|---|---|
| pending working set | `Log set 2 · 140kg × 6` | mark done, start rest, show RIR strip, advance |
| pending warm-up | `Log warm-up · 70kg × 8` | mark done, advance (no rest, no RIR) |
| logged set (correcting) | `Update set 1` | keep logged, clear focus, advance |
| none, `canFinish` | `Finish workout` | finish (existing path) |
| none, nothing done | hidden | — |

The bar has no set number for warm-ups. Its weight uses the current unit (`UnitService.fmtWt` plus `uLabel`).

**Act-while-editing:** before doing anything, the bar's tap must commit a value still being typed in a live-card stepper. It calls `FocusManager.instance.primaryFocus?.unfocus()` followed by `FocusManager.instance.applyFocusChangesIfNeeded()` (see `app/CLAUDE.md` and the numeric-input notes). Today's set row avoids this problem because a stepper never renders for a done set. Letting a logged set become live removes that protection, so this commit step is load-bearing.

**Advancing:**
- After a log or update, focus returns to the first not-done set.
- If that set is in a different block, the finished block collapses (only when all its sets are done), the next block expands, and the list scrolls the live card into view.
- Haptics are unchanged: heavy impact for a live PR, medium for a normal set, selection click for an update.

### RIR after logging

Logging a working set stores its current RIR (prefilled from the plan, as today).

- The logged row then shows a 0–3 strip under its compact line for 4 seconds, with 48dp chips and the stored value selected.
- Tapping a chip sets RIR and restarts the 4 seconds.
- When the time runs out, or the next set is logged, the strip collapses.
- Warm-ups have no strip. There is no RIR control anywhere else on the live screen.

### Rest in the header

The floating `RestTimerCard` is deleted.

While resting, the header's 3px progress bar becomes a 6px rest countdown bar in the accent colour, and a rest row appears under the title row containing:
- `REST 1:25`, which turns accent in the final 5 seconds.
- `Next · Lying leg curl · set 1 · 40kg × 8`, from the live set, ellipsised. It reads `Next · Finish workout` when no live set remains.
- `+30s` and `Skip` chips, each at least 48dp tall.

When not resting, the header is the one shipped today.

The rest haptics, the auto-stop at 0 and the notification path are unchanged; they live in the screen and the controller, not the card.

### Menus instead of footers

- **Header:** the trash button becomes a `⋯` button (48dp), which opens an action sheet:
  - `Finish workout`, enabled when `canFinish`, so you can finish early.
  - `Discard workout`, destructive, going through the existing `_handleClose` confirm logic.
- **Block header:** gains a `⋯` button (48dp), which opens an action sheet:
  - `Add set`
  - `Add warm-up`
  - `Move up`, disabled on the first block
  - `Move down`, disabled on the last block
  - `Remove exercise`, destructive, with the existing confirm when sets are logged

  The block footer (buttons, arrows, remove) is deleted.
- The action sheet is a new shared widget: a bottom sheet of rows at least 56dp tall.

### Removing a set

- Swipe-left removal stays. Logged sets still confirm first, as today.
- Every removal now shows a snackbar with **Undo**, which restores the set at its original index in its original list.
- Removing the live set moves focus to the first not-done set.

### Block expansion

- A fresh workout expands only its first block.
- The block holding the live set always renders expanded, whatever its stored flag. The header's expand/collapse tap works as today for other blocks.
- Resumed drafts keep their persisted flags.

## Out of scope

- Today, History, the summary screen, charts and PR wording. Those are separate increments from the same critique.
- Stepper and target sizes outside the live workout, such as the editors, Profile and the History sheet. `WStepper` gains a large variant, and its default stays as it is.
- Per-weight deltas against last time.
- Changing the draft schema. The live set and the RIR strip are in-memory UI state; after a resume, focus is recomputed.

## States and ranges

- **Size:** 1–12 blocks, 0–3 warm-ups and 1–8 working sets each.
- **Values:** weights 0–500 kg or lb with a step of 1.25–5; reps 0–50.
- **Empty workout:** the bar is hidden, and the list shows the placeholder and "Add exercise".
- **All done:** the bar reads "Finish workout".
- **Resting with no sets left:** "Next · Finish workout".
- **Reduced motion:** strip and expand transitions are instant, and nothing pulses.
- **Locales:** en/it/de/es. German is the longest; the bar label ellipsises and never wraps.
- **Width:** 320–430dp, including text scale 1.3 at 320dp without overflow.

## Acceptance

- One tap on the bar logs a prefilled set at the values shown.
- Every tappable on the live screen is at least 48dp on both axes, and every icon-only control has a Semantics label.
- Nothing overlaps the exercise list at any time.
- Typing a weight and then tapping the bar logs the typed value.
- Tests cover live-set resolution, log/update/advance, the RIR strip timer, undo restore, the bar label matrix, the typed-then-log case, and no overflow at 320dp/1.3× in Italian.
