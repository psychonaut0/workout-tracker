import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/db.dart';
import 'package:workout_tracker/sync/schema.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';
import '../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-progress');
    database = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await database.initialize();
    dbForTests = database;
  });

  tearDown(() async {
    dbForTests = null;
    await database.close();
    await dir.delete(recursive: true);
  });

  testWidgets('a non-null initialTarget does not crash on the first frame',
      (tester) async {
    // Reproduces tapping a Recent-PR row on Home: the screen mounts with a
    // target already set, before the catalog stream has emitted anything.
    await tester.pumpWidget(wrapL10n(
      ChangeNotifierProvider<UnitService>(
        create: (_) => UnitService(),
        child: const ProgressScreen(initialTarget: 'some-exercise-id'),
      ),
    ));

    // The very first frame is the one that threw "Bad state: No element".
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a non-null initialTarget against a genuinely empty catalog shows the '
      'recoverable empty state, not a dead blank screen', (tester) async {
    // No exercises are ever inserted, so the catalog stream settles on an
    // empty (but non-null-data) list — distinct from "hasn't emitted yet".
    await tester.pumpWidget(wrapL10n(
      ChangeNotifierProvider<UnitService>(
        create: (_) => UnitService(),
        child: const ProgressScreen(initialTarget: 'some-exercise-id'),
      ),
    ));
    expect(tester.takeException(), isNull);

    // The catalog stream's first (real, isolate-backed) emission needs real
    // async progress to land — pumpAndSettle only advances fake time, so
    // poll with real ticks until the empty state's content actually appears.
    await pumpUntilFound(tester, find.text('No exercises found'));
    expect(tester.takeException(), isNull);

    // _EmptyState's content (progress_screen.dart) — the picker entry point
    // that lets the user escape the empty state, rather than a blank screen.
    expect(find.text('No exercises found'), findsOneWidget);
    expect(find.text('Choose exercise'), findsOneWidget);
  });
}
