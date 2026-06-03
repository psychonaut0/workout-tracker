import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/motion.dart';

void main() {
  testWidgets('UnitSwap cross-fades when the key changes and settles on the new child',
      (tester) async {
    Widget build(String unit, String text) => MaterialApp(
          home: UnitSwap(unitKey: unit, child: Text(text)),
        );
    await tester.pumpWidget(build('kg', '100 kg'));
    await tester.pumpAndSettle();
    expect(find.text('100 kg'), findsOneWidget);

    await tester.pumpWidget(build('lb', '220 lb'));
    await tester.pump(const Duration(milliseconds: 40));
    // Mid-swap both children exist (cross-fade).
    expect(find.text('220 lb'), findsOneWidget);
    expect(find.text('100 kg'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('100 kg'), findsNothing);
    expect(find.text('220 lb'), findsOneWidget);
  });

  testWidgets('UnitSwap does not animate when only the value changes',
      (tester) async {
    Widget build(String text) => MaterialApp(
          home: UnitSwap(unitKey: 'kg', child: Text(text)),
        );
    await tester.pumpWidget(build('100 kg'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build('102.5 kg'));
    await tester.pump(const Duration(milliseconds: 40));
    // Same key → AnimatedSwitcher swaps in place, old child gone immediately.
    expect(find.text('100 kg'), findsNothing);
    expect(find.text('102.5 kg'), findsOneWidget);
  });
}
