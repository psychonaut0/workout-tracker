import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/stats_repository.dart';
import 'package:workout_tracker/sync/schema.dart';

/// [StatsRepository.lastTrainedExerciseId] against a REAL PowerSync database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;
  late StatsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-stats');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
    repo = StatsRepository(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedSession(String id, String date) => db.execute(
      'INSERT INTO sessions (id, date, split_label, duration_min) VALUES (?, ?, ?, ?)',
      [id, date, 'Upper A', 40]);

  Future<void> seedSet(String id, String sessionId, String exerciseId, int n,
          {bool warmup = false}) =>
      db.execute(
          'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, '
          'is_warmup, is_top_set, is_pr) VALUES (?, ?, ?, ?, ?, 5, 1, ?, 0, 0)',
          [id, sessionId, exerciseId, n, '50.00', warmup ? 1 : 0]);

  test('no history: returns null', () async {
    expect(await repo.lastTrainedExerciseId(), isNull);
  });

  test('returns the exercise of the most recent working set', () async {
    await seedSession('s1', '2026-09-01');
    await seedSession('s2', '2026-09-10');
    await seedSet('a1', 's1', 'squat', 1);
    await seedSet('b1', 's2', 'bench', 1);
    expect(await repo.lastTrainedExerciseId(), 'bench');
  });

  test('warm-up-only most recent session is skipped in favour of an earlier working set',
      () async {
    await seedSession('s1', '2026-09-01');
    await seedSession('s2', '2026-09-10');
    await seedSet('a1', 's1', 'squat', 1);
    await seedSet('b1', 's2', 'bench', 1, warmup: true);
    expect(await repo.lastTrainedExerciseId(), 'squat');
  });

  test('ties within the same session break on the highest set number', () async {
    await seedSession('s1', '2026-09-01');
    await seedSet('a1', 's1', 'squat', 1);
    await seedSet('a2', 's1', 'bench', 2);
    expect(await repo.lastTrainedExerciseId(), 'bench');
  });
}
