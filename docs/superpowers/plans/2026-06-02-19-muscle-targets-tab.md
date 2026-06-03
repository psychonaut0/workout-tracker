# Muscle-Targets Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Edit weekly muscle targets in-app: a third "Targets" segment on the Plan screen listing the 8 canonical muscles, each with a live-persisting stepper (0 = no goal, deletes the row).

**Architecture:** Pure op builders + a routing function (`targetOpFor`) in `MuscleTargetRepository` (TDD), a presentational `TargetsList` (widget-testable, no DB) wrapped by `TargetsTab` (streams `watchTargets`, persists via `setTarget` with `IdentityService.currentUserId`), and a third `_SegBtn` in `plan_screen`. No server change (`applyMuscleTarget` already upserts + deletes).

**Tech Stack:** Flutter 3.44 (fvm, `make -C app`), PowerSync, provider, existing `WStepper`/tokens.

**Spec:** `docs/superpowers/specs/2026-06-02-muscle-targets-tab-design.md`

**Branch:** `muscle-targets-tab` (off `main`).

**Grounding facts (verified):**
- `plan_screen.dart`: `_activeTab: 'split' | 'exercises'`; `_SegmentedToggle` renders two `_SegBtn`s (`label/active/tokens/onTap`); `_buildBody()` routes `_activeTab == 'split'` → `SplitTab` else `LibraryTab`.
- `WStepper({required double value, required double step, required String Function(double) format, required ValueChanged<double> onChanged})` (`lib/widgets/stepper.dart` — confirm `format`/`onChanged` exact types when implementing).
- `MuscleTargetRepository(this.db)` has `watchTargets()` (`SELECT id, muscle, target_sets … ORDER BY muscle`) + `seedDefaultsIfEmpty`. Insert shape: `(id, user_id, muscle, target_sets, created_at)`. `uuid` from `package:powersync/powersync.dart`.
- `kMuscleLabels` (`lib/data/muscles.dart`): 8 ordered keys chest…triceps. `MuscleTarget {id, muscle, targetSets}`.
- `IdentityService` provided in `main.dart`'s `MultiProvider`; `context.read<IdentityService>().currentUserId`.

---

## Task 1: Repo — op builders + `targetOpFor` + `setTarget` (TDD)

**Files:**
- Modify: `app/lib/data/muscle_target_repository.dart`
- Test: `app/test/data/muscle_target_edit_test.dart`

- [ ] **Step 1: Failing test**

Create `app/test/data/muscle_target_edit_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/muscle_target_repository.dart';

void main() {
  const existing = MuscleTarget(id: 't1', muscle: 'chest', targetSets: 12);

  test('no row + sets>0 -> INSERT with user/muscle/sets', () {
    final op = targetOpFor(existing: null, sets: 10, newId: 'new1',
        userId: 'u1', muscle: 'chest', nowIso: '2026-06-02T00:00:00Z');
    expect(op!.sql, contains('INSERT INTO muscle_targets'));
    expect(op.args, ['new1', 'u1', 'chest', 10, '2026-06-02T00:00:00Z']);
  });

  test('existing + sets>0 -> UPDATE by id', () {
    final op = targetOpFor(existing: existing, sets: 15, newId: 'x',
        userId: 'u1', muscle: 'chest', nowIso: 'now');
    expect(op!.sql, 'UPDATE muscle_targets SET target_sets = ? WHERE id = ?');
    expect(op.args, [15, 't1']);
  });

  test('existing + sets==0 -> DELETE by id (no goal)', () {
    final op = targetOpFor(existing: existing, sets: 0, newId: 'x',
        userId: 'u1', muscle: 'chest', nowIso: 'now');
    expect(op!.sql, 'DELETE FROM muscle_targets WHERE id = ?');
    expect(op.args, ['t1']);
  });

  test('no row + sets==0 -> null (no-op)', () {
    expect(targetOpFor(existing: null, sets: 0, newId: 'x',
        userId: 'u1', muscle: 'chest', nowIso: 'now'), isNull);
  });
}
```

- [ ] **Step 2: Run, watch fail** — `make -C app test 2>&1 | tail -15` → FAIL (`targetOpFor` undefined).

- [ ] **Step 3: Implement**

