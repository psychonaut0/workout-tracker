# Live loop stability: design

Date: 2026-09-29
Status: approved (decisions confirmed in session)
Origin: the post-0.16.0 critique (`.impeccable/critique/2026-09-29T11-38-39Z__app-lib.md`), issues #1 and #7. On the phone, the end of a rest moved the exercise list about 60dp. A tap aimed at set 2 landed on set 4, which became the live set. The RIR strip under a logged set closed on its own after 4 seconds, which moved the list again. The weight and reps rulers drew ticks and labels past their card into the screen gutter.

## Goal and success

Nothing in the live workout moves or disappears unless the user's own tap caused it.

The work is done when all of these hold on the phone:
- rest ends without the list moving;
- the RIR strip is still open after a 10-second wait;
- the rulers stop at their own edges in both themes.

Tests must pin the header height in both rest states at 412dp and 320dp, 1.0× and 2.0× text, in English and Italian, with no overflow.

Nothing here changes the draft schema, storage, sync or the ruler's zoom behaviour.

## Causes

- `SessionHeader` sits above the `ListView`, outside it (`active_session_screen.dart`). Its rest row is built only while resting, and its progress bar is 6dp while resting and 3dp otherwise. When the countdown reaches 0, the whole list moves up.
- The controller closes the RIR strip when `rirPromptWindow` (4 s) runs out; the screen's one-second ticker calls `expireRirPrompt`.
- The tape painter draws one step past each side (`halfSpan = width / 2 / pxPerValue + step`) so edge values can slide in, but nothing clips the `CustomPaint`. The edge-fade `ShaderMask` only affects pixels inside its own bounds, so marks painted outside them show at full strength.

## Decisions

- **The rest row appears on the first logged set and stays for the rest of the workout.** Before the first log there is no row, as today. That first appearance is the only height change, and the user's tap causes it.
- **After rest, the row counts up how long you have rested.**
- **The RIR strip has no timer.** It stays open after a value is picked, so fixing a wrong pick takes one more tap. It closes only on an action on another set, or on a change to the set list.
- **The ruler is clipped to its own box.** Painting and zoom are unchanged.

## Design

### Rest row (`session/session_header.dart`, `session/active_session_controller.dart`)

**When it shows.** The row is shown when any set in the draft is done, warm-ups included, or while resting. Because this is derived from the draft, it comes back correctly after a resume or process death.

**Two states, same height:**
- **Resting** (unchanged):
  - line 1: `REST 1:12` with the `+30s` and `Skip` chips;
  - line 2: `Next · …`;
  - the bar is a 6dp draining countdown.
- **After rest:**
  - Line 1 reads `RESTED 1:24` (new string `restRestedLabel`). The time counts up from `restEndedAt`, with tabular figures, in the dim colour and without the final-seconds accent.
  - The chip area keeps its space but is empty. It is a placeholder with the same height as the chips, so line 1 stays the same height at any text scale.
  - Line 2: `Next · …`.
  - The bar stays 6dp and shows workout progress (done / total working sets).

**The rested timer:**
- **`restEndedAt`:** a new in-memory `DateTime?` on the controller.
  - `stopRest()` sets it to now. That covers the countdown reaching 0 (the screen ticker and `SessionManager`'s resume check) and a Skip.
  - `startRest()` clears it.
  - Discard and finish reset it along with the other rest fields.
  - It is not persisted, like the live set.
  - It is not changed by `setRestRaw()`, the notification's +30s sync. When `setRestRaw` receives a null start (rest already over), `restEndedAt` is left alone.
- **When `restEndedAt` is null** (after a resume, or when only warm-ups have been logged), line 1 shows the `RESTED` label with no time.
- **Display:** `m:ss`, capped at `99:59`.

**The Next line names the next pending set.**
- New controller getter `nextPendingSet`: the live set if it is not done, otherwise the first not-done set in on-screen order.
- `restNextLabel` takes that instead of `liveSet`. So while a logged set is open for correction, the line names the real next set, not the one being edited.
- With nothing pending it reads `Next · Finish workout`, as today.

**Layout.** Both states build the same two-line structure, with the same text styles and the same reserved chip height. Only the contents change, so the header height is the same in both states at any width and text scale.

### RIR strip (`session/active_session_controller.dart`, `session/active_session_screen.dart`)

Remove `rirPromptWindow`, `_rirPromptUntil` and `expireRirPrompt`, and the ticker's call to `expireRirPrompt`.

**Opens:**
- Logging a working set opens the strip on that set, as today.
- Picking a value (`setRirFromPrompt`) stores it and leaves the strip open.

**Closes:**
- **`logLiveSet`:** logging any other set moves the strip to it if it is a newly logged working set, and closes it otherwise. That is the current rule minus the timer.
- **`focusSet`:** tapping any set closes it. Tapping the prompted set itself turns it into the live card, which has no strip.
- **`markNotDone`:** un-logging the prompted set closes it (already done today).
- **Set-list changes:** adding a set or warm-up, removing a set (swipe, or restore on Undo), adding or removing an exercise, moving an exercise up or down, reordering.
- **Discard / finish:** the controller is reset.

**Doesn't close:** scrolling, rest starting or ending, the ticker, minimizing and reopening the screen while the controller lives.

### Ruler (`widgets/ruler_picker.dart`)

- Wrap the tape `CustomPaint` in a `ClipRect`, inside the `ShaderMask`. Nothing then paints outside the ruler's box, and the existing 6% edge fade softens the ends.
- The centre marker and the centre tap target are unaffected.
- History's set editor uses the same widget and gets the same fix.

### Strings (en/it/de/es)

`restRestedLabel`: "RESTED" / "RIPOSATO" / "PAUSIERT" / "DESCANSADO". Short, mono uppercase, like `restLabel`. Each one reads as a past tense next to its `restLabel` ("REST" / "RECUPERO" / "PAUSE" / "DESCANSO").

## Out of scope

Other live-workout items from the critique, left for later:
- the next set not following a heavier logged set;
- rulers opening in 0.25 kg mode on fractional weights;
- two warm-up rows both labelled "W";
- the typed-entry sheet having no Cancel.

## Acceptance

**Tests (TDD):**
- **Controller:**
  - the RIR strip is still open well past 4 s;
  - it closes on each close trigger above and on nothing else in the "Doesn't close" list;
  - `restEndedAt` is set by the natural end and by Skip, cleared by `startRest`, and reset by discard and finish;
  - `nextPendingSet` covers three cases: focus on a pending set, focus on a logged set, and nothing pending.
- **Header widget:**
  - no rest row before the first log;
  - the same height resting and after rest, at 412 and 320dp, 1.0× and 2.0× text, in English and Italian, with no overflow;
  - `RESTED` with a count-up when `restEndedAt` is set, and without a time when it is null;
  - the Next line after correcting a logged set.
- **Ruler:** nothing is painted outside the widget's bounds, in kg and lb, at rest and zoomed.

**Device checks:**
1. Log a working set, let rest run out: the list doesn't move and `RESTED` counts up.
2. Skip a rest: same.
3. Log a set, wait 10 s: the RIR strip is still open. Pick a value: still open. Log the next set: the strip moves to it.
4. Open a logged set during rest: the Next line names the real next set.
5. Rulers show clean edges in dark and light, kg and lb, at 1.0× and 2.0× text.
6. Minimize and resume during rest and after rest: the row stays, and after a process restart the `RESTED` label shows without a time.
