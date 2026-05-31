# Plan Editors (Split + Exercise Library) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the Plan placeholder tab with the real Plan editors: a **Split** sub-tab (training-day list → DayEditor with name/focus/weekday + an ordered, reorderable slot list with inline prescription) and an **Exercises** sub-tab (library grouped by muscle → ExerciseEditor: identity/compound/equipment, read-only PR, start-weight, default prescription).

**Architecture:** **Pure client increment — NO migration/handler change** (verified: `sync_upload.go` `applyExercise`/`applyDayTemplate`/`applyDayTemplateItem` already accept every column, force `is_template=false`, stamp `created_by`, gate writes by ownership). New repository write methods (`DayTemplateRepository.saveDay`/`deleteDay`, `ExerciseRepository.createExercise`/`updateExercise`/`uniqueSlug`/`prTopSets`) write via `db.writeTransaction` → the CRUD queue → `/sync/upload`, mirroring `session_writer`/`bodyweightUpsertOp` (TEXT weights, `0/1` bools, OMIT `user_id`/`created_at`). **Clone-on-edit:** seeded rows (`is_template=true`/`created_by` NULL) are server-read-only, so opening one creates a NEW owned copy (`id=null`) with a banner; owned rows edit in place.

**Tech Stack:** Flutter 3.44 (`make -C app`), PowerSync. Reuse `context.tokens`/`WorkoutType`/`WIcons`/`AppRadius`, `UnitService` (`fromKg`/`toKg`/`fmtWt`/`uLabel`, `fmtPlain`), `WCard`/`SectionLabel`/`WStepper`, `app/lib/data/muscles.dart` (`kMuscleLabels`/`muscleLabel`/`orderedMuscles`), `app/lib/ui/exercise_sheet.dart` (`showExerciseSheet`), `resolveSlot`/`rirParse`/`rirToString` (in `models.dart`/`day_template_repository.dart`), `uuid` (from `package:powersync/powersync.dart`). Design: `docs/design_handoff_workout_tracker/design/app/screen-plan.jsx`.

**Settled decisions (adopted from the understanding synthesis):**
- **Clone-on-edit** for seeded days/exercises (`id=null` new owned copy + "Editing creates your own copy" banner); owned rows edit in place; "New" always creates a custom row.
- **1-based contiguous** `day_template_items.position` (matches seed `00014`); re-stamp `index+1` on save.
- **No delete-exercise** button (FK RESTRICT → ghost delete); **confirm dialog on delete-day** (cascades to slots).
- **RIR** = free-text field parsed via `rirParse`/displayed via `rirToString` (stored as `*_rir_low/high` ints).
- **No `plate_step_kg` UI** (keep on edit, default `2.5` new); the start-weight stepper increments by `plateStepKg`.
- **Clear-to-NULL is a no-op on ALL PATCH fields** (day name/focus, slot targets, exercise defaults/equip — Go uses `COALESCE(NULLIF($,''), col)`): an existing value can be overwritten with a new non-empty value but not blanked back to NULL. Accepted limitation. The int steppers (min values) already prevent it; ensure the editors expose no "clear to empty then Save" affordance the user would perceive as saved (RIR/equipment text: a left-empty field just preserves the prior value — fine).
- **Android hardware back** won't collapse an open in-tab editor (it pops the root route). Optional: wrap `PlanScreen` in a `PopScope` that collapses an open editor to the list first. Deferrable.
- Muscle grouping = the 8 DB groups via `muscles.dart` (+ an `other` bucket), NOT the JSX MUSCLES map.

---

