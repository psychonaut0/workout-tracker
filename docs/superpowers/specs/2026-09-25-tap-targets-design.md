# 48dp tap targets across the app: design

Date: 2026-09-25
Status: approved (decisions confirmed in session)
Origin: UI/UX critique (`.impeccable/critique/2026-09-24T16-58-17Z__app-lib.md`), P0 "tap targets far too small". The live workout was fixed in the live-set-focus increment; this covers every other screen.

## Problem

Outside the live workout, many controls sit below the 48dp Material minimum and the handoff's own 44px rule. Several icon-only controls have no screen-reader label. A survey found:

- **Steppers:** the `WStepper` buttons are 25×34 and unlabelled. They are used 16 times, in the day editor, exercise editor, Profile rest settings, muscle targets and History.
- **RIR chips:** the History set editor uses 30dp-tall chips about 15dp wide, with a 32×34 delete button, all in one row.
- **Day editor rows:** each exercise row packs ↑ ↓ (28×30), 🗑 (30×30) and a 16dp chevron into a single row.
- **Profile:**
  - 26dp accent swatches;
  - a 36dp back button;
  - a text-only "Save name" link;
  - a name row about 46dp tall.
- **Plan:** a 36dp back button and segment buttons under 48dp.
- **Shared widgets:**
  - `ChipSelect` chips about 32dp;
  - `Toggle` 50×30;
  - `MetricTabs` 34dp;
  - `WDeleteButton` 46dp;
  - the day editor's "Add exercise" button 44dp.
- **Unlabelled icon-only controls:**
  - the tab bar's centre ⚡ FAB;
  - the bodyweight sheet's ± buttons;
  - the back buttons;
  - the day-editor trash;
  - the Profile edit pencil;
  - the History set delete;
  - the accent swatches.

## Decisions

- **Every tappable is at least 48×48dp.** Where the visual element is smaller, it stays the same size and sits centred in a 48×48 hit area, unless the layout has room to enlarge it.
- **Every icon-only control has a Semantics label.**
- **History set editing uses the live workout's pattern:**
  - each logged set is a read-only line (`1 · 140kg × 6 · RIR 1`);
  - tapping a line opens it inline as an editing card, with the same weight and reps rulers (tap the value for typed entry), 48dp RIR chips for working sets, and a 48dp "Delete set" action;
  - one card is open at a time, and "Add set" appends a set and opens it.
- **The day editor reorders by drag handle.**
  - Each exercise row has a 48dp ≡ drag handle and a 48dp trash button.
  - Tapping the row header expands or collapses its prescription panel; the chevron becomes a non-interactive indicator.
  - The ↑/↓ buttons are removed.
  - Rows are uniform height while collapsed. The expanded row hides its handle, and dragging collapses the open row first (see Design).

## Design

### WStepper (`widgets/stepper.dart`)

- Each −/+ button keeps its 25×34 visual, centred in a 48×48 hit box.
- The value label is wrapped in `FittedBox(fit: BoxFit.scaleDown)`, so a value that doesn't fit shrinks instead of being cut off with "…".
- New optional `semanticLabel` (e.g. "Rest"). The buttons announce `a11yDecrease(label)` / `a11yIncrease(label)` ("Decrease Rest"), or `a11yDecreaseGeneric` / `a11yIncreaseGeneric` when no label is given.
- Nothing else changes: the commit, clamp, `formatForEdit` and `parseDisplay` rules in `app/AGENTS.md` stay exactly as they are.
- The fixed-width wrappers at `profile_screen.dart` (the two rest steppers) and `targets_tab.dart` grow from 120 to 168dp.

### Shared small controls

- `ChipSelect` chips: at least 48dp tall.
- `Toggle`: a 48×48 hit area around the 50×30 pill, plus `Semantics(toggled:, label:)`.
- `MetricTabs` segments: 48dp tall.
- `WDeleteButton`: 48dp tall.
- Day editor "Add exercise": 48dp tall.
- Plan segment buttons: 48dp tall.
- Profile and Plan back buttons: 48×48 hit areas with the `commonBack` label.
- Profile:
  - The name row and "Save name" are at least 48dp tall, and the pencil gets the `profileEditName` label.
  - The accent swatches move to their own full-width row under the Accent title. Each is a 48×48 target around a 28dp dot, labelled `profileAccentOption(n)`.
