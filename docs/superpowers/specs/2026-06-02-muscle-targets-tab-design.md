# Muscle-targets editing (Targets tab under Plan) — design

**Date:** 2026-06-02
**Status:** Approved (design)
**Scope:** Let the user edit their weekly muscle targets in-app. A third **"Targets"** segment on the Plan screen's existing Split|Exercises toggle, listing the 8 canonical muscles with a stepper each. Closes the "muscle_targets editing UI" deferred item (targets were previously only seeded — onboarding/dev — and uneditable).

## UI
- `lib/ui/plan_screen.dart`: extend the segmented toggle (`_activeTab: 'split' | 'exercises'`) with `'targets'` → renders a new `TargetsTab`.
- **Create `lib/ui/targets_tab.dart`**: streams `MuscleTargetRepository.watchTargets()`; renders **all 8 canonical muscles** in `kMuscleLabels` order (Chest, Back, Shoulders, Quads, Hamstrings, Calves, Biceps, Triceps), one row each: muscle label + weekly target sets via `WStepper` (step 1, min 0, sensible max e.g. 40). Match the Plan screen's existing visual language (tokens, mono labels, row styling).
- A muscle with **no target row shows 0, styled dim as "no goal"** (the Progress dashboard already treats goalless muscles as on-target).

## Behavior
- **Live-persist** on every stepper tap (no Save button — matches the set editor / active session).
- Increment on a goalless muscle → **INSERT** a row (`uuid.v4()`, `user_id = IdentityService.currentUserId`, the muscle, the value).
- Change on an existing row → **UPDATE by row id** (`target_sets` only).
- Decrement to **0 → DELETE the row** ("no goal").
- Progress volume bars update live via the existing `watchTargets()` stream — no dashboard changes.

## Data layer
`lib/data/muscle_target_repository.dart` gains pure op builders + a method, following the repo's established TDD pattern:
- `insertTargetOp(id, userId, muscle, sets, nowIso)`, `updateTargetOp(id, sets)`, `deleteTargetOp(id)` — `({String sql, List<Object?> args})` records.
- `Future<void> setTarget({required String muscle, required int sets, required String userId, MuscleTarget? existing})` — picks insert/update/delete-at-zero from `existing` + `sets`, runs in a `writeTransaction`.

## Sync
**No server change.** `applyMuscleTarget` already upserts `ON CONFLICT (user_id, muscle) DO UPDATE` and handles owner-gated DELETE, and stamps `user_id` from the JWT on upload — so rows inserted locally with the local `currentUserId` converge to the account's identity after sync.

## Edge cases
- Start-empty users (no seeded targets): the tab shows all 8 at "no goal"; setting values creates rows.
- Concurrent seed: the onboarding/today seed only runs when the table is empty — no conflict with edits.
- Unknown muscle keys (future-proofing): not rendered for editing; taxonomy is the fixed 8 (`kMuscleLabels`).

## Testing
- Unit: the three op builders (SQL + args, incl. delete-at-zero routing in `setTarget` via a FakeExec-style executor or by asserting the chosen op).
- Widget: `TargetsTab` renders 8 rows in canonical order and reports stepper changes; goalless rows render the no-goal state.
- Existing suite stays green.

## Out of scope
Custom muscles / editing the taxonomy; per-day or per-exercise targets; rest of the deferred polish list.