## File Structure
- `app/lib/data/models.dart` (MOD) — `Slot.id`; `DayTemplate.isTemplate`; `ExerciseDraft`
- `app/lib/data/day_template_repository.dart` (MOD) — expose `is_template`/slot `id` in reads; `saveDay`, `deleteDay`, pure `dayTemplateUpsertOp`/`slotUpsertOp`
- `app/lib/data/exercise_repository.dart` (MOD) — `createExercise`, `updateExercise`, `uniqueSlug`, `prTopSets`, pure `exerciseUpsertOp`
- `app/lib/widgets/plan_form.dart` (NEW) — `Field`, `TextInput`, `ChipSelect`, `Toggle`, `PrimaryBtn`, `PlanSection`
- `app/lib/ui/plan_screen.dart` (NEW) — shell: header + back-nav + Split|Exercises toggle + editor routing
- `app/lib/ui/split_tab.dart`, `app/lib/ui/day_editor.dart`, `app/lib/ui/exercise_library_tab.dart`, `app/lib/ui/exercise_editor.dart` (NEW)
- `app/lib/shell/app_shell.dart` (MOD) — mount `PlanScreen` at IndexedStack index 3

---

### Task 1: Read-model gaps (Slot.id, DayTemplate.isTemplate, prTopSets)

**Files:** Modify `app/lib/data/models.dart`, `app/lib/data/day_template_repository.dart`, `app/lib/data/exercise_repository.dart`

