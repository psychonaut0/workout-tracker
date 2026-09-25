# 48dp Tap Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every tappable outside the live workout becomes at least 48×48dp, and every icon-only control gets a Semantics label. The day editor reorders with a drag handle, and History edits sets with the live workout's rulers inside a card that opens when you tap a set.

**Architecture:** Small, contained edits to shared widgets and screens, plus two structural changes:
- a `ReorderableListView` of uniform slot rows in the day editor;
- the History set sheet moved to its own testable file, built on a `SetValuesEditor` extracted from `LiveSetCard`, with debounced per-set persistence.

**Tech Stack:** Flutter via fvm (`make -C app …`), provider, flutter_test, gen-l10n ARB (en/it/de/es).

**Spec:** `docs/superpowers/specs/2026-09-25-tap-targets-design.md`

## Global Constraints

- **Commands:**
  - Run everything from the repo root as `make -C app …`. Never `cd` and never call `flutter` directly.
  - Run `make -C app get` first, and again after editing ARB files. The generated l10n files are gitignored; never commit them.
  - A bare `make -C app test` gets auto-backgrounded by the harness. Always run `timeout 400 make -C app test [TEST=…] > /tmp/x.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/x.log`.
  - `make -C app analyze` must report "No issues found".
- **Tap targets:** every tappable is at least 48×48dp. A smaller visual stays as it is, centred in a 48×48 hit box. Every icon-only tappable gets a Semantics label.
- **WStepper:** the rules in `app/AGENTS.md` are unchanged (the commit paths, clamp, `formatForEdit`, `emptyValue`, per-site `parseDisplay`, and the `didUpdateWidget` guard). Only the button hit boxes, the label's `FittedBox` and the optional `semanticLabel` change.
- **Strings:** every new string goes into all four ARB files. Edit ARB files as text, and validate JSON with `python3 -m json.tool`.
- **Project rules:**
  - Confirm dialogs use `showWConfirm` only.
  - Every duration goes through `Motion.of`.
  - `Expanded`/`Flexible` are direct children of their Row/Column.
  - No `db.watch` in `build`.
  - Anything that acts on values being edited (deleting, switching cards, adding a set, closing) calls `commitPendingInput()` first (`widgets/pending_input.dart`).
- **Commits:** Conventional Commits, subject line only, no body, no trailer lines. No plan or task numbers in code.

## Review Focus

1. **A ruler fling in History:** the rulers must not write to the database on every tick. There must be exactly one `updateSet` after the fling settles, carrying the final value. Task 5 tests the debounce with a fake repository.
2. **Closing the History sheet mid-debounce:** the pending edit must still be saved. Task 5 tests the flush on collapse, and dispose fires the flush.
3. **The profile rest steppers at 168dp and 1.3× text in German:** no overflow. Task 1 has a stepper test at 168dp and 1.3×.
4. **Dragging a slot while another slot is expanded:** the open row collapses at drag start, and the order is saved only through Save. This is a device check; Task 3 tests the row widget's handle and trash.
5. **The Profile accent row on a 320dp phone:** the swatches wrap onto their own row with no overflow. Device check.

---

### Task 1: WStepper 48dp hit boxes, labels, a label that never truncates, and wider fixed sites

