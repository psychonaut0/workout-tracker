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

  Map<String, Object?> setRow(String id, String exId) => {
        'id': id,
        'session_id': 'sess-1',
        'exercise_id': exId,
        'user_id': null,
        'set_number': 1,
        'weight_kg': '80',
        'reps': 8,
        'rir': 1,
        'is_warmup': 0,
        'is_top_set': 1,
        'is_pr': 0,
        'created_at': '2026-01-02T00:00:00Z',
        'updated_at': null,
      };

  // Owned day_template_item that references a template exercise (B1b).
  Map<String, Object?> ownedItem(String id, String dayId, String exId) => {
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
        'is_template': 0,
        'created_by': user,
        'created_at': '2026-01-02T00:00:00Z',
      };

  group('absorbCopyId', () {
    test('is deterministic and user/template-scoped', () {
      final a = absorbCopyId(user, 't1');
      expect(a, absorbCopyId(user, 't1'));
      expect(a, isNot(absorbCopyId(user, 't2')));
      expect(a, isNot(absorbCopyId('user-2', 't1')));
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
        affectedSets: [setRow('set-1', 'ex-t')],
        affectedItems: [ownedItem('owned-item-1', 'day-owned', 'ex-t')],
        affectedSessionDayIds: const {},
        existingIds: const {},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
        nowIso: '2026-06-04T10:00:00Z',
      );
      final copyId = absorbCopyId(user, 'ex-t');

      final insert = ops.firstWhere((o) => o.sql.startsWith('INSERT INTO exercises'));
      expect(insert.args, contains(copyId));
      expect(insert.args, contains(user)); // created_by
      expect(insert.args, contains(0)); // is_template
      expect(insert.args, contains('Bench Press'));

      // Set re-point is DELETE + INSERT (same id, new exercise_id) — NOT UPDATE.
      expect(ops.any((o) => o.sql.startsWith('UPDATE sets')), isFalse);
      final setDelIdx =
          ops.indexWhere((o) => o.sql == 'DELETE FROM sets WHERE id = ?');
      expect(setDelIdx, greaterThanOrEqualTo(0));
      expect(ops[setDelIdx].args, ['set-1']);
      final setInsIdx = ops.indexWhere(
          (o) => o.sql.startsWith('INSERT INTO sets'), setDelIdx);
      expect(setInsIdx, greaterThan(setDelIdx));
      final setIns = ops[setInsIdx];
      expect(setIns.args, contains('set-1')); // same id preserved
      expect(setIns.args, contains(copyId)); // new exercise_id
      expect(setIns.args, contains('sess-1'));
      expect(setIns.args, contains('80'));
      expect(setIns.args, contains(8));

      // Owned item re-point is also DELETE + INSERT (B1b — PATCH drops exercise_id).
      expect(ops.any((o) => o.sql.startsWith('UPDATE day_template_items')),
          isFalse);
      final itemDelIdx = ops.indexWhere(
          (o) => o.sql == 'DELETE FROM day_template_items WHERE id = ?');
      expect(itemDelIdx, greaterThanOrEqualTo(0));
      expect(ops[itemDelIdx].args, ['owned-item-1']);
      final itemInsIdx = ops.indexWhere(
          (o) => o.sql.startsWith('INSERT INTO day_template_items'), itemDelIdx);
      expect(itemInsIdx, greaterThan(itemDelIdx));
      final itemIns = ops[itemInsIdx];
      expect(itemIns.args, contains('owned-item-1')); // same id preserved
      expect(itemIns.args, contains(copyId)); // new exercise_id
      expect(itemIns.args, contains('day-owned')); // parent unchanged
    });

    test('copies a day with its items, re-pointing exercise ids, and rewrites sessions',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: [tmplDay('day-t')],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-t')],
        affectedSets: const [],
        affectedItems: const [],
        affectedSessionDayIds: {'day-t'},
        existingIds: const {},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
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
        affectedSets: const [],
        affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: {absorbCopyId(user, 'ex-t'), absorbCopyId(user, 'day-t')},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
        nowIso: '2026-06-04T10:00:00Z',
      );
      expect(ops, isEmpty);
    });

    test('skips templates recorded in alreadyAbsorbed even when no copy exists',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: [tmplDay('day-t')],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-t')],
        affectedSets: const [],
        affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {},
        alreadyAbsorbed: {'ex-t', 'day-t'},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
        nowIso: '2026-06-04T10:00:00Z',
      );
      expect(ops, isEmpty);
    });

    test('re-points late-synced sets even when the exercise copy already exists',
        () {
      // The exercise was absorbed on a prior boot (copy exists), but a set that
      // still references the template id only synced down now → must re-point.
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t')],
        templateDays: const [],
        templateItems: const [],
        affectedSets: [setRow('set-late', 'ex-t')],
        affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: {absorbCopyId(user, 'ex-t')},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
        nowIso: 'x',
      );
      // No INSERT exercises (copy exists) but the set is still re-pointed.
      expect(ops.any((o) => o.sql.startsWith('INSERT INTO exercises')), isFalse);
      expect(ops.any((o) => o.sql == 'DELETE FROM sets WHERE id = ?'), isTrue);
      final ins = ops.firstWhere((o) => o.sql.startsWith('INSERT INTO sets'));
      expect(ins.args, contains(absorbCopyId(user, 'ex-t')));
    });

    test('no templates → no ops', () {
      expect(
        absorbOps(
          userId: user,
          templateExercises: const [],
          templateDays: const [],
          templateItems: const [],
          affectedSets: const [],
          affectedItems: const [],
          affectedSessionDayIds: const {},
          existingIds: const {},
          alreadyAbsorbed: const {},
          ownedExerciseByKey: const {},
          ownedDayByName: const {},
          nowIso: 'x',
        ),
        isEmpty,
      );
    });

    test('item referencing a non-template exercise keeps its id', () {
      final ops = absorbOps(
        userId: user,
        templateDays: [tmplDay('day-t')],
        templateExercises: const [],
        templateItems: [tmplItem('item-t', 'day-t', 'ex-owned')],
        affectedSets: const [],
        affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: const {},
        nowIso: 'x',
      );
      final itemInsert = ops
          .firstWhere((o) => o.sql.startsWith('INSERT INTO day_template_items'));
      expect(itemInsert.args, contains('ex-owned'));
    });
  });

  group('name-dedup', () {
    test('template exercise with an owned name+muscle twin emits no insert and re-points to it',
        () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t', name: 'Bench Press')],
        templateDays: const [],
        templateItems: const [],
        affectedSets: [
          {
            'id': 'set-1', 'session_id': 's1', 'exercise_id': 'ex-t',
            'set_number': 1, 'weight_kg': '80', 'reps': 8, 'rir': 1,
            'is_warmup': 0, 'is_top_set': 1, 'is_pr': 0,
            'created_at': 'x', 'updated_at': null,
          },
        ],
        affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {},
        alreadyAbsorbed: const {},
        ownedExerciseByKey: {'bench press|chest': 'owned-ex'},
        ownedDayByName: const {},
        nowIso: 'x',
      );
      expect(ops.where((o) => o.sql.startsWith('INSERT INTO exercises')), isEmpty);
      final ins = ops.firstWhere((o) => o.sql.startsWith('INSERT INTO sets'));
      expect(ins.args, contains('owned-ex'));
      expect(ins.args, contains('set-1'));
    });

    test('case-insensitive name match', () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t', name: 'BENCH press')],
        templateDays: const [], templateItems: const [],
        affectedSets: const [], affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {}, alreadyAbsorbed: const {},
        ownedExerciseByKey: {'bench press|chest': 'owned-ex'},
        ownedDayByName: const {}, nowIso: 'x',
      );
      expect(ops.where((o) => o.sql.startsWith('INSERT INTO exercises')), isEmpty);
    });

    test('different muscle group does NOT merge (creates a copy)', () {
      final ops = absorbOps(
        userId: user,
        templateExercises: [tmplExercise('ex-t', name: 'Row')],
        templateDays: const [], templateItems: const [],
        affectedSets: const [], affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {}, alreadyAbsorbed: const {},
        ownedExerciseByKey: {'row|back': 'owned-back-row'},
        ownedDayByName: const {}, nowIso: 'x',
      );
      expect(ops.where((o) => o.sql.startsWith('INSERT INTO exercises')),
          isNotEmpty);
    });

    test('template day with an owned name twin emits no insert', () {
      final ops = absorbOps(
        userId: user,
        templateExercises: const [],
        templateDays: [tmplDay('day-t', name: 'Upper A')],
        templateItems: const [],
        affectedSets: const [], affectedItems: const [],
        affectedSessionDayIds: const {},
        existingIds: const {}, alreadyAbsorbed: const {},
        ownedExerciseByKey: const {},
        ownedDayByName: {'upper a': 'owned-day'},
        nowIso: 'x',
      );
      expect(ops.where((o) => o.sql.startsWith('INSERT INTO day_templates')),
          isEmpty);
    });
  });
}