- [ ] **Step 1: `Slot` carries its row id (NULLABLE).** In `models.dart`, add `final String? id;` to `Slot` with `this.id` **NOT `required`** in the constructor, and read it in `Slot.fromRow` (`id: r['id'] as String?`). It MUST be optional — non-DB `Slot`s are constructed elsewhere with named args and no id (`active_session_controller.dart` `Slot(exerciseId:…, position:…)`, `resolve_slot_test.dart`, and DayEditor's own seed slots); a required `id` breaks them. `day_template_items` reads include `id` (their query is `SELECT *`), so DB-loaded slots get a non-null id; DayEditor reads `slot.id` only for those.
- [ ] **Step 2: `DayTemplate.isTemplate`.** `watchDays`/`byId` use **explicit column lists that OMIT `is_template`** (NOT `SELECT *`) and build `DayTemplate` **inline** (no `fromRow`). So: (a) add `dt.is_template` to the `watchDays` SELECT and `is_template` to the `byId` SELECT; (b) add `final bool isTemplate;` to `DayTemplate` with a **`this.isTemplate = false` default** (so the 3 other inline build sites — `today_screen.dart`, `rotation_test.dart`, `split_card_test.dart` — still compile unchanged); (c) pass `isTemplate: ((row['is_template'] as num?) ?? 0) != 0` in **both** repo inline constructors. Without the SELECT additions, every day reads `isTemplate=false` → editing a seeded day would PATCH a server-read-only row (ghost write silently dropped). (SplitTab/DayEditor use this for clone-on-edit.)
- [ ] **Step 3: `ExerciseRepository.prTopSets()`** → `Future<Map<String, double>>`:
```dart
Future<Map<String, double>> prTopSets() async {
  final rows = await db.getAll(
    'SELECT exercise_id, MAX(CAST(weight_kg AS REAL)) AS pr '
    'FROM sets WHERE is_top_set = 1 AND is_warmup = 0 GROUP BY exercise_id'); // is_top_set=1 for parity with bestTopSet
  return { for (final r in rows) r['exercise_id'] as String: (r['pr'] as num?)?.toDouble() ?? 0 };
}
```
- [ ] **Step 4: Safe RIR parse.** In `models.dart` add `({int low, int high})? rirTryParse(String s)` — a non-throwing wrapper (return `null` on empty/partial/non-numeric; otherwise the parsed pair). The editors' RIR text fields call this on commit; never call the throwing `rirParse` from `onChanged`. (Leave the existing `rirParse`/`rirToString` as-is.)
- [ ] **Step 5:** `make -C app analyze` clean; `make -C app test` green (existing 69 still pass — the nullable `Slot.id` + defaulted `DayTemplate.isTemplate` must not break `resolveSlot`/`today_screen`/`history_screen`/`active_session_controller`/`rotation_test`/`split_card_test`; verify they compile). **Commit** — "feat(app): expose slot id + day is_template; prTopSets + safe RIR parse"

### Task 2: Repository write methods + pure builders (TDD)

**Files:** Modify `app/lib/data/day_template_repository.dart`, `app/lib/data/exercise_repository.dart`, `app/lib/data/models.dart`; Test `app/test/data/plan_write_test.dart`

Mirror the `session_writer`/`bodyweightUpsertOp` pattern: **pure** `({String sql, List<Object?> args})` builders (testable with a FakeExec) + thin `db.writeTransaction` wrappers. **TEXT** for `base_weight_kg`/`plate_step_kg` (`toStringAsFixed(2)`); `compound` `0/1`; OMIT `user_id`/`created_at`/`is_template` (server stamps/forces). Day-item targets are plain ints.

- [ ] **Step 1: `ExerciseDraft`** in `models.dart`: `{String? id; String name; String muscleGroup; String? equip; bool compound; double? baseWeightKg; double plateStepKg; int? defaultRepLow/High; int? defaultWarmupSets/WorkingSets; int? defaultRirLow/High;}` (mutable draft; `id==null`/`isTemplate` source ⇒ create).

- [ ] **Step 2: Pure builders** — write tests FIRST in `plan_write_test.dart`:
  - `exerciseUpsertOp(String? existingId, String newId, ExerciseDraft d, String slug)` → INSERT (existingId==null: columns id,slug,name,muscle_group,equip,compound,base_weight_kg,plate_step_kg,default_*; NO is_template/created_by) vs UPDATE-by-id (name,muscle_group,equip,compound,base_weight_kg,plate_step_kg,default_* — NOT slug/id). Value rules: `base_weight_kg` = `d.baseWeightKg == null ? '' : d.baseWeightKg!.toStringAsFixed(2)` (empty → server `NULLIF` keeps NULL — do NOT write `'0.00'`); `plate_step_kg` always `d.plateStepKg.toStringAsFixed(2)` (non-null, default 2.5); `compound` = `0`/`1`; `equip` empty→`''`; defaults are ints. OMIT user_id/created_at (server stamps; do NOT copy `muscle_target_repository.seedDefaultsIfEmpty` which writes created_at). Test both branches: new uses `newId`+`slug`; update targets `existingId`, no slug; weights are Strings (null base → `''`); compound is `0`/`1`.
  - `dayTemplateUpsertOp(String? existingId, String newId, name, focus, weekday, int position)` → INSERT (id,name,focus,scheduled_weekday,position; OMIT slug/notes/is_template/created_by) vs UPDATE-by-id (name,focus,scheduled_weekday — NOT position on a plain edit). Test both.
  - `slotUpsertOp(String? itemId, String newId, dayId, exerciseId, int position, targets...)` → INSERT (id,day_template_id,exercise_id,position,target_*) vs UPDATE-by-id (position,target_* — NOT exercise_id/day_template_id). Test both.

- [ ] **Step 3: `DayTemplateRepository.saveDay({String? id, required DayDraft draft})`** (define `DayDraft{name, focus, weekday, List<SlotDraft> slots}` + `SlotDraft{String? itemId, exerciseId, workSets, warmupSets, repLow, repHigh, rirLow, rirHigh}` in models.dart). Inside ONE `db.writeTransaction`:
  - `id==null` (new/cloned): `position = (SELECT COALESCE(MAX(position),0)+1 FROM day_templates)`; emit `dayTemplateUpsertOp(null, newDayId, ...)`; then for each slot `slotUpsertOp(null, uuid, newDayId, ex, index+1, targets)`.
  - `id!=null` (owned): `dayTemplateUpsertOp(id, id, name, focus, weekday, 0)` UPDATE (name/focus/weekday only). Reconcile slots against the loaded set: slot `itemId==null` → INSERT (`position=index+1`); existing `itemId` → UPDATE (`position=index+1` + targets); a loaded `itemId` absent from the draft → `DELETE FROM day_template_items WHERE id=?`. Positions re-stamped `index+1` (1-based, contiguous).
  - **LOAD-BEARING INVARIANT (new/clone path):** the `day_templates` PUT MUST be the FIRST op and ALL slot PUTs MUST follow it **within the same `db.writeTransaction`** (→ one ordered CRUD batch). The server's `applyDayTemplateItem` PUT verifies parent ownership (`day_template.created_by = userID`) BEFORE inserting, so the parent must arrive first in the batch. Do NOT split the day vs its slots across two writeTransactions — every item PUT would then hit "not owned" and be silently skipped (2xx) → a day with zero slots, no error.
  - **Testability:** keep the diff logic PURE — `saveDay` reads (`MAX(position)+1`, the loaded slots) then passes that loaded data + computed positions into a pure reconcile that returns an ordered `List<({String sql, List<Object?> args})>` (built from the `*UpsertOp` builders); the writeTransaction just executes them in order. Unit-test the pure reconcile (below), not the wire PATCH.
- [ ] **Step 4: `DayTemplateRepository.deleteDay(String id)`** — ONE writeTransaction: `DELETE FROM day_template_items WHERE day_template_id=?` then `DELETE FROM day_templates WHERE id=?` (local SQLite has no cascade; both must be emitted so the queue/server stay consistent).
- [ ] **Step 5: slug — collision-proof by construction.** `slug` is **globally** UNIQUE NOT NULL, but the local SQLite mirror only holds shared templates + THIS user's customs (per-user bucket), so local de-dup CANNOT guarantee global uniqueness — a cross-user collision → server `23505` → `isTransient()` treats it as PERMANENT → the op is logged-and-skipped (2xx), so the exercise persists locally but never server-side and vanishes on next sync-down. Therefore generate `slug = slugify(name) + '-' + newId.substring(0,8)` (newId = the row's `uuid.v4()`), which is effectively globally unique without a global view. `slugify`: lowercase, `[^a-z0-9]+`→`-`, trim `-`, fallback `'exercise'`. `createExercise(ExerciseDraft)` = new `uuid.v4()` id + that slug + `exerciseUpsertOp(null, id, draft, slug)`; `updateExercise(String id, ExerciseDraft)` = `exerciseUpsertOp(id, id, draft, _)` (slug NOT changed on update). Both in a `db.writeTransaction`.
- [ ] **Step 6: Test the PURE reconcile** (not a live tx — the existing `FakeExec` only has `execute()`, no `getOptional`/`getAll`, and the wire PATCH carries only PowerSync's column delta which Dart doesn't control). Call the pure reconcile with hand-built "loaded slots" + draft + computed positions and assert the returned ordered `List<Op>`: new day → day PUT FIRST then N slot PUTs at positions 1..n; edit with one slot removed + one reordered → day PATCH, then per-slot PATCH/DELETE/PATCH with contiguous 1..n positions; no `user_id`/`created_at`/`is_template` in any op's columns. Also test `exerciseUpsertOp`/`dayTemplateUpsertOp`/`slotUpsertOp` both branches + `uniqueSlug` (slug ends with the id prefix). The wire-shape (omitted owner cols, contiguous positions on the server) is verified by the Task 6 live psql round-trip. Run `make -C app test`.
- [ ] **Step 7:** `make -C app analyze` clean. **Commit** — "feat(app): plan-editor write methods (saveDay/deleteDay/exercise upsert + slug)"

