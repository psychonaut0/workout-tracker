import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/db.dart';
import 'package:workout_tracker/sync/schema.dart';
import 'package:workout_tracker/ui/add_weight_sheet.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';
import '../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-add-weight');
    database = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await database.initialize();
    dbForTests = database;
  });

  tearDown(() async {
    dbForTests = null;
    await database.close();
    await dir.delete(recursive: true);
  });

  Widget host() => wrapL10n(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAddWeightSheet(context),
            child: const Text('open'),
          ),
        ),
      );

  Widget wrapped() => ChangeNotifierProvider<UnitService>(
        create: (_) => UnitService(),
        child: host(),
      );

  testWidgets('tapping the number opens a field seeded with the current value',
      (tester) async {
    await tester.pumpWidget(wrapped());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Wait for the last-entry seed query (empty table -> 70.0 kg default) to
    // land, rather than a fixed delay.
    await pumpUntilFound(tester, find.text('70.0'));

    await tester.tap(find.text('70.0'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '70.0');
  });

  testWidgets('typing a value and submitting shows it', (tester) async {
    await tester.pumpWidget(wrapped());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('70.0'));
    await tester.tap(find.text('70.0'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '81.4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('81.4'), findsOneWidget);
  });

  testWidgets(
      'tapping Save while a field is open persists the typed value, not '
      'the pre-edit one', (tester) async {
    // THE critical regression: nothing on Android unfocuses a TextField from
    // a tap outside it (tap-outside-to-unfocus only fires for touch on web),
    // and Save's own tap handler never requests focus either — so without
    // flushing the in-flight edit as the FIRST statement of _save, this
    // writes the seeded 70.0 instead of what was typed.
    await tester.pumpWidget(wrapped());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('70.0'));
    await tester.tap(find.text('70.0'));
    await tester.pumpAndSettle();

    // Type but do NOT submit or blur — tap Save directly while the field is
    // still focused and open.
    await tester.enterText(find.byType(TextField), '81.4');
    await tester.pump();

    await tester.tap(find.text('Save entry'));
    await tester.pump();

    // The write goes through a real PowerSync writeTransaction; a plain
    // pumpAndSettle only advances fake time and never waits for it. Mirror
    // pumpUntilFound's discipline of alternating a short REAL delay with a
    // pump — a single long-lived runAsync block does not reliably drain
    // continuations chained onto a Future created before runAsync started.
    List<Map<String, dynamic>> rows = const [];
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) && rows.isEmpty) {
      await tester.runAsync(() async {
        rows = await database.getAll(
          'SELECT CAST(weight_kg AS REAL) AS weight FROM bodyweight_logs',
        );
      });
      await tester.pump();
      if (rows.isNotEmpty) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }

    expect(rows, hasLength(1));
    expect((rows.first['weight'] as num).toDouble(), closeTo(81.4, 0.005));
  });

  testWidgets(
      'tapping + while a differing edit is open builds on the typed value',
      (tester) async {
    // The ± buttons are always visible (unlike WStepper's, which hide behind
    // the field), so without committing the in-flight edit first, tapping +
    // silently discards it: the bump lands on the stale pre-edit _val, then
    // the field's later (untouched-looking) commit overwrites the bump with
    // the typed text, and the button feels dead.
    await tester.pumpWidget(wrapped());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('70.0'));
    await tester.tap(find.text('70.0'));
    await tester.pumpAndSettle();

    // Type but do NOT submit — tap + directly while the field is still open.
    await tester.enterText(find.byType(TextField), '81.4');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // kg mode steps by 0.1: one step above the TYPED 81.4, not the seeded 70.0.
    expect(find.text('81.5'), findsOneWidget);
  });

  testWidgets('typing a negative value clamps to 0', (tester) async {
    await tester.pumpWidget(wrapped());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('70.0'));
    await tester.tap(find.text('70.0'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '-5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('0.0'), findsOneWidget);
  });
}
