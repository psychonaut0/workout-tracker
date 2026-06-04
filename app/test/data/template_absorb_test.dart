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
        templateDays: [tmplDay('day-t')],
        templateExercises: const [],
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
