# Ownership overhaul + plan/workout UX fixes

**Date:** 2026-06-04
**Status:** Approved (design)
**Scope:** Kill the "locked templates" model (user's general rule: nothing in the app is read-only): a one-time absorb migration copies synced template rows into user-owned rows and re-points local references; the UI shows owned rows only; clone-on-edit is deleted from both Plan editors. Plus: exercise delete with an FK guard, tap-to-type weight input on steppers, Bodyweight-view status-bar inset, FAB nudged lower. Ships as v0.9.0.

## Background (root causes, verified)

- The Plan editors treat `is_template=1` rows as read-only: editing clones (`day_editor.dart:156-158` — `_isClone = day.isTemplate; _editId = day.isTemplate ? null : day.id;`; same pattern `exercise_editor.dart:141-142`), and the day delete button only shows for owned days (`day_editor.dart:271,367`). A synced phone's whole split IS the four server templates → every save "duplicates" the day, nothing is deletable. Working as coded, wrong as a product.
- Server enforcement (sync_upload.go): clients can never PUT/PATCH/DELETE template rows (`created_by NULL` fails the ownership WHERE). BUT `sets.exercise_id`, `day_template_items.exercise_id`, and `sessions.day_template_id` are NOT ownership-validated — any id is accepted. So re-pointing references from template ids to owned-copy ids syncs cleanly.
- Spec B's `dedupeCatalog` (`exercise_repository.dart:99-113`) already hides templates that have an owned name-twin.
- Exercise delete simply doesn't exist (`exercise_editor.dart:519`, no repo method) — deferred since the plan editors shipped because of the server FK RESTRICT.

## 1. Absorb migration (`app/lib/data/template_absorb.dart`, new)

Runs once per boot in `main()` after `openDatabase()` + identity init (before `runApp`). Pure-ops + thin executor, mirroring the codebase's write-layer style.

**Key mechanism — deterministic copy ids.** The owned copy of template `T` for user `U` always gets id `uuid.v5(<fixed app namespace uuid>, '$U:$T')`. This makes the absorb idempotent with NO bookkeeping:
- Re-running skips any template whose copy id already exists locally (`SELECT EXISTS`).
- Renaming your copy never re-absorbs (identity is id-derived, not name-derived).
- A second device of the same account derives the SAME copy ids — either the first device's copies have already synced down (EXISTS → skip) or both devices PUT identical-id rows and the server's idempotent upsert converges.
- The old→new mapping is a pure function, recomputable forever — future template days referencing previously-absorbed exercises re-point correctly with no persisted map.

**Algorithm (per boot):**
1. `SELECT` all local `is_template=1` exercises and day_templates (+ their `day_template_items`).
2. For each template row whose deterministic copy id does NOT already exist locally:
   - **Exercise**: INSERT the owned copy (copy id, same columns, `is_template=0`, `created_by=currentUserId`, fresh `created_at`, slug suffixed with the copy id's first 8 chars per the existing slug convention); then `UPDATE sets SET exercise_id=<copy> WHERE exercise_id=<template>` and `UPDATE day_template_items SET exercise_id=<copy> WHERE exercise_id=<template>`.
   - **Day template**: INSERT the owned copy (copy id, same name/focus/weekday/position, `is_template=0`, `created_by=currentUserId`) + owned copies of its items (item ids also deterministic — `uuid.v5(ns, '$U:$itemId')`; `day_template_id` → the day's copy id; item `exercise_id` → that exercise's deterministic copy id IF a row with that id exists or was created this run, else unchanged); then `UPDATE sessions SET day_template_id=<copy> WHERE day_template_id=<template>`.
3. Everything in ONE `db.writeTransaction` — a crash mid-migration can't half-absorb (next boot redoes the whole thing; the EXISTS checks and `WHERE old-id` rewrites are naturally idempotent).

**Properties:**
- Offline-only installs: no template rows → no-op.
- Future server templates sync down → absorbed on next boot (between sync and next boot they're invisible, not locked — see §2 filters).
- PowerSync upload: the new owned rows PUT, the reference rewrites PATCH — all user-owned writes the server accepts. Template rows themselves are never mutated (they keep syncing down; the UI just never shows them).
- `uuid.v5` availability: the project uses the `uuid` singleton re-exported by package:powersync — verify `v5` is exposed; if not, depend on `package:uuid` directly (it's already a transitive dep) and use its `Uuid().v5(Namespace.oid, ...)` with a fixed app namespace constant.

## 2. Owned-only UI + clone-on-edit removal

- `DayTemplateRepository.watchDays`/`byId`/rotation queries: add `WHERE is_template = 0` (covers Plan split tab, Today hero pager, `nextInRotation`, `templateIdsTrainedThisWeek`).
- `ExerciseRepository.watchCatalog`/`all`: filter `is_template = 1` rows out entirely (replaces the name-twin dedup as the primary mechanism; KEEP `dedupeCatalog` applied after the filter is moot — delete the dedup call and keep the function only if other call sites use it; otherwise remove it and its test in favor of the filter). Pickers receive the filtered list automatically.
- `day_editor.dart`: delete `_isClone`, the clone banner, and the `day.isTemplate ? null : day.id` branches — `_editId = day.id` always; delete button always shows for an existing day.
- `exercise_editor.dart`: same — delete `_isClone`/banner/branches; editing always updates in place.
- `models.dart` `DayTemplate.isTemplate` stays (the filter needs it); the "custom" tag in the exercise library becomes meaningless (everything is custom) → remove the tag.

## 3. Exercise delete (FK-guarded)

- `ExerciseRepository` gains:
  - `Future<({int setCount, int dayCount})> exerciseReferences(String id)` — `COUNT(*)` over `sets WHERE exercise_id=?` and `COUNT(DISTINCT day_template_id)` over `day_template_items WHERE exercise_id=?`.
  - `Future<void> deleteExercise(String id, {required bool removeFromDays})` — one writeTransaction: when `removeFromDays`, `DELETE FROM day_template_items WHERE exercise_id=?` first; then `DELETE FROM exercises WHERE id=?`.
- Pure decision helper (testable): `ExerciseDeleteAction decideExerciseDelete({required int setCount, required int dayCount})` → `blockedByHistory | confirmWithDays(dayCount) | confirmPlain`.
- Exercise editor gains a Delete button (danger style, below the primary action; only when editing an existing exercise):
  - `blockedByHistory` → `showWDialog` notice: "Used in N logged sets — delete the history first." (single OK action).
  - `confirmWithDays` → `showWConfirm` destructive: "Also removes it from X training day(s)."
  - `confirmPlain` → `showWConfirm` destructive: "This cannot be undone."
  - On delete → pop back to the library.
- Server accepts the DELETE (owned row, references cleaned first). Another user referencing your exercise id is theoretically possible but practically excluded by sync visibility — if the server-side FK still rejects, the per-op SAVEPOINT skips and the row resyncs (accepted rare edge).

## 4. Tap-to-type weight input (`widgets/stepper.dart`)

`WStepper` gains `editable: bool = false`. When true, tapping the value swaps it for an inline `TextField`:
- `keyboardType: TextInputType.numberWithOptions(decimal: true)`, pre-filled with the current display value, select-all on focus.
- Commit on submit/focus-loss: parse (accept `,` as decimal separator), clamp ≥ 0, route through the existing `onChanged` exactly as +/- does (same kg/display-space handling — READ how WStepper's value flows today and keep it identical); invalid input → revert, no change event.
- Visual: same mono value style, accent underline/caret; +/- buttons stay functional around it.
- Enabled at: session `set_row.dart` weight stepper, History `_SetEditorSheet` weight stepper. Reps/RIR unchanged. The existing stepper haptic/animation behavior stays for +/- taps; direct edits skip the directional slide (value swaps via the existing AnimatedSwitcher naturally).

## 5. Small fixes

- `bodyweight_view.dart`: list padding becomes `EdgeInsets.fromLTRB(16, 8 + MediaQuery.paddingOf(context).top, 16, 96)` (mirror `progress_screen.dart:195`).
- `w_tab_bar.dart:101`: FAB straddle `Offset(0, -22)` → `Offset(0, -14)`.
- Mini-bar (`app_shell.dart` `bottom: 105`): verify visually after the FAB shift; adjust only if they collide.

## 6. Weight-step question (answered, no change)

The +/- step is the exercise's `plate_step_kg` (catalog: barbells 2.5 kg, dumbbells 2, machines 5; lb mode converts). Already editable per exercise in the exercise editor — and after §1/§2, editable for every exercise. No code change.

## Constraints

- Migration must be crash-safe (single tx; prefs written after commit) and never run DDL.
- No data loss: history (sets/sessions) keeps resolving — re-pointed ids exist in the same tx.
- All 196 existing tests stay green; tests that seeded `is_template=1` fixtures for UI lists may need updating to the new filtered reality (update fixtures, not the filters).
- Sync safety: only user-owned rows are written; template rows are never mutated.

## Testing

- Pure: deterministic copy-id derivation (stable, distinct per user/template), absorb op-builder (copies columns, stamps ownership, slug suffix, item re-pointing incl. cross-boot exercise lookups), reference-rewrite ops, idempotency (second run = zero ops; rename-safe), `decideExerciseDelete` matrix.
- Repository: `watchDays`/`watchCatalog` filter templates; `exerciseReferences` counts; `deleteExercise` with/without `removeFromDays`.
- Widget: WStepper editable mode (tap → type → commit; invalid revert; clamp); editor delete button states.
- On-device (user): phone migrates once (split becomes 4 owned editable/deletable days, history/PRs intact, rotation still works), exercise edit-in-place + delete flows, weight typing in session + history, bodyweight inset, FAB position.

## Out of scope

Uniform weight steps; reps/RIR direct input; deleting template rows server-side; sync-rules changes. (Multi-device absorb coordination is IN scope and solved by the deterministic copy ids in §1 — no extra mechanism needed.)
