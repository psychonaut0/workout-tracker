import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/exercise_repository.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/resume.dart';
import 'package:workout_tracker/sync/schema.dart';

/// Resume-a-finished-workout contracts against a REAL PowerSync database:
/// the replace-in-place write, the CRUD ops it uploads, and the baseline
/// lookups that must ignore the resumed session's own rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-resume');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedDay(String id) => db.execute(
      'INSERT INTO day_templates (id, name, position, is_template) VALUES (?, ?, 0, 0)',
      [id, 'Upper A']);

  Future<void> seedSession(String id, String date, {String? day}) => db.execute(
      'INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, date, day, 'Upper A', 40]);

  Future<void> seedSet(String id, String sessionId, String exerciseId, int n,
          String weight,
          {bool top = false}) =>
      db.execute(
          'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, '
          'is_warmup, is_top_set, is_pr) VALUES (?, ?, ?, ?, ?, 5, 1, 0, ?, 0)',
          [id, sessionId, exerciseId, n, weight, top ? 1 : 0]);

  Future<void> seedExercise(String id, String name) => db.execute(
      'INSERT INTO exercises (id, slug, name, muscle_group, equip, compound, '
      'base_weight_kg, plate_step_kg, is_template) VALUES (?, ?, ?, ?, ?, 1, ?, ?, 0)',
      [id, '$name-$id', name, 'chest', 'barbell', '60.00', '2.50']);

  /// Completes every queued upload transaction so the next one is ours.
  Future<void> drainCrud() async {
    while (true) {
      final t = await db.getNextCrudTransaction();
      if (t == null) return;
      await t.complete();
    }
  }

  Future<List<CrudEntry>> nextCrud() async {
    final t = await db.getNextCrudTransaction();
    if (t == null) return [];
    await t.complete();
    return t.crud;
  }

  SessionWrite write(String id, {String? day, List<SetWrite>? sets}) => SessionWrite(
        id: id,
        dateIso: '2026-09-23',
        dayTemplateId: day,
        splitLabel: 'Upper A',
        durationMin: 55,
        sets: sets ??
            const [
              SetWrite(id: 'a', exerciseId: 'bench', setNumber: 1, weightKg: '102.50', reps: 5, rir: 1, isWarmup: false, isTopSet: true),
              SetWrite(id: 'b', exerciseId: 'bench', setNumber: 2, weightKg: '100.00', reps: 5, rir: 1, isWarmup: false),
            ],
      );

  group('writer (real DB)', () {
    test('persistSession stores NULL for a training day that no longer exists', () async {
      await db.writeTransaction(
          (tx) => persistSession(PowerSyncTxExecutor(tx), write('S', day: 'gone')));
      final row = await db.get('SELECT day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['day_template_id'], isNull);
    });

    test('persistSession keeps an existing training day', () async {
      await seedDay('d1');
      await db.writeTransaction(
          (tx) => persistSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));
      final row = await db.get('SELECT day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['day_template_id'], 'd1');
    });

    test('replaceSession keeps the row and uploads a PATCH, set DELETEs, then set PUTs', () async {
      await seedDay('d1');
      await seedSession('S', '2026-09-23', day: 'd1');
      await seedSet('a', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('old', 'S', 'bench', 2, '95.00');
      await drainCrud();

      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));

      final ops = await nextCrud();
      expect(ops.map((e) => '${e.op.name}:${e.table}').toList(), [
        'patch:sessions',
        'delete:sets',
        'delete:sets',
        'put:sets',
        'put:sets',
      ]);
      expect(ops.first.id, 'S');
      expect(ops.first.opData!.containsKey('day_template_id'), isFalse);
      expect(ops.first.opData!['duration_min'], 55);

      final sessions = await db.getAll('SELECT id, date FROM sessions');
      expect(sessions.single['id'], 'S');
      expect(sessions.single['date'], '2026-09-23');
      final sets = await db.getAll('SELECT id, weight_kg FROM sets ORDER BY id');
      expect(sets.map((r) => r['id']), ['a', 'b']);
      expect(sets.first['weight_kg'], '102.50');
    });

    test('replaceSession survives a training day deleted since the first finish', () async {
      await seedDay('d1');
      await seedSession('S', '2026-09-23', day: 'd1');
      await seedSet('a', 'S', 'bench', 1, '100.00', top: true);
      await db.execute('DELETE FROM day_templates WHERE id = ?', ['d1']);
      await drainCrud();

      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));

      final ops = await nextCrud();
      expect(ops.where((e) => e.table == 'sessions').map((e) => e.op), [UpdateType.patch]);
      expect(ops.first.opData!.containsKey('day_template_id'), isFalse);
      expect((await db.getAll('SELECT id FROM sessions')).single['id'], 'S');
    });

    test('replaceSession re-creates a vanished session row, with a deleted day as NULL', () async {
      await drainCrud();
      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'gone')));

      final ops = await nextCrud();
      expect(ops.first.op, UpdateType.put);
      expect(ops.first.table, 'sessions');
      final row = await db.get('SELECT date, day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['date'], '2026-09-23');
      expect(row['day_template_id'], isNull);
      expect((await db.getAll('SELECT id FROM sets')).length, 2);
    });
  });

  group('repository (real DB)', () {
    test('bestTopSet and lastTopSet can exclude one session', () async {
      await seedSession('Y', '2026-09-22');
      await seedSet('y1', 'Y', 'bench', 1, '90.00', top: true);
      await seedSession('T', '2026-09-23');
      await seedSet('t1', 'T', 'bench', 1, '100.00', top: true);
      final repo = SessionRepository(db);

      expect(await repo.bestTopSet('bench'), 100);
      expect(await repo.bestTopSet('bench', excludeSessionId: 'T'), 90);
      expect((await repo.lastTopSet('bench'))!.date, '2026-09-23');
      final last = (await repo.lastTopSet('bench', excludeSessionId: 'T'))!;
      expect(last.date, '2026-09-22');
      expect(last.weight, 90);
      final before = (await repo.lastTopSet('bench',
          beforeDate: '2026-09-24', excludeSessionId: 'T'))!;
      expect(before.date, '2026-09-22');
      expect(await repo.bestTopSet('bench', excludeSessionId: 'Y'), 100);
    });

    test('sessionById returns the row, or null once it is gone', () async {
      await seedSession('S', '2026-09-23', day: 'd1');
      final repo = SessionRepository(db);
      final row = (await repo.sessionById('S'))!;
      expect(row.date, '2026-09-23');
      expect(row.durationMin, 40);
      expect(await repo.sessionById('nope'), isNull);
    });
  });

  group('addBlock baseline (real DB)', () {
    Future<ActiveSessionController> controllerWithBench({String? sessionId}) async {
      await seedExercise('bench', 'Bench');
      await seedSession('Y', '2026-09-22');
      await seedSet('y1', 'Y', 'bench', 1, '90.00', top: true);
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      final c = ActiveSessionController()
        ..seedForTest(SessionDraft(
          templateId: null, name: 'Upper A', focus: '',
          startedAt: DateTime(2026, 9, 23, 9), blocks: [],
          sessionId: sessionId, sessionDate: sessionId == null ? null : '2026-09-23',
        ));
      final bench = (await ExerciseRepository(db).byId('bench'))!;
      await c.addBlock(bench, sessionRepo: SessionRepository(db));
      return c;
    }

    test('an exercise added to a resumed workout is baselined without its own rows', () async {
      final c = await controllerWithBench(sessionId: 'S');
      expect(c.draft.blocks.single.bestKg, 90);
      expect(c.draft.blocks.single.lastTop!.date, '2026-09-22');
    });

    test('a fresh workout still sees every logged session', () async {
      final c = await controllerWithBench();
      expect(c.draft.blocks.single.bestKg, 100);
      expect(c.draft.blocks.single.lastTop!.date, '2026-09-23');
    });
  });

  group('restoreFinishedDraft (real DB)', () {
    Exercise bench() => const Exercise(
          id: 'bench', name: 'Bench', slug: 'bench', muscleGroup: 'chest',
          compound: true, plateStepKg: 2.5, isTemplate: false,
        );

    BlockState benchBlock() => BlockState(
          exercise: bench(),
          resolved: ResolvedSlot(
            exercise: bench(), workSets: 3, warmupSets: 0,
            repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2,
          ),
          warmupSets: [],
          workingSets: [
            SetState(id: 's1', weightKg: 100, reps: 5, rir: 1, isWarmup: false, done: true),
            SetState(id: 's3', weightKg: 95, reps: 5, rir: 1, isWarmup: false, done: false),
          ],
          expanded: true,
          bestKg: 90,
        );

    FinishedSession finished(List<BlockState> blocks) => FinishedSession(
          sessionId: 'S',
          sessionDate: '2026-09-23',
          finishedAt: DateTime(2026, 9, 23, 10, 0),
          elapsedSeconds: 2400,
          draft: SessionDraft(
            templateId: null, name: 'Upper A', focus: '',
            startedAt: DateTime(2026, 9, 23, 9, 20), blocks: blocks,
          ),
        );

    test('restores the snapshot, baselines a History-added exercise without this session, continues the clock', () async {
      await seedExercise('bench', 'Bench');
      await seedExercise('curl', 'Curl');
      await seedSession('Y', '2026-09-22');
      await seedSet('y2', 'Y', 'curl', 1, '20.00', top: true);
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('x1', 'S', 'curl', 1, '22.50', top: true); // added in History
      final repo = SessionRepository(db);
      final now = DateTime(2026, 9, 23, 10, 10);

      final d = await restoreFinishedDraft(
        finished([benchBlock()]),
        await repo.setsForSession('S'),
        durationMin: 40,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: now,
      );

      expect(d.sessionId, 'S');
      expect(d.sessionDate, '2026-09-23');
      expect(d.startedAt, now.subtract(const Duration(seconds: 2400)));
      expect(d.blocks.map((b) => b.exercise.id), ['bench', 'curl']);
      expect(d.blocks[0].workingSets.map((s) => s.id), ['s1', 's3']);
      expect(d.blocks[0].bestKg, 90); // the snapshot's pre-workout baseline
      final curl = d.blocks[1];
      expect(curl.exercise.name, 'Curl');
      expect(curl.workingSets.single.id, 'x1');
      expect(curl.workingSets.single.done, isTrue);
      expect(curl.bestKg, 20); // not this session's own 22.5
      expect(curl.lastTop!.date, '2026-09-22');
    });

    test('drops a planned-only block whose exercise was deleted; keeps logged sets of a deleted exercise', () async {
      await seedExercise('bench', 'Bench');
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('z1', 'S', 'gone2', 1, '30.00', top: true);
      final ghost = Exercise(
        id: 'gone1', name: 'Ghost', slug: 'ghost', muscleGroup: 'chest',
        compound: false, plateStepKg: 2.5, isTemplate: false,
      );
      final planned = BlockState(
        exercise: ghost,
        resolved: ResolvedSlot(exercise: ghost, workSets: 1, warmupSets: 0,
            repLow: 8, repHigh: 12, rirLow: 1, rirHigh: 2),
        warmupSets: [],
        workingSets: [SetState(id: 'g1', weightKg: 10, reps: 10, rir: 1, isWarmup: false, done: false)],
        expanded: true,
      );
      final repo = SessionRepository(db);
      final d = await restoreFinishedDraft(
        finished([benchBlock(), planned]),
        await repo.setsForSession('S'),
        durationMin: 40,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: DateTime(2026, 9, 23, 10, 10),
      );
      expect(d.blocks.map((b) => b.exercise.id), ['bench', 'gone2']);
      expect(d.blocks[1].exercise.name, 'gone2'); // placeholder, rows kept
      expect(d.blocks[1].workingSets.single.id, 'z1');
    });

    test('a stale snapshot cannot roll the clock back', () async {
      await seedExercise('bench', 'Bench');
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      final repo = SessionRepository(db);
      final now = DateTime(2026, 9, 23, 10, 10);
      final d = await restoreFinishedDraft(
        finished([benchBlock()]),
        await repo.setsForSession('S'),
        durationMin: 55,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: now,
      );
      expect(d.startedAt, now.subtract(const Duration(minutes: 55)));
    });
  });
}
