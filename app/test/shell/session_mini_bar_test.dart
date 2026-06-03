import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/session_mini_bar.dart';

void main() {
  testWidgets('shows session name and ticking elapsed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionMiniBar(
          name: 'Upper A',
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: null,
          restTotal: 0,
          onTap: () => tapped = true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Upper A'), findsOneWidget);
    expect(find.textContaining('5:0'), findsOneWidget); // 5:00–5:09 window
    await tester.tap(find.byType(SessionMiniBar));
    expect(tapped, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('swaps to rest countdown while resting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionMiniBar(
          name: 'Upper A',
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: DateTime.now().subtract(const Duration(seconds: 10)),
          restTotal: 90,
          onTap: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Rest'), findsOneWidget);
    expect(find.textContaining('1:'), findsOneWidget); // ~1:20 remaining
    await tester.pump(const Duration(seconds: 1));
  });
}