**Files:** `app/lib/widgets/stepper.dart`, `app/lib/ui/profile_screen.dart` (the two rest steppers' `SizedBox(width: 120)` → 168), `app/lib/ui/targets_tab.dart` (`SizedBox(width: 120)` → 168), `app/lib/l10n/app_{en,it,de,es}.arb`. Test: `app/test/widgets/stepper_targets_test.dart` (new).

**Strings** (add after `"commonUndo"`):
- en: `"a11yDecrease": "Decrease {label}"`, `"a11yIncrease": "Increase {label}"` (placeholder `label`, type String), `"a11yDecreaseGeneric": "Decrease"`, `"a11yIncreaseGeneric": "Increase"`
- it: `"Diminuisci {label}"`, `"Aumenta {label}"`, `"Diminuisci"`, `"Aumenta"`
- de: `"{label} verringern"`, `"{label} erhöhen"`, `"Verringern"`, `"Erhöhen"`
- es: `"Reducir {label}"`, `"Aumentar {label}"`, `"Reducir"`, `"Aumentar"`

**Implementation:**
- Add an optional `final String? semanticLabel;` to `WStepper`.
- In `build`, each `btn(...)` becomes:

```dart
Semantics(
  button: true,
  label: dir < 0
      ? (widget.semanticLabel == null ? l.a11yDecreaseGeneric : l.a11yDecrease(widget.semanticLabel!))
      : (widget.semanticLabel == null ? l.a11yIncreaseGeneric : l.a11yIncrease(widget.semanticLabel!)),
  excludeSemantics: true,
  child: GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onTap: () => _step(dir),
    child: SizedBox(
      width: 48,
      height: 48,
      child: Center(child: /* the existing 25×34 decorated Container */),
    ),
  ),
)
```

- The keys `stepper-dec` / `stepper-inc` move to the `GestureDetector`, which is now 48×48.
- Remove the `SizedBox(width: 4)` gaps between the buttons and the label; the hit boxes already provide the spacing.
- Wrap the non-editing label `Text` in `FittedBox(fit: BoxFit.scaleDown, child: …)`, with `overflow: TextOverflow.visible`.
- Pass a `semanticLabel` at the call sites that have an obvious field name. Use strings that already exist:
  - Profile rest steppers: `l.profileCompoundRest` / `l.profileIsolationRest`.
  - `targets_tab`: the localized muscle name.
  - Day and exercise editor steppers: their field labels.
  - History: see Task 5, which replaces those steppers.

**Tests** (`stepper_targets_test.dart`), all using `wrapL10n`:
- `tester.getSize(find.byKey(Key('stepper-inc')))` is `Size(48, 48)`.
- `find.bySemanticsLabel('Increase Rest')` finds one widget when `semanticLabel: 'Rest'`, and `find.bySemanticsLabel('Increase')` finds one when it is null.
- In a `SizedBox(width: 168)` at `TextScaler.linear(1.3)` with `format: (v) => '${v.round()}s'` and value 180, there is no exception, and the label's `FittedBox` is present.
- The existing `test/widgets/stepper_test.dart` and `stepper_input_test.dart` still pass.

**Commit:** `feat(app): give steppers 48dp buttons and screen-reader labels`

---

### Task 2: Shared small controls, back buttons, the FAB, the bodyweight ± buttons and Profile

**Files:**
- `app/lib/widgets/plan_form.dart` (`ChipSelect`, `Toggle`)
- `app/lib/widgets/progress_widgets.dart` (`_MetricSegment` height 34 → 48)
- `app/lib/widgets/delete_button.dart` (height 46 → 48)
- `app/lib/ui/day_editor.dart` (`_AddExerciseButton` height 44 → 48)
- `app/lib/ui/plan_screen.dart` (`_BackButton` 48×48 hit with the `commonBack` label; `_SegBtn` min height 48)
- `app/lib/ui/profile_screen.dart`:
  - back button: 48×48 hit, `commonBack` label;
  - name row: min height 48, pencil labelled `profileEditName`;
  - "Save name": min height 48;
  - accent swatches: their own full-width `Wrap` row under the Accent title, each a 48×48 target around a 28dp dot, labelled `profileAccentOption(n)` with n 1-based, and the selected one flagged `Semantics(selected: true)`.
- `app/lib/shell/w_tab_bar.dart` (FAB `Semantics(button: true, label: l.splitStartWorkout)`)
- `app/lib/ui/add_weight_sheet.dart` (± `Semantics` labels via `a11yDecrease` / `a11yIncrease` of the sheet's weight label string)
- the ARB files

**Strings:**
- en: `"commonBack": "Back"`, `"profileEditName": "Edit name"`, `"profileAccentOption": "Accent colour {n}"` (placeholder `n`, type int)
- it: `"Indietro"`, `"Modifica nome"`, `"Colore di accento {n}"`
- de: `"Zurück"`, `"Namen bearbeiten"`, `"Akzentfarbe {n}"`
- es: `"Atrás"`, `"Editar nombre"`, `"Color de acento {n}"`

**Implementation notes:**
- `ChipSelect`: wrap each chip in `ConstrainedBox(constraints: BoxConstraints(minHeight: 48))` and centre its content. Keep the pill look by keeping the decoration on an inner `Container`; the extra height is transparent hit area.
- `Toggle`: wrap it in `Semantics(toggled: value, label: <the label its caller passes, if the API has one; otherwise add an optional String? semanticLabel>)` and a 48×48 hit `SizedBox` centring the 50×30 pill.
- The Profile accent row is a layout change:
  - The `_Row` for Accent keeps its icon, title and subtitle, with `right: null`.
  - Directly below it, inside the same group, add a `Padding(fromLTRB(14, 0, 14, 12))` containing a `Wrap(spacing: 4, runSpacing: 4)` of swatch targets.

**Tests** (`app/test/widgets/tap_targets_test.dart`, new):
- a `ChipSelect` chip is at least 48 tall;
- a `Toggle`'s hit area is at least 48×48, and its semantics report toggled;
- `MetricTabs` segments are at least 48 tall;
- `WDeleteButton` is at least 48 tall;
- the tab bar FAB has the semantics label "Start workout", if `WTabBar` can be pumped standalone. If it can't, skip this one and note it in the report.

Profile, Plan and the bodyweight sheet are verified by analyze and a device check. Profile and Plan own streams or DB reads, so they can't be mounted in tests.

**Commit:** `feat(app): lift shared controls and settings to 48dp targets with labels`

---

### Task 3: Day editor, drag-handle reordering

**Files:** `app/lib/ui/day_editor.dart`, ARB files. Test: `app/test/ui/day_editor_slot_row_test.dart` (new).

**Strings:**
- en: `"a11yReorderExercise": "Reorder {name}"`, `"dayEditorRemoveExercise": "Remove {name}"` (placeholder `name`, String)
- it: `"Riordina {name}"`, `"Rimuovi {name}"`
- de: `"{name} verschieben"`, `"{name} entfernen"`
- es: `"Reordenar {name}"`, `"Quitar {name}"`

**Implementation:**
- Make `_SlotRow` public as `DaySlotRow` so it can be tested. The day editor itself does an unawaited DB read in `initState` and deadlocks `pumpWidget`, per `app/AGENTS.md`. Give `DaySlotRow` a new `int reorderIndex` parameter.
- Header row: `[index] [Expanded name + summary]` becomes a single `GestureDetector(onTap: onToggle)` region. Then add the handle and the trash:
  - **Handle**, shown only when `!expanded`: `Semantics(label: l.a11yReorderExercise(name), child: ReorderableDragStartListener(index: reorderIndex, child: SizedBox(48, 48, child: Icon(Icons.drag_handle, size: 20, color: tokens.dim))))`.
  - **Trash:** `Semantics(button: true, label: l.dayEditorRemoveExercise(name), excludeSemantics: true, child: GestureDetector(onTap: onRemove, child: SizedBox(48, 48, child: Center(<the existing 30×30 container>))))`.
  - **Chevron:** stays as a non-interactive `ExcludeSemantics` indicator, next to the name.
- Delete `_ReorderBtn` and the `onMove` parameter.
- In the editor build, replace the slot `for` loop with:

```dart
ReorderableListView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  buildDefaultDragHandles: false,
  itemCount: _slots.length,
  onReorderStart: (_) {
    HapticFeedback.mediumImpact();
    setState(() => _expandedExId = null);
  },
  onReorderItem: (from, to) => setState(() => _slots.insert(to, _slots.removeAt(from))),
  itemBuilder: (context, i) => DaySlotRow(
    key: ValueKey(_slots[i].exerciseId),
    reorderIndex: i,
    // … the existing arguments, minus onMove
  ),
)
```

  Slots are deduplicated by `exerciseId`, so the key is unique. Keep whatever wrapper and padding the old loop used.
- Replace `_moveSlot` with the inline `onReorderItem` update.

**Tests** (`day_editor_slot_row_test.dart`): pump a `DaySlotRow` inside a `ReorderableListView` of two rows.
- The handle `SizedBox` is 48×48 and has semantics label "Reorder Incline bench press".
- The trash is 48×48, labelled "Remove …", and fires `onRemove`.
- Tapping the name fires `onToggle`.
- When `expanded: true`, the handle is absent.
- Dragging row 2's handle up by one row reorders the list (use the pattern from `test/session/reorder_exercises_sheet_test.dart`).

**Commit:** `feat(app): reorder a training day's exercises by drag handle`

---

### Task 4: Extract `SetValuesEditor` from LiveSetCard

**Files:** create `app/lib/session/set_values_editor.dart`; modify `app/lib/session/live_set_card.dart`. Tests: `app/test/session/set_values_editor_test.dart` (new). `app/test/session/live_set_card_test.dart` must stay green unchanged.

**Interface produced:**

```dart
class SetValuesEditor extends StatelessWidget {
  const SetValuesEditor({super.key, required this.weightKg, required this.reps,
      required this.unit, required this.onWeight, required this.onReps});
  final double weightKg;
  final int reps;
  final UnitService unit;
  final ValueChanged<double> onWeight;
  final ValueChanged<int> onReps;
}
```

It renders, exactly as `LiveSetCard` does now:
- the "WEIGHT · KG" caption and the weight `RulerPicker` (`Key('live-weight')`, 0.5 kg or 1 lb step, max 500, `format: unit.fmtWt`, semantic label `"${l.sessionWeight}, ${unit.uLabel}"`, tap → `showNumberEntrySheet` with the unchanged-text guard and lb `parseDisplay`);
- the "REPS" caption and the reps `RulerPicker` (`Key('live-reps')`, step 1, max 50, `itemExtent: 56`, tap → typed entry).

It keeps `LiveSetCard`'s full-width layout: the rulers are full-bleed and the captions are inset 14.

**Move, don't rewrite:** cut the ruler and typed-entry code, including `_typeWeight` / `_typeReps`, out of `LiveSetCard` into `SetValuesEditor`, calling `onWeight` / `onReps` where the card used to mutate the set.

`LiveSetCard` then builds `SetValuesEditor(weightKg: set.weightKg, reps: set.reps, unit: unit, onWeight: (v) { set.weightKg = v; onChanged(); }, onReps: (v) { set.reps = v; onChanged(); })` between its label and its RIR row. Its visual output is unchanged.

**Tests** (`set_values_editor_test.dart`):
- a weight swipe calls `onWeight` with the stepped value;
- typed entry calls `onWeight` with the typed value;
- an untouched lb entry calls nothing.

These may reuse patterns from `live_set_card_test.dart`. All existing `live_set_card_test.dart`, `log_set_bar_test.dart` and `active_session_screen_test.dart` tests must still pass.

**Commit:** `refactor(app): share the live card's weight and reps editor`

---

### Task 5: History set editor, tap a set to edit it with the rulers

**Files:** create `app/lib/ui/set_editor_sheet.dart` (the moved and rewritten `_SetEditorSheet`, public as `SetEditorSheet`, plus `_EditableSet`); modify `app/lib/ui/history_screen.dart` (remove the old sheet, `_SetEditRow` and `_EditableSet`, and open the new sheet from the same place with the same arguments); ARB files. Test: `app/test/ui/set_editor_sheet_test.dart` (new, using a fake `SessionRepository` as in `test/ui/history_session_card_test.dart`, implementing `updateSet`, `deleteSet` and `addSet` and recording calls).

**Strings:**
- en: `"historyDeleteSet": "Delete set"`
- it: `"Elimina serie"`
- de: `"Satz löschen"`
- es: `"Eliminar serie"`

**Behaviour:**
- **The list.** Each set is a read-only line:
  - index, or `W` for warm-ups;
  - `{weight}{unit} × {reps}`;
  - `RIR n` for working sets;
  - a trailing chevron.
  - The whole line is a 48dp-tall tap target that opens that set's editing card in place. `SetLine` in `session/set_line.dart` is the reference look: reuse its visual style, not the widget itself, since its API is session-specific.
- **One card at a time,** held in a `String? _openId`. Tapping the open set's line (the card's header) collapses it.
- **The editing card** (a bordered container like `LiveSetCard`, without its label or last-session line):
  - `SetValuesEditor(weightKg:, reps:, unit:, onWeight: (v) => _edit(s, weight: v), onReps: (v) => _edit(s, reps: v))`;
  - for working sets, a row with the `sessionColRir` caption and `RirPicker(height: 48)`;
  - a full-width 48dp "Delete set" action (icon `WIcons.trash` plus `historyDeleteSet`, danger colour), which calls the existing confirm-then-delete logic.
- **Persistence:**
  - `_edit` mutates the local copy, calls `setState`, and (re)starts a 400 ms `Timer` stored per set id in `Map<String, Timer>`. When it fires, it calls the existing `_persist(s)`.
  - `_flush(id)` cancels that set's timer and persists immediately if a timer was pending.
  - `_flush` runs:
    - when a card closes (switching `_openId` or collapsing);
    - before `_deleteSet`;
    - before `_addSet`;
    - in `dispose`, for every pending set, fire-and-forget.
  - Before any of those, call `commitPendingInput()` to stop a gliding ruler.
- **Add set:** keep the existing seeding logic, then set `_openId` to the new id. Keep the existing unfocus/apply lines, or replace them with `commitPendingInput()`, which includes them.

**Tests** (`set_editor_sheet_test.dart`):
1. It lists the sets as lines, each at least 48dp tall, and tapping one shows `find.byKey(Key('live-weight'))`.
2. A timed drag on the weight ruler, followed by `pump(300 ms)`, shows `updateSet` not yet called. After another `pump(200 ms)`, `updateSet` has been called exactly once, with the final weight string.
3. An edit followed by an immediate tap on the open line to collapse it calls `updateSet` once right away, without waiting for the debounce.
4. "Delete set" → confirm → `deleteSet(id)` is called and the line disappears.
5. "Add set" → `addSet` is called and the new set's card is open.
6. The RIR chips in the card are at least 48 tall.

**Commit:** `feat(app): edit logged sets with the live workout's rulers`

---

## Device checks

1. Every stepper in Plan › Edit exercise / Edit day and Profile › Rest is easy to hit, and no label is cut off.
2. Plan › Edit training day: drag a ≡ handle to reorder, open a row by tapping it, and remove an exercise with the 48dp trash. Save keeps the new order.
3. Profile: the accent swatches sit on their own row and are easy to hit. The name row, "Save name" and the back button are easy to hit.
4. History › a session › Edit sets:
   - tap a set to open its rulers;
   - fling the weight and close the sheet: the value sticks after reopening;
   - delete a set;
   - add a set.
5. With TalkBack on, the stepper buttons, back buttons, FAB, trash and swatches are announced by name.