### Task 3: Shared form primitives + PlanScreen shell + AppShell wiring

**Files:** Create `app/lib/widgets/plan_form.dart`, `app/lib/ui/plan_screen.dart`; Modify `app/lib/shell/app_shell.dart`. Port `screen-plan.jsx` chrome.

- [ ] **Step 1: `plan_form.dart`** — `Field(label, child)`, `TextInput(...)` (h46, surface3, line border, radius*0.6, 15px), `ChipSelect<T>({items, selected, onSelect, labelOf})` (pills; selected=accent/accentInk, else surface/dim/lineStrong — used for weekday AND muscle), `Toggle(value, onChanged)` (50×30), `PrimaryBtn(label, enabled, onTap)` (h52 accent/accentInk, disabled=surface3+faint), `PlanSection(label, {hint})` (mono uppercase). (Check `SectionLabel` before duplicating PlanSection.)
- [ ] **Step 2: `PlanScreen`** (StatefulWidget) — owns header (top safe-area pad; back-chevron when an editor is open else a plan-icon tile; title 'Plan'/'New training day'/'Edit training day'/exercise equivalents) + a `Split|Exercises` segmented toggle (shown only at the list level) + routes the body: `SplitTab` / `LibraryTab` / `DayEditor` / `ExerciseEditor`. Holds editor route state (`{kind, id}`); `onBack` returns to the active sub-tab list.
- [ ] **Step 3: AppShell** — replace `PlaceholderTab(title:'Plan')` at IndexedStack **index 3** with `const PlanScreen()` (import it). Keep Profile placeholder + the placeholder import.
- [ ] **Step 4:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): Plan screen shell + form primitives"