In `app/lib/data/muscle_target_repository.dart`, add top-level (above the class):
```dart
// ── target edit ops ──────────────────────────────────────────────────────────

({String sql, List<Object?> args}) insertTargetOp(
        String id, String userId, String muscle, int sets, String nowIso) =>
    (
      sql: 'INSERT INTO muscle_targets (id, user_id, muscle, target_sets, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
      args: [id, userId, muscle, sets, nowIso],
    );

({String sql, List<Object?> args}) updateTargetOp(String id, int sets) =>
    (sql: 'UPDATE muscle_targets SET target_sets = ? WHERE id = ?', args: [sets, id]);

({String sql, List<Object?> args}) deleteTargetOp(String id) =>
    (sql: 'DELETE FROM muscle_targets WHERE id = ?', args: [id]);

/// Picks the right op for setting [muscle]'s weekly target to [sets]:
/// no row + sets>0 → INSERT; existing + sets>0 → UPDATE; existing + 0 → DELETE
/// ("no goal"); no row + 0 → null (nothing to do).
({String sql, List<Object?> args})? targetOpFor({
  required MuscleTarget? existing,
  required int sets,
  required String newId,
  required String userId,
  required String muscle,
  required String nowIso,
}) {
  if (existing == null) {
    return sets > 0 ? insertTargetOp(newId, userId, muscle, sets, nowIso) : null;
  }
  return sets > 0 ? updateTargetOp(existing.id, sets) : deleteTargetOp(existing.id);
}
```
And the repo method inside the class:
```dart
  /// Live-persists [muscle]'s weekly target to [sets]. 0 = no goal (deletes).
  Future<void> setTarget({
    required String muscle,
    required int sets,
    required String userId,
    required MuscleTarget? existing,
  }) async {
    final op = targetOpFor(
      existing: existing,
      sets: sets,
      newId: uuid.v4(),
      userId: userId,
      muscle: muscle,
      nowIso: DateTime.now().toUtc().toIso8601String(),
    );
    if (op == null) return;
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }
```

- [ ] **Step 4: Run, watch pass** — `make -C app test 2>&1 | grep -E 'All tests passed|failed'` → all pass (current count + 4).

