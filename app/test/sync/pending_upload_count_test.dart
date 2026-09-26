import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:workout_tracker/sync/db.dart';
import 'package:workout_tracker/sync/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase database;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reps-pending');
    database = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test('counts local changes still waiting to upload', () async {
    expect(await pendingUploadCount(database), 0);
    await database.execute(
      'INSERT INTO bodyweight_logs (id, date, weight_kg) VALUES (?, ?, ?)',
      ['b1', '2026-09-20', '80'],
    );
    await database.execute(
      'INSERT INTO bodyweight_logs (id, date, weight_kg) VALUES (?, ?, ?)',
      ['b2', '2026-09-21', '79.5'],
    );
    expect(await pendingUploadCount(database), 2);
  });
}
