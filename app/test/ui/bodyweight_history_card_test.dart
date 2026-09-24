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

  testWidgets('a delta that displays as 0 is never coloured', (tester) async {
    final series = [
      (date: '2026-09-06', value: 67.00, reps: 0, isPr: false),
      (date: '2026-09-07', value: 67.03, reps: 0, isPr: false), // +0.03 → "0"
    ];
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: series, unit: 'kg', goal: BodyweightGoal.bulk))));
    final tokens = tester.element(find.byType(BodyweightHistoryCard)).tokens;
    expect(find.text('0'), findsOneWidget);
    expect(_colorOf(tester, '0'), tokens.dim);
  });

  testWidgets('the oldest visible row still shows a delta when older entries exist', (tester) async {
    // 26 entries, one per day; the card caps display at 24, newest first, so
    // series[0] and series[1] are dropped and series[2] is the oldest shown
    // (the 24th visible row). Its delta must come from series[1] (+3.5, a
    // value distinct from every other consecutive delta, which is +1).
    final values = [0.0, 2.5, 6.0, for (var i = 3; i < 26; i++) 6.0 + (i - 2)];
    final series = List.generate(26, (i) {
      final day = 6 + i; // 2026-08-06 .. 2026-08-31
      return (
        date: '2026-08-${day.toString().padLeft(2, '0')}',
        value: values[i],
        reps: 0,
        isPr: false,
      );
    });
    await tester.pumpWidget(wrapL10n(SingleChildScrollView(
        child: BodyweightHistoryCard(series: series, unit: 'kg', goal: BodyweightGoal.maintain))));
    expect(find.text('+3.5'), findsOneWidget);
  });
}