- Tab-bar FAB labelled `splitStartWorkout`.
- Bodyweight sheet ± buttons labelled `a11yDecrease` / `a11yIncrease` of the weight label.

### Day editor (`ui/day_editor.dart`)

- The slot rows move into a `ReorderableListView` (`shrinkWrap`, `NeverScrollableScrollPhysics`, `buildDefaultDragHandles: false`) inside the existing page `ListView`.
- A slot row is: `[index] [name + summary, tappable → toggle] [≡ handle 48×48: ReorderableDragStartListener] [trash 48×48]`.
- The handle is hidden while that row is expanded. `onReorderStart` collapses any expanded row.
- `onReorderItem(from, to)` moves the slot in `_slots`. Positions are saved as today, by the Save button.
- Labels: the handle gets `a11yReorderExercise(name)`, the trash `dayEditorRemoveExercise(name)`.

### History set editor

- `_SetEditorSheet` moves to `ui/set_editor_sheet.dart` as a public `SetEditorSheet`, so it can be widget-tested with a fake `SessionRepository` (the pattern in `test/ui/history_session_card_test.dart`).
- The rulers and typed entry are extracted from `LiveSetCard` into a shared `SetValuesEditor` (`session/set_values_editor.dart`), which both screens use:
  - inputs: weight (kg) and reps, the unit, and change callbacks;
  - behaviour: the 0.5 kg / 1 lb weight step, the modal typed-entry sheet, and the lb unchanged-seed guard.
  - `LiveSetCard` keeps its label, last-session line, RIR row and "Mark as not done" around it, and its tests stay green.
- **Editing card:** `SetValuesEditor`, then for working sets a 48dp RIR row, then a 48dp "Delete set" action (icon + text, danger colour) that keeps the existing confirm dialog.
- **Persistence:** edits are no longer written on every change.
  - Each edited set is saved 400 ms after its last change (debounced per set).
  - A pending save is written immediately when the card closes (another line is tapped, the card is collapsed, or the sheet closes).
  - This keeps one `updateSet` per settled edit instead of one per ruler tick. Each write also recomputes the top set and queues a sync upload.
- **Act-while-editing:** before deleting, switching cards, adding a set, or closing, the sheet calls `commitPendingInput()`, which stops a gliding ruler, and then flushes the pending save.

### Strings (en/it/de/es)

- **Add:**
  - `a11yDecrease(label)`, `a11yIncrease(label)`, `a11yDecreaseGeneric`, `a11yIncreaseGeneric`;
  - `commonBack`, `profileEditName`, `profileAccentOption(n)`;
  - `a11yReorderExercise(name)`, `dayEditorRemoveExercise(name)`;
  - `historyDeleteSet`.
- **Reuse:** `splitStartWorkout`, `historyDeleteSetTitle` / `historyDeleteSetMessage`, `sessionColRir`.

## Out of scope

- The live workout (already done).
- Visual restyling beyond what a larger hit area needs.
- Drag-to-reorder anywhere else.

## Acceptance

- **Widget tests assert at least 48dp** for:
  - the WStepper buttons (including a 1.3× scale no-overflow check at the 168dp width);
  - `ChipSelect`, `Toggle`, `MetricTabs` and `WDeleteButton`;
  - the day editor's handle and trash, if the editor can be mounted; otherwise a row-widget test;
  - `SetEditorSheet`'s lines, RIR chips and delete action.
- **Semantics tests** cover the stepper and toggle labels.
- **`SetEditorSheet` tests:**
  - a ruler swipe produces exactly one `updateSet` after the debounce, carrying the final value;
  - collapsing flushes a pending save immediately;
  - delete confirms and deletes;
  - "Add set" opens the new set.
- `make -C app analyze` is clean and `make -C app test` is green.
