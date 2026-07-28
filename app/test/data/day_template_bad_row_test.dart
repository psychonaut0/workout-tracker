// Pins the same contract that protects Home's day-rotation stream, but at the
// repository/stream boundary instead of mounting the screen: a widget test
// that mounts TodayScreen over a real PowerSync database leaves pending
// watch-throttle timers behind and hangs the test binding, so it can't be
// used to verify this. Testing directly against DayTemplateRepository gives
// the same coverage — a NULL exercise_id in day_template_items really does
// throw on the stream, and a listener that supplies onError really does
// receive it — without mounting anything.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/day_template_repository.dart';
import 'package:workout_tracker/sync/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-day-template-bad-row');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('watchDays throws on a day_template_items row with a NULL exercise_id',
      () async {
    await db.execute(
      "INSERT INTO day_templates (id, name, is_template) "
      "VALUES ('d1', 'Lower A', 0)",
    );
    await db.execute(
      "INSERT INTO day_template_items (id, day_template_id, exercise_id, position) "
      "VALUES ('i1', 'd1', NULL, 0)",
    );

    await expectLater(
      DayTemplateRepository(db).watchDays().first,
      throwsA(isA<TypeError>()),
    );
  });

  test('a listener with onError receives the error instead of it escaping',
      () async {
    await db.execute(
      "INSERT INTO day_templates (id, name, is_template) "
      "VALUES ('d1', 'Lower A', 0)",
    );
    await db.execute(
      "INSERT INTO day_template_items (id, day_template_id, exercise_id, position) "
      "VALUES ('i1', 'd1', NULL, 0)",
    );

    final completer = Completer<Object>();
    final sub = DayTemplateRepository(db).watchDays().listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.complete(e);
      },
    );
    final err = await completer.future;
    expect(err, isA<TypeError>());
    await sub.cancel();
  });
}
