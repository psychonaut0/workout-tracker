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

  Widget stepper(void Function(double) onChanged) => WStepper(
        value: 80,
        step: 2.5,
        format: (v) => v.toStringAsFixed(1),
        onChanged: onChanged,
        editable: true,
      );

  testWidgets('the field requests the done action', (tester) async {
    await tester.pumpWidget(host(stepper((_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.done');
  });

  testWidgets('dismissing the keyboard commits the typed value',
      (tester) async {
    // THE reported defect. Hiding the Android keyboard does not drop focus, so
    // without an inset-collapse listener the typed text is silently discarded.
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();

    // Keyboard comes up.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '92.5');
    await tester.pump();
    expect(changed, isNull, reason: 'not committed until an exit path fires');

    // System dismisses the keyboard; focus is deliberately untouched.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changed, 92.5);
    expect(find.text('92.5'), findsOneWidget);
  });

  testWidgets('losing focus commits the typed value', (tester) async {
    // NOTE: tester.tap on another widget does NOT unfocus in a widget test
    // (tap-outside only unfocuses for touch on web, and tests force Android),
    // so drive focus loss explicitly.
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '85');
    await tester.pump();

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changed, 85.0);
  });

  testWidgets('being disposed mid-edit commits the typed value',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '77.5');
    await tester.pump();

    // Replacing the root deactivates and unmounts the stepper in one pump.
    await tester.pumpWidget(host(const Text('gone')));
    await tester.pump();

    expect(changed, 77.5);
  });

  testWidgets('text that is not a number commits nothing', (tester) async {
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, isNull);
    expect(find.text('80.0'), findsOneWidget);
  });

  testWidgets('committing only fires onChanged once', (tester) async {
    // Four exit paths can each call _commitEdit; the re-entrancy guard must
    // keep that to a single emission.
    final emitted = <double>[];
    await tester.pumpWidget(host(stepper(emitted.add)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(host(const Text('gone')));
    await tester.pump();

    expect(emitted, [99.0]);
  });
}