- [ ] **Step 5: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker && git checkout -b muscle-targets-tab
git add app/lib/data/muscle_target_repository.dart app/test/data/muscle_target_edit_test.dart
git commit -m "feat(app): muscle-target edit ops + setTarget (0 = no goal)"
```

---

## Task 2: TargetsTab UI + Plan wiring (TDD on the presentational list)

**Files:**
- Create: `app/lib/ui/targets_tab.dart`
- Modify: `app/lib/ui/plan_screen.dart` (third segment + routing)
- Test: `app/test/ui/targets_tab_test.dart`

- [ ] **Step 1: Failing widget test (presentational `TargetsList`, no DB)**

Create `app/test/ui/targets_tab_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/ui/targets_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xFFD8FF3E)),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders all 8 canonical muscles in order', (tester) async {
    await tester.pumpWidget(_wrap(TargetsList(targets: const {}, onChanged: (_, __) {})));
    for (final label in ['Chest', 'Back', 'Shoulders', 'Quads', 'Hamstrings', 'Calves', 'Biceps', 'Triceps']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('stepper + reports the new value for the right muscle', (tester) async {
    String? muscle; int? sets;
    await tester.pumpWidget(_wrap(TargetsList(
      targets: const {'chest': MuscleTarget(id: 't1', muscle: 'chest', targetSets: 12)},
      onChanged: (m, s) { muscle = m; sets = s; },
    )));
    // Tap the FIRST stepper's "+" (Chest is first in canonical order).
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    expect(muscle, 'chest');
    expect(sets, 13);
  });
}
```
(Adjust `buildTheme`'s real signature and the stepper's actual +/- icon/finder to match `WStepper`'s implementation — read `lib/widgets/stepper.dart` and `app_theme.dart`; the assertions — 8 labels, chest 12→13 — are the contract.)

- [ ] **Step 2: Run, watch fail** — `make -C app test 2>&1 | tail -15` → FAIL (`targets_tab.dart` not found).

- [ ] **Step 3: Implement `targets_tab.dart`**

Create `app/lib/ui/targets_tab.dart` with TWO widgets:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/muscle_target_repository.dart';
import '../data/muscles.dart';
import '../identity/identity_service.dart';
import '../sync/db.dart';
import '../widgets/stepper.dart';

/// Plan ▸ Targets: edit weekly set targets per muscle. Live-persists each
/// change; 0 = no goal (row deleted). Streams the targets so the Progress
/// volume bars update immediately.
class TargetsTab extends StatelessWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MuscleTargetRepository(db);
    return StreamBuilder<List<MuscleTarget>>(
      stream: repo.watchTargets(),
      builder: (context, snap) {
        final byMuscle = {for (final t in snap.data ?? <MuscleTarget>[]) t.muscle: t};
        return TargetsList(
          targets: byMuscle,
          onChanged: (muscle, sets) => repo.setTarget(
            muscle: muscle,
            sets: sets,
            userId: context.read<IdentityService>().currentUserId,
            existing: byMuscle[muscle],
          ),
        );
      },
    );
  }
}

/// Presentational list (testable without a DB): all 8 canonical muscles in
/// kMuscleLabels order; each row a label + WStepper. 0 renders dim ("no goal").
class TargetsList extends StatelessWidget {
  const TargetsList({super.key, required this.targets, required this.onChanged});

  final Map<String, MuscleTarget> targets;
  final void Function(String muscle, int sets) onChanged;

  @override
  Widget build(BuildContext context) {
    // One row per canonical muscle; style rows like the Split/Library lists
    // (tokens, mono caption for the sets count, dim when 0/no-goal).
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (final entry in kMuscleLabels.entries)
          _TargetRow(
            muscle: entry.key,
            label: entry.value,
            sets: targets[entry.key]?.targetSets ?? 0,
            onChanged: (v) => onChanged(entry.key, v),
          ),
      ],
    );
  }
}
```
Implement `_TargetRow` matching the app's visual language: muscle label (body text), a "sets / wk" mono caption, and a `WStepper(value: sets.toDouble(), step: 1, format: (v) => v.round() == 0 ? '—' : v.round().toString(), onChanged: (v) => onChanged(v.round().clamp(0, 40)))`; when `sets == 0` render the label/value in the dim token color (no goal). READ `lib/ui/split_tab.dart` / `library` rows + `lib/widgets/stepper.dart` to match real constructor args + row styling — the structure above is the contract, the styling follows the neighbors.

- [ ] **Step 4: Wire the third segment in `plan_screen.dart`**

- Import: `import 'targets_tab.dart';`
- In `_SegmentedToggle`'s `Row`, after the 'Exercises' `_SegBtn`, add:
```dart
          const SizedBox(width: 6),
          _SegBtn(
            label: 'Targets',
            active: activeTab == 'targets',
            tokens: tokens,
            onTap: () => onSelect('targets'),
          ),
```
- In `_buildBody()`, before the `LibraryTab` fallback:
```dart
    if (_activeTab == 'targets') {
      return const TargetsTab();
    }
```

- [ ] **Step 5: Run, watch pass** — `make -C app test 2>&1 | grep -E 'All tests passed|failed'` and `make -C app analyze 2>&1 | grep -iE 'no issues|error'` → all pass + no issues.

- [ ] **Step 6: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/ui/targets_tab.dart app/lib/ui/plan_screen.dart app/test/ui/targets_tab_test.dart
git commit -m "feat(app): Targets tab under Plan — edit weekly muscle targets"
```

---

## Task 3: Verify (INLINE)

- [ ] **Step 1:** `make -C app analyze` (0 issues) + `make -C app test` (all green) + `make -C app build` (Linux links).
- [ ] **Step 2:** Headless smoke (fresh profile, 20s, no crash) — the tab is behind a tap so the smoke just guards startup.
- [ ] **Step 3:** Merge `--no-ff` → main, push. Build a **release** APK (`make -C app build-apk-release`) + install on the phone; the user verifies: Plan ▸ Targets shows 8 muscles, stepping persists, 0 shows "—/no goal", Progress volume bars reflect changes live, and the change syncs to the homelab (`muscle_targets` row count/values in the ct-workout DB).

## Verification summary
1. 4 new op tests + 2 widget tests green; analyze clean; build links.
2. On-device: edit targets in Plan ▸ Targets; dashboard updates; homelab DB reflects the change after sync.

## Out of scope
Custom muscles; per-day targets; other deferred polish.
