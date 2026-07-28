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
