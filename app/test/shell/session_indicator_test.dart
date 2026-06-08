import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/session_indicator.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

void main() {
  testWidgets('shows ticking elapsed and taps through', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      home: Scaffold(
        body: SessionIndicator(
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: null,
          restTotal: 0,
          onTap: () => tapped = true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('5:0'), findsOneWidget); // 5:00–5:09 window
    await tester.tap(find.byType(SessionIndicator));
    expect(tapped, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows rest countdown while resting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      home: Scaffold(
        body: SessionIndicator(
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: DateTime.now().subtract(const Duration(seconds: 10)),
          restTotal: 90,
          onTap: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('1:'), findsOneWidget); // ~1:20 remaining
    await tester.pump(const Duration(seconds: 1));
  });
}
