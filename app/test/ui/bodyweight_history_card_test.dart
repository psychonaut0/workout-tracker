import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/settings/bodyweight_goal.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/ui/bodyweight_view.dart';

import '../support/l10n_harness.dart';

final _series = [
  (date: '2026-09-06', value: 67.0, reps: 0, isPr: false),
  (date: '2026-09-18', value: 67.3, reps: 0, isPr: false), // +0.3
  (date: '2026-09-24', value: 66.3, reps: 0, isPr: false), // −1
];

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  testWidgets('deltas are always signed, with a true minus', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.maintain))));
    expect(find.text('−1'), findsOneWidget);
    expect(find.text('+0.3'), findsOneWidget);
  });

  testWidgets('on cut, a loss is accent and a gain is neutral', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.cut))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(_colorOf(tester, '−1'), tokens.accent);
    expect(_colorOf(tester, '+0.3'), tokens.dim);
  });

  testWidgets('on maintain nothing is coloured', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.maintain))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(_colorOf(tester, '−1'), tokens.dim);
    expect(_colorOf(tester, '+0.3'), tokens.dim);
  });

  testWidgets('the date fits on one line', (tester) async {
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: SizedBox(width: 360, child: BodyweightHistoryCard(series: _series, unit: 'kg', goal: BodyweightGoal.cut)))));
    // One line of 12pt mono, never wrapped (it may ellipsize at large scales).
    final date = find.textContaining('24');
    expect(tester.getSize(date.first).height, lessThan(24));
  });
}
