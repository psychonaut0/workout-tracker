# Ownership Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing in the app is locked: a boot-time absorb migration copies synced template rows into user-owned rows (deterministic ids, references re-pointed), the UI shows owned rows only, clone-on-edit is deleted, exercises become deletable behind an FK guard, weight steppers accept typed input, plus two small visual fixes — per `docs/superpowers/specs/2026-06-04-ownership-overhaul-design.md`. Ships as v0.9.0.

**Architecture:** New `data/template_absorb.dart` (pure op builders + thin executor mirroring `top_set_backfill.dart`'s pattern), `WHERE is_template = 0` filters in the two repositories, clone-path deletion in both editors, `decideExerciseDelete` pure helper + repo methods + editor UI, `WStepper.editable` inline TextField mode.

**Tech Stack:** Flutter 3.44 (fvm), PowerSync SQLite, `uuid` v5 (deterministic copy ids — new DIRECT dependency on `package:uuid`, already transitive at 4.5.3).

**Conventions:**
- Branch: create `ownership-overhaul` off `main` first.
- Makefile only, from repo root: `make -C app analyze`, `make -C app test`, `make -C app get`, `make -C app build`. NEVER run `flutter` directly.
- Baseline: 196 tests green, analyze clean.
- Commit style: Conventional Commits, subject line only, no body.
- Test import prefix `package:workout_tracker/...`.

**Verified facts:**
- Server (sync_upload.go): clients can never write template rows (`created_by NULL` fails ownership WHERE), but `sets.exercise_id` / `day_template_items.exercise_id` / `sessions.day_template_id` are NOT ownership-validated — re-pointing them to owned copies syncs fine. Owned-row PUT/PATCH/DELETE all work.
- Clone-on-edit: `day_editor.dart` `_loadData` (`_isClone = day.isTemplate; _editId = day.isTemplate ? null : day.id;` and slots get `day.isTemplate ? null : slot.id`), banner at `if (_isClone) _CloneBanner(...)`, delete gated by `isOwned = _editId != null`. Same pattern in `exercise_editor.dart` (`final isClone = ex.isTemplate; final editId = isClone ? null : ex.id;`).
- `watchDays` (day_template_repository.dart:263) has no template filter; `watchCatalog` (exercise_repository.dart:126) filters via `dedupeCatalog` name-twins only; `all()` (:141) unfiltered; `nextInRotation` derives from `watchDays`.
- Schema columns — exercises: `id, name, slug, muscle_group, is_template, created_by, created_at, equip, compound, base_weight_kg, plate_step_kg, default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, default_rir_low, default_rir_high`; day_templates: `id, slug, name, notes, position, is_template, created_by, created_at, focus, scheduled_weekday`; day_template_items: `id, day_template_id, exercise_id, position, target_warmup_sets, target_working_sets, target_rep_low, target_rep_high, target_rir_low, target_rir_high, is_template, created_by, created_at`.
- Migration executor pattern to mirror: `top_set_backfill.dart` — `db.getAll(...)` then `db.writeTransaction((tx) async { for (...) await tx.execute(...); })`.
- main.dart boot: `await backfillTopSets(db);` sits after `identity.init(...)` — the absorb call goes right after it (identity.currentUserId is ready).
- `uniqueSlug(name, id)` exists in exercise_repository.dart (slugify + `-id8` suffix) — reuse (import or move if private; check visibility).
- WStepper (widgets/stepper.dart): `{value, step, format, onChanged}`, internal `_internalValue` in caller-space (kg for weights), `format` caller-supplied, +/- via `_step(dir)` with clamp `next < 0 ? 0.0 : next` + selectionClick + AnimatedSwitcher value slide. Weight call sites: set_row.dart:213-224 and history_screen.dart `_SetEditorSheet` :1156-1165 (both `value: set.weightKg, step: exercise.plateStepKg, format: unit.fmtWt`). targets_tab.dart uses WStepper too — must keep working unchanged (no `editable`).
- bodyweight_view.dart:66-67: `ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 96))` — missing the status-bar inset that progress_screen.dart:195 has.
- w_tab_bar.dart:101: `Transform.translate(offset: const Offset(0, -22), child: _FabButton(...))`. Mini-bar docks at `bottom: 105` in app_shell.dart.
- Exercise library "custom" tag: exercise_library_tab.dart:300-319 (`if (!exercise.isTemplate) ... 'custom' tag`).

---

### Task 1: Absorb migration (TDD)

**Files:**
- Create: `app/lib/data/template_absorb.dart`
- Modify: `app/pubspec.yaml` (direct `uuid` dep), `app/lib/main.dart`
- Test: `app/test/data/template_absorb_test.dart`

- [ ] **Step 1: Add the uuid dependency.** In `app/pubspec.yaml` dependencies:
```yaml
  # Deterministic v5 ids for the template-absorb migration.
  uuid: ^4.5.0
```
Run `make -C app get`. Check the resolved v5 API (`~/.pub-cache/hosted/pub.dev/uuid-4.x/lib/`): modern form is `const Uuid().v5(Namespace.oid.value, name)` (namespace as a uuid STRING + name); adapt the call if the signature differs.

- [ ] **Step 2: Write the failing tests**

`app/test/data/template_absorb_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/template_absorb.dart';

void main() {
  const user = 'user-1';

  Map<String, Object?> tmplExercise(String id, {String name = 'Bench Press'}) => {
        'id': id,
        'name': name,
        'slug': 'bench-press',
        'muscle_group': 'chest',
        'is_template': 1,
        'created_by': null,
        'created_at': '2026-01-01T00:00:00Z',
        'equip': 'Barbell',
        'compound': 1,
        'base_weight_kg': '20',
        'plate_step_kg': '2.5',
        'default_rep_low': 8,
        'default_rep_high': 12,
        'default_warmup_sets': 2,
        'default_working_sets': 3,
        'default_rir_low': 1,
        'default_rir_high': 2,
      };

  Map<String, Object?> tmplDay(String id, {String name = 'Upper A'}) => {
        'id': id,
        'slug': 'upper-a',
        'name': name,
        'notes': null,
        'position': 1,
        'is_template': 1,
        'created_by': null,
        'created_at': '2026-01-01T00:00:00Z',
        'focus': 'Push',
        'scheduled_weekday': 0,
      };

  Map<String, Object?> tmplItem(String id, String dayId, String exId) => {
        'id': id,
        'day_template_id': dayId,
        'exercise_id': exId,
        'position': 1,
        'target_warmup_sets': 2,
        'target_working_sets': 3,
        'target_rep_low': 8,
        'target_rep_high': 12,
        'target_rir_low': 1,
        'target_rir_high': 2,
        'is_template': 1,
        'created_by': null,
        'created_at': '2026-01-01T00:00:00Z',
      };

  group('absorbCopyId', () {
    test('is deterministic and user/template-scoped', () {
      final a = absorbCopyId(user, 't1');
      expect(a, absorbCopyId(user, 't1'));
      expect(a, isNot(absorbCopyId(user, 't2')));
      expect(a, isNot(absorbCopyId('user-2', 't1')));
      // Valid uuid shape.
      expect(a, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });

  group('absorbOps', () {
    test('copies an exercise with ownership stamped and rewrites references',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: const [],
        templateItems: const [],
        existingIds: const {},
        nowIso: '2026-06-04T10:00:00Z',
      );
      final copyId = absorbCopyId(user, 'ex-t');

      // INSERT copy, then rewrite sets + items references.
      final insert = ops.firstWhere((o) => o.sql.startsWith('INSERT INTO exercises'));
      expect(insert.args, contains(copyId));
      expect(insert.args, contains(user)); // created_by
      expect(insert.args, contains(0)); // is_template
      expect(insert.args, contains('Bench Press'));

      final setRewrite = ops.firstWhere((o) => o.sql.contains('UPDATE sets'));
      expect(setRewrite.args, [copyId, 'ex-t']);
      final itemRewrite =
          ops.firstWhere((o) => o.sql.contains('UPDATE day_template_items'));
      expect(itemRewrite.args, [copyId, 'ex-t']);
    });

    test('copies a day with its items, re-pointing exercise ids, and rewrites sessions',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: [tmplDay('day-t')],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-t')],
        existingIds: const {},
        nowIso: '2026-06-04T10:00:00Z',
      );
      final dayCopy = absorbCopyId(user, 'day-t');
      final exCopy = absorbCopyId(user, 'ex-t');
      final itemCopy = absorbCopyId(user, 'item-t');

      final dayInsert =
          ops.firstWhere((o) => o.sql.startsWith('INSERT INTO day_templates'));
      expect(dayInsert.args, contains(dayCopy));
      expect(dayInsert.args, contains('Upper A'));
      expect(dayInsert.args, contains(user));

      final itemInsert = ops
          .firstWhere((o) => o.sql.startsWith('INSERT INTO day_template_items'));
      expect(itemInsert.args, contains(itemCopy));
      expect(itemInsert.args, contains(dayCopy)); // re-pointed parent
      expect(itemInsert.args, contains(exCopy)); // re-pointed exercise

      final sessionRewrite =
          ops.firstWhere((o) => o.sql.contains('UPDATE sessions'));
      expect(sessionRewrite.args, [dayCopy, 'day-t']);
    });

    test('skips templates whose copy already exists (idempotent / cross-device)',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: [tmplDay('day-t')],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-t')],
        existingIds: {absorbCopyId(user, 'ex-t'), absorbCopyId(user, 'day-t')},
        nowIso: '2026-06-04T10:00:00Z',
      );
      expect(ops, isEmpty);
    });

    test('no templates → no ops', () {
      expect(
        absorbOps(
          userId: user,
          templateExercises: const [],
          templateDays: const [],
          templateItems: const [],
          existingIds: const {},
          nowIso: 'x',
        ),
        isEmpty,
      );
    });

    test('item referencing a non-template exercise keeps its id', () {
      final ops = absorbOps(
        userId: user,
        templateExercises: const [],
        templateDays: [tmplDay('day-t')],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-owned')],
        existingIds: const {},
        nowIso: 'x',
      );
      final itemInsert = ops
          .firstWhere((o) => o.sql.startsWith('INSERT INTO day_template_items'));
      expect(itemInsert.args, contains('ex-owned'));
    });
  });
}
```

- [ ] **Step 3: Run `make -C app test` — expect FAIL** (file missing).

- [ ] **Step 4: Implement `app/lib/data/template_absorb.dart`**
```dart
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:uuid/uuid.dart';

import 'exercise_repository.dart' show uniqueSlug; // adjust if uniqueSlug lives elsewhere/private — if private, copy the helper here with a comment

/// Fixed namespace for deterministic absorb ids — never change this value.
const _absorbNamespace = '7d9f0a3c-4b2e-4f81-9c5d-1e6a8b0f2d47';

/// The owned copy's id for template [templateId] under user [userId].
/// Deterministic: same inputs → same id on every boot and every device,
/// which is the entire idempotency mechanism of the absorb migration.
String absorbCopyId(String userId, String templateId) =>
    const Uuid().v5(_absorbNamespace, '$userId:$templateId');

typedef AbsorbOp = ({String sql, List<Object?> args});

/// Builds the SQL ops that absorb synced template rows into user-owned rows:
/// owned copies (deterministic ids, ownership stamped) + reference rewrites
/// (sets.exercise_id, day_template_items.exercise_id, sessions.day_template_id).
/// Pure: rows in, ops out. Templates whose copy id is in [existingIds] are
/// skipped (already absorbed — possibly by another device).
List<AbsorbOp> absorbOps({
  required String userId,
  required List<Map<String, Object?>> templateExercises,
  required List<Map<String, Object?>> templateDays,
  required List<Map<String, Object?>> templateItems,
  required Set<String> existingIds,
  required String nowIso,
}) {
  final ops = <AbsorbOp>[];

  // Map EVERY template exercise id → its copy id (items re-point through this
  // even for exercises absorbed on an earlier boot — the template rows keep
  // syncing down, so they're always in [templateExercises]).
  final exCopyIds = {
    for (final e in templateExercises)
      e['id'] as String: absorbCopyId(userId, e['id'] as String),
  };

  for (final e in templateExercises) {
    final oldId = e['id'] as String;
    final copyId = exCopyIds[oldId]!;
    if (existingIds.contains(copyId)) continue;
    ops.add((
      sql: 'INSERT INTO exercises '
          '(id, slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg, '
          'default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, '
          'default_rir_low, default_rir_high, is_template, created_by, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        copyId,
        uniqueSlug(e['name'] as String, copyId),
        e['name'],
        e['muscle_group'],
        e['equip'],
        e['compound'],
        e['base_weight_kg'],
        e['plate_step_kg'],
        e['default_rep_low'],
        e['default_rep_high'],
        e['default_warmup_sets'],
        e['default_working_sets'],
        e['default_rir_low'],
        e['default_rir_high'],
        0,
        userId,
        nowIso,
      ],
    ));
    ops.add((
      sql: 'UPDATE sets SET exercise_id = ? WHERE exercise_id = ?',
      args: [copyId, oldId],
    ));
    ops.add((
      sql: 'UPDATE day_template_items SET exercise_id = ? WHERE exercise_id = ?',
      args: [copyId, oldId],
    ));
  }

  final itemsByDay = <String, List<Map<String, Object?>>>{};
  for (final it in templateItems) {
    (itemsByDay[it['day_template_id'] as String] ??= []).add(it);
  }

  for (final d in templateDays) {
    final oldId = d['id'] as String;
    final copyId = absorbCopyId(userId, oldId);
    if (existingIds.contains(copyId)) continue;
    ops.add((
      sql: 'INSERT INTO day_templates '
          '(id, name, focus, scheduled_weekday, position, is_template, created_by, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        copyId,
        d['name'],
        d['focus'],
        d['scheduled_weekday'],
        d['position'],
        0,
        userId,
        nowIso,
      ],
    ));
    for (final it in itemsByDay[oldId] ?? const <Map<String, Object?>>[]) {
      final exId = it['exercise_id'] as String;
      ops.add((
        sql: 'INSERT INTO day_template_items '
            '(id, day_template_id, exercise_id, position, target_warmup_sets, '
            'target_working_sets, target_rep_low, target_rep_high, '
            'target_rir_low, target_rir_high, is_template, created_by, created_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        args: [
          absorbCopyId(userId, it['id'] as String),
          copyId,
          exCopyIds[exId] ?? exId, // re-point only known template exercises
          it['position'],
          it['target_warmup_sets'],
          it['target_working_sets'],
          it['target_rep_low'],
          it['target_rep_high'],
          it['target_rir_low'],
          it['target_rir_high'],
          0,
          userId,
          nowIso,
        ],
      ));
    }
    ops.add((
      sql: 'UPDATE sessions SET day_template_id = ? WHERE day_template_id = ?',
      args: [copyId, oldId],
    ));
  }

  return ops;
}

/// Boot-time executor: absorbs all visible templates. Returns the number of
/// ops applied (0 = nothing to do — the common case).
Future<int> absorbTemplates(PowerSyncDatabase db, String userId) async {
  final exRows = await db.getAll(
      'SELECT * FROM exercises WHERE is_template = 1');
  final dayRows = await db.getAll(
      'SELECT * FROM day_templates WHERE is_template = 1');
  if (exRows.isEmpty && dayRows.isEmpty) return 0;
  final itemRows = await db.getAll(
      'SELECT * FROM day_template_items WHERE is_template = 1');

  final existingExercise =
      await db.getAll('SELECT id FROM exercises WHERE is_template = 0');
  final existingDays =
      await db.getAll('SELECT id FROM day_templates WHERE is_template = 0');
  final existingIds = {
    ...existingExercise.map((r) => r['id'] as String),
    ...existingDays.map((r) => r['id'] as String),
  };

  final ops = absorbOps(
    userId: userId,
    templateExercises:
        [for (final r in exRows) Map<String, Object?>.from(r)],
    templateDays: [for (final r in dayRows) Map<String, Object?>.from(r)],
    templateItems: [for (final r in itemRows) Map<String, Object?>.from(r)],
    existingIds: existingIds,
    nowIso: DateTime.now().toUtc().toIso8601String(),
  );
  if (ops.isEmpty) return 0;

  await db.writeTransaction((tx) async {
    for (final op in ops) {
      await tx.execute(op.sql, op.args);
    }
  });
  return ops.length;
}
```
NOTE on `uniqueSlug`: it lives in `exercise_repository.dart` — check whether it's a top-level public function. If yes, import it (`show uniqueSlug`); if private/method, move it to a shared location or duplicate minimally WITH a comment pointing at the original. Verify the `Uuid().v5` call shape against the resolved package (Step 1) — namespace likely needs `Namespace`-style or plain uuid-string first arg; `_absorbNamespace` is a plain uuid string.

- [ ] **Step 5: Wire into `app/lib/main.dart`.** Import `data/template_absorb.dart`. Right after `await backfillTopSets(db);`:
```dart
  // Absorb synced template rows into user-owned rows (nothing is locked).
  await absorbTemplates(db, identity.currentUserId);
```

- [ ] **Step 6: `make -C app analyze` (clean) + `make -C app test` — expect 202 (196 + 6).**

- [ ] **Step 7: Commit**
```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/data/template_absorb.dart app/lib/main.dart app/test/data/template_absorb_test.dart
git commit -m "feat(app): absorb template rows into user-owned copies at boot"
```

---

### Task 2: Owned-only UI + clone-on-edit removal

**Files:**
- Modify: `app/lib/data/day_template_repository.dart`, `app/lib/data/exercise_repository.dart`, `app/lib/ui/day_editor.dart`, `app/lib/ui/exercise_editor.dart`, `app/lib/ui/exercise_library_tab.dart`
- Modify/Delete tests: `app/test/data/catalog_dedup_test.dart` (replaced)

- [ ] **Step 1: Repository filters.**
- `day_template_repository.dart` `watchDays` (:263): SQL → `'... FROM day_templates dt WHERE dt.is_template = 0 ORDER BY dt.position'`. (`byId` stays unfiltered — editors only reach it via the filtered list, and stray references must still resolve.)
- `exercise_repository.dart`:
  - `watchCatalog` (:126): SQL → `'SELECT * FROM exercises WHERE is_template = 0 ORDER BY name'`; REMOVE the `dedupeCatalog(...)` call (map rows directly).
  - `all()` (:141): same `WHERE is_template = 0` filter (used by pickers + day editor catalog; `byId` stays unfiltered for stray history references).
  - DELETE the `dedupeCatalog` function if nothing else uses it (grep) and DELETE `app/test/data/catalog_dedup_test.dart`, replacing it with a filter test:

`app/test/data/exercise_catalog_filter_test.dart` — NOTE: `watchCatalog` needs a live DB; instead test at the SQL-string level is brittle. Skip a dedicated test here — the absorb tests + existing repo usage cover behavior; the on-device check is the real gate. (If an existing test asserted dedup behavior, delete it with the function.)

- [ ] **Step 2: `day_editor.dart` — kill the clone path.**
- In `_loadData`: slots always keep their ids — `slots.add(_slotStateFromResolved(resolved, slot.id));`; state: `_isClone = false;` → DELETE the `_isClone` field and every reference; `_editId = day.id;`.
- DELETE `if (_isClone) _CloneBanner(tokens: tokens),` and the whole `_CloneBanner` class.
- `isOwned = _editId != null` stays (distinguishes NEW day from existing) — the delete button now shows for every existing day.

- [ ] **Step 3: `exercise_editor.dart` — same.**
- `_loadData`: DELETE `final isClone = ex.isTemplate; final editId = isClone ? null : ex.id;` → `_editId = ex.id;` directly; DELETE the `_isClone` field, its banner usage, and the `_CloneBanner` class in this file.
- `btnLabel`/`isNew` logic: `final isNew = _editId == null;` and `btnLabel = isNew ? 'Create exercise' : 'Save exercise';`.

- [ ] **Step 4: `exercise_library_tab.dart` — remove the 'custom' tag** (:300-319, the `if (!exercise.isTemplate) ...[...]` block — everything visible is custom now).

- [ ] **Step 5: Verify.** `make -C app analyze` clean (unused `_CloneBanner`/imports flagged → remove); `make -C app test` — the dedup test is gone, everything else green (expect 201 = 202 − 1, adjust to actual). If `plan_write_test.dart` or others assert clone behavior or seed `is_template: 1` fixtures expecting them listed, update the FIXTURES to the owned-only reality.

- [ ] **Step 6: Commit**
```bash
git add -A app/lib app/test
git commit -m "feat(app): owned-only plan UI — remove clone-on-edit and template filtering by name"
```

---

### Task 3: Exercise delete with FK guard (TDD)

**Files:**
- Modify: `app/lib/data/exercise_repository.dart`, `app/lib/ui/exercise_editor.dart`
- Test: `app/test/data/exercise_delete_test.dart`

- [ ] **Step 1: Write the failing pure-decision tests**

`app/test/data/exercise_delete_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/exercise_repository.dart';

void main() {
  test('referenced by sets → blocked', () {
    expect(decideExerciseDelete(setCount: 3, dayCount: 0),
        ExerciseDeleteAction.blockedByHistory);
    expect(decideExerciseDelete(setCount: 1, dayCount: 2),
        ExerciseDeleteAction.blockedByHistory);
  });

  test('referenced only by days → confirm with day removal', () {
    expect(decideExerciseDelete(setCount: 0, dayCount: 2),
        ExerciseDeleteAction.confirmWithDays);
  });

  test('unreferenced → plain confirm', () {
    expect(decideExerciseDelete(setCount: 0, dayCount: 0),
        ExerciseDeleteAction.confirmPlain);
  });
}
```

- [ ] **Step 2: Run `make -C app test` — expect FAIL.**

- [ ] **Step 3: Implement in `exercise_repository.dart`:**
```dart
/// What deleting an exercise requires, given its references.
enum ExerciseDeleteAction { blockedByHistory, confirmWithDays, confirmPlain }

/// Logged sets always block (history would break — mirrors the server's FK
/// RESTRICT); split-day references are removable alongside the exercise.
ExerciseDeleteAction decideExerciseDelete({
  required int setCount,
  required int dayCount,
}) {
  if (setCount > 0) return ExerciseDeleteAction.blockedByHistory;
  if (dayCount > 0) return ExerciseDeleteAction.confirmWithDays;
  return ExerciseDeleteAction.confirmPlain;
}
```
and the repo methods (inside `ExerciseRepository`):
```dart
  /// Reference counts gating delete: logged sets + distinct split days.
  Future<({int setCount, int dayCount})> exerciseReferences(String id) async {
    final sets = await db.get(
        'SELECT COUNT(*) AS c FROM sets WHERE exercise_id = ?', [id]);
    final days = await db.get(
        'SELECT COUNT(DISTINCT day_template_id) AS c '
        'FROM day_template_items WHERE exercise_id = ?',
        [id]);
    return (
      setCount: (sets['c'] as num).toInt(),
      dayCount: (days['c'] as num).toInt(),
    );
  }

  /// Deletes an owned exercise; when [removeFromDays], clears its split-day
  /// slots first (same transaction). Caller must have run the decide gate.
  Future<void> deleteExercise(String id, {required bool removeFromDays}) async {
    await db.writeTransaction((tx) async {
      if (removeFromDays) {
        await tx.execute(
            'DELETE FROM day_template_items WHERE exercise_id = ?', [id]);
      }
      await tx.execute('DELETE FROM exercises WHERE id = ?', [id]);
    });
  }
```
(Check `db.get` vs `getOptional` usage style in this file and match.)

- [ ] **Step 4: Editor UI** (`exercise_editor.dart`, below the `PrimaryBtn`, replacing the `// NO delete button` comment — only when `_editId != null`):
```dart
              if (_editId != null) ...[
                const SizedBox(height: 10),
                _DeleteButton(tokens: tokens, onTap: _delete),
              ],
```
Reuse/adapt the `_DeleteButton` pattern from `day_editor.dart` (copy the class into this file if it's private there — match its style). The handler:
```dart
  Future<void> _delete() async {
    final id = _editId;
    if (id == null) return;
    final refs = await _repo.exerciseReferences(id);
    if (!mounted) return;

    switch (decideExerciseDelete(
        setCount: refs.setCount, dayCount: refs.dayCount)) {
      case ExerciseDeleteAction.blockedByHistory:
        await showWDialog<bool>(
          context,
          title: 'Can\'t delete',
          message:
              'This exercise is used in ${refs.setCount} logged set(s). '
              'Delete those sessions first.',
          actions: const [WDialogAction(label: 'OK', value: true)],
        );
        return;
      case ExerciseDeleteAction.confirmWithDays:
        final ok = await showWConfirm(
          context,
          title: 'Delete exercise?',
          message:
              'Also removes it from ${refs.dayCount} training day(s). '
              'This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: true);
      case ExerciseDeleteAction.confirmPlain:
        final ok = await showWConfirm(
          context,
          title: 'Delete exercise?',
          message: 'This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: false);
    }
    if (mounted) widget.onBack();
  }
```
Imports: `../widgets/w_dialog.dart` if not present. NOTE the switch falls through Dart 3 patterns — each case returns or completes; ensure `widget.onBack()` runs only after a successful delete (restructure with explicit `return`s if cleaner).

- [ ] **Step 5: Verify** — `make -C app analyze` clean; `make -C app test` (3 new tests green).

- [ ] **Step 6: Commit**
```bash
git add app/lib/data/exercise_repository.dart app/lib/ui/exercise_editor.dart app/test/data/exercise_delete_test.dart
git commit -m "feat(app): exercise delete with logged-set guard and split cleanup"
```

---

### Task 4: WStepper tap-to-type (TDD)

**Files:**
- Modify: `app/lib/widgets/stepper.dart`, `app/lib/session/set_row.dart`, `app/lib/ui/history_screen.dart`
- Test: `app/test/widgets/stepper_input_test.dart`

- [ ] **Step 1: Write the failing widget tests**

`app/test/widgets/stepper_input_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/stepper.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark, accents[0]),
        home: Scaffold(body: Center(child: SizedBox(width: 160, child: child))),
      );

  testWidgets('editable: tap value → type → commit fires onChanged',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 80,
      step: 2.5,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '92.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 92.5);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('92.5'), findsOneWidget);
  });

  testWidgets('editable: comma decimal and clamp below zero', (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12,5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 12.5);

    await tester.tap(find.text('12.5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '-4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 0.0);
  });

  testWidgets('editable: invalid input reverts without onChanged',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, isNull);
    expect(find.text('10.0'), findsOneWidget);
  });

  testWidgets('non-editable: tapping the value does nothing', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
```

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (`editable` param missing).

- [ ] **Step 3: Implement in `stepper.dart`.** Add `this.editable = false` to the constructor + `final bool editable;`. In State: `bool _editing = false;` + `TextEditingController? _editCtrl;` (+ FocusNode). Replace the value `Text` region: when `widget.editable`, wrap the existing AnimatedSwitcher value in a `GestureDetector(behavior: HitTestBehavior.opaque, onTap: _beginEdit)`; when `_editing`, render instead a compact `TextField`:
```dart
  void _beginEdit() {
    if (!widget.editable) return;
    _editCtrl = TextEditingController(text: widget.format(_internalValue));
    _editCtrl!.selection =
        TextSelection(baseOffset: 0, extentOffset: _editCtrl!.text.length);
    setState(() => _editing = true);
  }

  void _commitEdit() {
    final raw = _editCtrl?.text.trim().replaceAll(',', '.') ?? '';
    final parsed = double.tryParse(raw);
    setState(() {
      _editing = false;
      if (parsed != null) {
        final clamped = parsed < 0 ? 0.0 : _round2(parsed);
        _up = clamped > _internalValue;
        _internalValue = clamped;
        widget.onChanged(clamped);
      }
    });
    _editCtrl?.dispose();
    _editCtrl = null;
  }
```
TextField config: `keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false)`, `textAlign: TextAlign.center`, same mono style/size as the value Text, `autofocus: true`, `onSubmitted: (_) => _commitEdit()`, and commit on focus loss (`Focus(onFocusChange: (f) { if (!f && _editing) _commitEdit(); }, ...)` or a FocusNode listener). NOTE: the displayed text comes from `widget.format` (display units) but the COMMITTED value goes through `onChanged` in the same space as `_internalValue` (kg for weights) — for kg-mode this is identical; for LB display `format` converts kg→lb so parsing the typed text as the internal value would be WRONG. READ how `unit.fmtWt` works: it converts kg→display. Therefore the edit field must operate in DISPLAY space and convert back: add an optional `double Function(double display)? parseDisplay` param — when provided, `_commitEdit` maps the typed display value back (callers pass `(v) => UnitService.toKg(v, unit.unit)`-equivalent); when null, typed value is used directly (the tests above use identity formats so they pass either way). Check `UnitService` for the existing `toKg/fromKg` statics and wire the two weight call sites with the correct converter; pre-fill the field from `widget.format(_internalValue)` minus any unit suffix (fmtWt returns bare numbers — verify).
Also: dispose `_editCtrl` in `dispose()`; `_editing` state must not break the targets_tab usage (editable defaults false — untouched).

- [ ] **Step 4: Enable at the two weight call sites.**
- `set_row.dart` weight WStepper (:213-224): add `editable: true,` + `parseDisplay: (v) => UnitService.toKg(v, unit.unit),` (match the real converter API; import if needed).
- `history_screen.dart` `_SetEditorSheet` weight WStepper (:1156-1165): same two params with its `units` service.
- Reps/RIR steppers untouched.

- [ ] **Step 5: Verify** — `make -C app analyze` clean; `make -C app test` (4 new green; `set_row_overflow_test` and stepper-dependent tests still green).

- [ ] **Step 6: Commit**
```bash
git add app/lib/widgets/stepper.dart app/lib/session/set_row.dart app/lib/ui/history_screen.dart app/test/widgets/stepper_input_test.dart
git commit -m "feat(app): tap-to-type weight input on steppers"
```

---

### Task 5: Small visual fixes

**Files:**
- Modify: `app/lib/ui/bodyweight_view.dart` (:66-67), `app/lib/widgets/w_tab_bar.dart` (:101)

- [ ] **Step 1:** bodyweight_view ListView padding →
```dart
      padding: EdgeInsets.fromLTRB(
          16, 8 + MediaQuery.paddingOf(context).top, 16, 96),
```
(drop the `const`).

- [ ] **Step 2:** w_tab_bar FAB straddle: `Offset(0, -22)` → `Offset(0, -14)`. Eyeball note: the mini-bar (`app_shell.dart`, `bottom: 105`) gains clearance from this (FAB top drops 8px) — no change needed there.

- [ ] **Step 3: Verify + commit**
```bash
make -C app analyze && make -C app test
git add app/lib/ui/bodyweight_view.dart app/lib/widgets/w_tab_bar.dart
git commit -m "fix(app): bodyweight status-bar inset, lower FAB straddle"
```

---

### Task 6: Verify + ship v0.9.0 (INLINE — run by the orchestrating session, not a subagent)

- [ ] `make -C app analyze` + `make -C app test` (~208: 196 +6 absorb −1 dedup +3 delete +4 stepper) + `make -C app build-apk-release` → green.
- [ ] Final adversarial review subagent over `git diff main...ownership-overhaul`, focused on: absorb correctness (column completeness vs schema, op ordering day-before-items, deterministic-id collision domains exercise-vs-day-vs-item, idempotency incl. crash-mid-tx and cross-device, PowerSync upload semantics of the INSERT/UPDATE ops — do raw tx.execute writes enter the upload queue?— verify against how other writes work), filter completeness (any remaining query surfacing is_template=1: grep), clone-path removal completeness, delete-guard SQL + dialog flows, stepper display-vs-internal-space conversion correctness in LB mode, regressions in targets_tab/onboarding seeds.
- [ ] Merge `--no-ff` → main, push, tag `v0.9.0` → CI publishes `reps-v0.9.0.apk`. User on-device: first boot migrates (split becomes 4 owned days — edit saves in place, delete button present; history/PRs intact; rotation works), exercise edit-in-place + delete (blocked/with-days/plain), weight typing in session + history (kg AND lb mode), bodyweight inset, FAB position.

### Out of scope
Uniform steps; reps/RIR typing; server-side template deletion; sync-rules changes.