### Task 4: Split sub-tab + DayEditor

**Files:** Create `app/lib/ui/split_tab.dart`, `app/lib/ui/day_editor.dart`. Spec: `screen-plan.jsx` (Split + DayEditor) + the synthesis `splitEditorSpec`.

- [ ] **Step 1: `SplitTab`** — `StreamBuilder` over `DayTemplateRepository.watchDays()`: header `'{N} training days in rotation'`; per-day card (weekday badge = `(d.scheduledWeekday != null && d.scheduledWeekday! >= 0 && d.scheduledWeekday! <= 6) ? weekdayShort(d.scheduledWeekday!) : '–'` — `weekdayShort(int)` is non-nullable and indexes unguarded, so guard the nullable `scheduledWeekday`; slot count, name, faint focus, chevron) → opens `DayEditor(id: day.id)`; dashed 'New training day' → `DayEditor(id: null)`.
- [ ] **Step 2: `DayEditor`** — loads via `byId(id)` into a `DayDraft`; **clone-on-edit**: if the loaded day `isTemplate==true`, start a NEW draft (`id=null`) seeded from its values + show a "Editing creates your own copy" banner. For each loaded `Slot`, `resolveSlot(slot, exercise)` to fill the int targets and keep `itemId=slot.id`. Fields: name `TextInput` (required; Save disabled if empty), focus `TextInput`, weekday `ChipSelect` (Mon..Sun → 0..6). Slot list (one expanded at a time): collapsed row = index, exercise name, mono `'{work}×{repLow}–{repHigh} · RIR {rirToString(low,high)}{ · {warm}wu}'`, up/down reorder (adjacent swap; up disabled at 0, down at last), trash, chevron; expanded = `WStepper` Working (min1) + Warmups (min0), Rep low (min1, bump high≥low) + Rep high (min low), RIR `TextInput` keeping the **raw text** in slot state; commit `(rirLow,rirHigh)` only via a non-throwing `rirTryParse` on save (NOT per-keystroke — `rirParse` uses bare `int.parse` and throws on `''`/`'-'`/`'1-'`). 'Add exercise' → DayEditor holds the catalog (`watchCatalog()`/`all()`) and calls `await showExerciseSheet(context, exercises: catalog, current: null)` (real signature: `(BuildContext, {required List<Exercise> exercises, required String? current})`); guard `if (r == null || r == kBodyweightSentinel) return;` (`kBodyweightSentinel = '__bodyweight__'`, from `exercise_sheet.dart`), then dedupe by exerciseId (block the same exercise twice), append a `SlotDraft(itemId: null)` seeded via `resolveSlot`. **Key each SlotRow by `ValueKey(slot.exerciseId)` and track the one-expanded slot by exerciseId (NOT list index)** — index-based expansion mis-associates after a reorder/remove. `PrimaryBtn` 'Create training day'/'Save changes' → `saveDay(id, draft)` → back. Delete button (only when editing an OWNED day) → confirm dialog → `deleteDay(id)` → back.
- [ ] **Step 3:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): Split editor (day list + day/slot editor)"

