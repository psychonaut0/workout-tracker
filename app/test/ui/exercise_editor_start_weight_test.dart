import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

// Field renders its label upper-cased.
Finder _startWeight(Finder matching) => find.descendant(
      of: find.ancestor(
          of: find.text('START WEIGHT'), matching: find.byType(Field)),
      matching: matching,
    );

Future<void> _openEditor(WidgetTester tester, ScreenHarness harness) async {
  setPhone(tester, width: 412);
  await tester.pumpWidget(harness.wrap(
      Scaffold(body: ExerciseEditor(id: 'ex3', onBack: () {}))));
  await pumpUntilFound(tester,
      find.descendant(of: find.byType(ExerciseEditor), matching: find.byType(ListView)));
  await scrollIntoView(
      tester, find.byType(ExerciseEditor), find.text('START WEIGHT'));
}

/// The text the start-weight edit field is seeded with when tapped.
Future<String> _editSeed(WidgetTester tester, String shown) async {
  await tester.tap(_startWeight(find.text(shown)));
  await tester.pump();
  return tester
      .widget<TextField>(_startWeight(find.byType(TextField)))
      .controller!
      .text;
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('in lb the start weight reads whole pounds, like a live set',
      (tester) async {
    // seedLong's ex3 starts at 20 kg = 44.09 lb.
    await harness.open(tester, prefs: const {'unit': 'lb'});
    await _openEditor(tester, harness);
    expect(_startWeight(find.text('44lb')), findsOneWidget);
    expect(await _editSeed(tester, '44lb'), '44');
    await harness.unmount(tester);
  });

  testWidgets('in kg a quarter-kilo start weight keeps both decimals',
      (tester) async {
    await harness.open(tester, seed: (d) async {
      await seedLong(d);
      await d.execute(
          "UPDATE exercises SET base_weight_kg = '1.25' WHERE id = 'ex3'");
    });
    await _openEditor(tester, harness);
    expect(_startWeight(find.text('1.25kg')), findsOneWidget);
    expect(await _editSeed(tester, '1.25kg'), '1.25');
    await harness.unmount(tester);
  });
}
