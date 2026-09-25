import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/session/set_values_editor.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

import '../support/l10n_harness.dart';

void main() {
  late int weightCalls;
  late double? lastWeight;
  setUp(() {
    weightCalls = 0;
    lastWeight = null;
  });

  Widget editor({double weightKg = 140, int reps = 6, UnitService? unit}) => SetValuesEditor(
        weightKg: weightKg,
        reps: reps,
        unit: unit ?? UnitService(),
        onWeight: (v) {
          weightCalls++;
          lastWeight = v;
        },
        onReps: (_) {},
      );

  Widget host(Widget child) =>
      wrapL10n(SingleChildScrollView(child: SizedBox(width: 260, child: child)));

  Future<void> swipe(WidgetTester tester, Key ruler, int steps) async {
    await tester.timedDrag(find.byKey(ruler),
        Offset(-steps * RulerPicker.defaultItemExtent, 0), const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('a weight swipe calls onWeight with the stepped value', (tester) async {
    await tester.pumpWidget(host(editor()));
    await swipe(tester, const Key('live-weight'), 2);
    expect(lastWeight, 141);
    expect(weightCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('typed entry calls onWeight with the typed value', (tester) async {
    await tester.pumpWidget(host(editor()));
    await tester.tap(find.descendant(
        of: find.byKey(const Key('live-weight')), matching: find.byKey(const Key('ruler-centre'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('number-entry-field')), '151,5');
    await tester.tap(find.byKey(const Key('number-entry-done')));
    await tester.pumpAndSettle();
    expect(lastWeight, 151.5);
    expect(weightCalls, 1);
  });

  testWidgets('an untouched lb entry calls nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final lb = UnitService()..setUnit(Unit.lb);
    await tester.pumpWidget(host(editor(weightKg: 100, unit: lb)));
    await tester.tap(find.descendant(
        of: find.byKey(const Key('live-weight')), matching: find.byKey(const Key('ruler-centre'))));
    await tester.pumpAndSettle();
    expect(find.text('220'), findsWidgets); // 100 kg shown as whole pounds
    await tester.tap(find.byKey(const Key('number-entry-done')));
    await tester.pumpAndSettle();
    expect(weightCalls, 0);
  });
}
