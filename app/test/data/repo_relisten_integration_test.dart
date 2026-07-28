import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/day_template_repository.dart';
import 'package:workout_tracker/data/exercise_repository.dart';
import 'package:workout_tracker/sync/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-relisten');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('watchCatalog can be listened to twice', () async {
    await db.execute(
      "INSERT INTO exercises (id, name, slug, muscle_group, is_template) "
      "VALUES ('e1', 'Squat', 'squat', 'quads', 0)",
    );
    final stream = ExerciseRepository(db).watchCatalog();

    final first = await stream.first; // listens, then cancels
    final second = await stream.first; // re-listens — this threw before

    expect(first.length, 1);
    expect(second.length, 1);
  });

  test('watchDays can be listened to twice', () async {
    final stream = DayTemplateRepository(db).watchDays();
    await stream.first;
    await stream.first;
  });
}
