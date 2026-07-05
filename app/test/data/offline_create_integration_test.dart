import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/day_template_repository.dart';
import 'package:workout_tracker/data/exercise_repository.dart';
import 'package:workout_tracker/data/is_template_backfill.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/template_absorb.dart';
import 'package:workout_tracker/sync/schema.dart';

/// Integration tests against a REAL PowerSync database (not SQL-string
/// assertions). These exist because the offline-create fix once shipped on
/// green string-level tests and still broke production: the state below —
/// legacy `is_template = NULL` rows with `base_weight_kg = ''`, exactly what a
/// sync-broken device accumulates — is the shape that detonated. Every
/// scenario here runs the real writers, filters, backfill, and absorb.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-itest');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Inserts an exercise the way PRE-FIX builds did: no is_template column
  /// (stored NULL), no created_at, and '' for a missing base weight.
  Future<void> insertLegacyNullRow(String id, String name) => db.execute(
        'INSERT INTO exercises '
        '(id, slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, '${name.toLowerCase()}-$id', name, 'chest', '', 0, '', '2.50'],
      );

  group('offline create (real DB)', () {
    test('createExercise with no base weight is immediately visible', () async {
      final repo = ExerciseRepository(db);
      final id = await repo.createExercise(ExerciseDraft(
        name: 'Pectoral machine',
        muscleGroup: 'chest',
        compound: false,
        baseWeightKg: null, // stored as '' — the historical crash trigger
        plateStepKg: 2.5,
      ));

      final catalog = await repo.watchCatalog().first;
      expect(catalog.map((e) => e.id), contains(id));
      expect(catalog.single.baseWeightKg, isNull); // '' maps safely
      final row = await db.get(
          'SELECT is_template FROM exercises WHERE id = ?', [id]);
      expect(row['is_template'], 0); // written locally, not left NULL
    });

    test('saveDay (new day + slot) is immediately visible', () async {
      final exRepo = ExerciseRepository(db);
      final exId = await exRepo.createExercise(ExerciseDraft(
        name: 'Row',
        muscleGroup: 'back',
        compound: true,
        plateStepKg: 2.5,
      ));

      final dayRepo = DayTemplateRepository(db);
      await dayRepo.saveDay(
        draft: DayDraft(
          name: 'Pull Day',
          focus: 'Back',
          weekday: 1,
          slots: [SlotDraft(exerciseId: exId, workSets: 3)],
        ),
      );

      final days = await dayRepo.watchDays().first;
      expect(days, hasLength(1));
      expect(days.single.name, 'Pull Day');
      expect(days.single.slots, hasLength(1));
      final row = await db.get(
          'SELECT is_template FROM day_templates WHERE id = ?',
          [days.single.id]);
      expect(row['is_template'], 0);
    });
  });

  group('legacy NULL rows (pre-fix device state)', () {
    test('visible via null-safe filter even BEFORE the backfill runs', () async {
      await insertLegacyNullRow('legacy-1', 'Pectoral machine');

      // The whole point of IS NOT 1: a NULL row shows up, and its '' base
      // weight must not blow up the mapping of the entire catalog.
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      expect(catalog, hasLength(1));
      expect(catalog.single.name, 'Pectoral machine');
      expect(catalog.single.baseWeightKg, isNull);
    });

    test('backfill normalizes NULL → 0 and is idempotent', () async {
      await insertLegacyNullRow('legacy-1', 'Pectoral machine');
      await db.execute(
          'INSERT INTO day_templates (id, name, position) VALUES (?, ?, ?)',
          ['legacy-day', 'Push Day', 1]); // is_template NULL

      await backfillIsTemplate(db);
      await backfillIsTemplate(db); // second run must be a no-op

      final ex = await db.get(
          'SELECT is_template FROM exercises WHERE id = ?', ['legacy-1']);
      final day = await db.get(
          'SELECT is_template FROM day_templates WHERE id = ?', ['legacy-day']);
      expect(ex['is_template'], 0);
      expect(day['is_template'], 0);
    });
  });

  group('backfill × absorb ordering', () {
    const userId = 'user-1';
    const templateId = 'tmpl-pec';

    Future<void> seedServerTemplate() => db.execute(
          'INSERT INTO exercises '
          '(id, slug, name, muscle_group, equip, compound, base_weight_kg, '
          'plate_step_kg, is_template) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
          [templateId, 'pectoral-machine', 'Pectoral machine', 'chest', '', 0, '40.00', '2.50'],
        );

    test('backfill BEFORE absorb → no duplicate owned copy', () async {
      await seedServerTemplate();
      await insertLegacyNullRow('legacy-1', 'Pectoral machine');

      await backfillIsTemplate(db);
      await absorbTemplates(db, userId);

      final owned = await db.getAll(
          "SELECT id FROM exercises WHERE is_template IS NOT 1 AND name = 'Pectoral machine'");
      expect(owned, hasLength(1),
          reason: 'absorb must de-dup against the (backfilled) owned row');
      expect(owned.single['id'], 'legacy-1');
      expect(owned.single['id'], isNot(absorbCopyId(userId, templateId)));
    });

    test('control: skipping the backfill WOULD duplicate — proves ordering is load-bearing',
        () async {
      await seedServerTemplate();
      await insertLegacyNullRow('legacy-1', 'Pectoral machine');

      await absorbTemplates(db, userId); // no backfill first

      final owned = await db.getAll(
          "SELECT id FROM exercises WHERE is_template IS NOT 1 AND name = 'Pectoral machine'");
      expect(owned, hasLength(2),
          reason: 'without the backfill, absorb cannot see the NULL row and '
              'creates a second owned copy — the ordering in main() prevents this');
    });
  });
}