### Task 5: Exercises sub-tab + ExerciseEditor

**Files:** Create `app/lib/ui/exercise_library_tab.dart`, `app/lib/ui/exercise_editor.dart`. Spec: `screen-plan.jsx` (Exercises + ExerciseEditor) + synthesis `exerciseEditorSpec`.

- [ ] **Step 1: `LibraryTab`** — `StreamBuilder(watchCatalog())` + a one-shot `prTopSets()` map (resolved in `initState`/FutureBuilder, not N watches): group by `muscleGroup` via `orderedMuscles`/`muscleLabel` (+ `other`); pinned 'New exercise' accent button → `ExerciseEditor(id: null)`; per-row: compound dot, name + mono sub `'{equip ?? muscleLabel}{ · compound}'`, trailing PR `fmtWt(pr)+uLabel` (if `pr>0`), edit icon, optional 'custom' tag for `isTemplate==false`; tap → `ExerciseEditor(id: ex.id)`.
- [ ] **Step 2: `ExerciseEditor`** — draft from `Exercise` (edit) or defaults (new). **Copy-on-edit**: if `exercise.isTemplate==true`, open into a NEW draft (`id=null`) + banner; owned rows edit in place. Identity: name `TextInput` (required), muscle `ChipSelect` over `kMuscleLabels` (the 8 DB groups; if the edited exercise's `muscleGroup` is outside the 8, include it as an extra chip so editing doesn't silently remap it), equipment `TextInput`, Compound `Toggle` (side-effect: turning ON seeds `defaultWarmupSets = 2` if null/0; leave untouched when toggling off). Stats (read-only): PR card (`fmtWt(pr)+uLabel` or '–'); Start-weight `WStepper` in DISPLAY units — `value = fromKg(baseWeightKg ?? 0, unit)`, **`step = fromKg(plateStepKg, unit)`** (NOT raw `plateStepKg`, which is kg → wrong increment in lb mode), `fmtPlain`+`uLabel`; store `base_weight_kg` via `toKg(displayValue, unit)` (watch `UnitService`); a 0/empty start-weight writes NULL (empty), not `0.00`. Default prescription: Rep low/high + Working/Warmups `WStepper`s (clamps), RIR `TextInput` (raw text; commit via non-throwing `rirTryParse` on save → `default_rir_low/high`). `PrimaryBtn` 'Create exercise'/'Save exercise' (disabled if name empty) → `createExercise`/`updateExercise` → back. **No delete button.**
- [ ] **Step 3:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): Exercise library + exercise editor (copy-on-edit)"

### Task 6: Verify + live round-trip (INLINE)
- [ ] **Step 1:** `make -C app analyze` (0 issues); `make -C app test` (all green incl. the plan-write tests); `make -C app build` (Linux bundle links).
- [ ] **Step 2: Live round-trip** — bring the stack up; `make -C app run`; in the Plan tab: create a custom day with 2 slots (reorder them) + save; create a custom exercise; edit a SEEDED day/exercise → confirm a NEW owned copy is created (clone-on-edit), not a ghost edit. Verify via psql that the new `day_templates`/`day_template_items`/`exercises` rows landed with `created_by`=dev user, `is_template=false`, contiguous 1-based slot positions, and that the seeded rows are unchanged.

---

## Deferred
- Profile & Settings + `SettingsService` (client-local unit/theme/accent + **configurable server URL**) — the last screen.
- Delete-exercise (needs a referenced-rows guard or a server cascade decision); day-level reorder; clear-focus-to-NULL (optional forced-PUT backend change).
