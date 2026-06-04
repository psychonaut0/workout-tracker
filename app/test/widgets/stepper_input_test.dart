import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/stepper.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark, accents[0]),
        home: Scaffold(body: Center(child: SizedBox(width: 160, child: child))),
      );

  testWidgets('editable: tap value → type → commit fires onChanged',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 80,
      step: 2.5,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '92.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 92.5);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('92.5'), findsOneWidget);
  });

  testWidgets('editable: comma decimal and clamp below zero', (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12,5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 12.5);

    await tester.tap(find.text('12.5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '-4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 0.0);
  });

  testWidgets('editable: invalid input reverts without onChanged',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, isNull);
    expect(find.text('10.0'), findsOneWidget);
  });

  testWidgets('editable: parseDisplay converts typed display value back',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 100, // internal space (e.g. kg)
      step: 1,
      format: (v) => (v * 2).toStringAsFixed(0), // display = 2x internal
      parseDisplay: (d) => d / 2, // back to internal
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('200'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 125.0); // 250 display → 125 internal
  });

  testWidgets('non-editable: tapping the value does nothing', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 10,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.0'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
