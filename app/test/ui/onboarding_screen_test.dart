import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/onboarding_screen.dart';

void main() {
  testWidgets('shows both choices and reports the selection', (tester) async {
    OnboardingChoice? chosen;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onChosen: (c) async => chosen = c),
    ));
    expect(find.text('Start empty'), findsOneWidget);
    expect(find.text('Add starter exercises'), findsOneWidget);

    await tester.tap(find.text('Add starter exercises'));
    await tester.pumpAndSettle();
    expect(chosen, OnboardingChoice.starter);
  });

  testWidgets('start empty reports the empty choice', (tester) async {
    OnboardingChoice? chosen;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onChosen: (c) async => chosen = c),
    ));
    await tester.tap(find.text('Start empty'));
    await tester.pumpAndSettle();
    expect(chosen, OnboardingChoice.empty);
  });
}
