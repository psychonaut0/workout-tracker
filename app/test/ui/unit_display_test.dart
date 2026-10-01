import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/ui/profile_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/ui/today_screen.dart';
import 'package:workout_tracker/widgets/sparkline.dart';

import '../support/screen_harness.dart';

const _lb = <String, Object>{'unit': 'lb'};

Widget _today() => Scaffold(
      body: TodayScreen(
        onStart: (_) {},
        onOpenExercise: (_) {},
        onOpenProfile: () {},
        onResume: () {},
        auth: AuthStore(),
      ),
    );

Widget _profile() =>
    ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore());

/// Two bodyweight entries two days apart, the latest 82.37 kg.
Future<void> _seedBodyweightOnly(PowerSyncDatabase d) async {
  final now = DateTime.now();
  await seedBodyweight(d, now.subtract(const Duration(days: 2)), 82.33);
  await seedBodyweight(d, now, 82.37);
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  group('volume reads the same on Summary and History', () {
    // seedLong's s0 lifts 1482.5 kg (3268 lb); its four sessions 5879 kg
    // (12961 lb).
    testWidgets('Summary shows lb volume as thousands of lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
      await settleUntilFound(tester, find.text(longExercise),
          where: 'Summary lb');
      expect(find.text('3.3k lb'), findsOneWidget);
      expect(find.text('3.3t'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('History shows lb volume as thousands of lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleUntilFound(tester, find.byType(SessionCard),
          where: 'History lb');
      expect(find.text('13k lb'), findsOneWidget);
      expect(find.text('13.0k'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('kg volume reads in tonnes on both (regression pin)',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
      await settleUntilFound(tester, find.text(longExercise),
          where: 'Summary kg');
      expect(find.text('1.5t'), findsOneWidget);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleUntilFound(tester, find.byType(SessionCard),
          where: 'History kg');
      expect(find.text('5.9t'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('an empty four weeks reads 0kg, like an empty session',
        (tester) async {
      await harness.open(tester, seed: (_) async {});
      setPhone(tester, width: 412);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await settleReal(tester);
      expect(find.text('0kg'), findsOneWidget);
      expect(find.text('0.0t'), findsNothing);
      await harness.unmount(tester);
    });
  });

  group('bodyweight reads the same on Today, Profile and its own view', () {
    // seedLong's latest bodyweight is 82.4 kg = 181.66 lb.
    testWidgets('in lb', (tester) async {
      await harness.open(tester, prefs: _lb);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(_today()));
      await settleUntilFound(tester, find.byType(Sparkline), where: 'Today lb');
      expect(find.text('181.7'), findsOneWidget);
      expect(find.text('182'), findsNothing);

      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: bwId))));
      await settleUntilFound(tester, find.text('181.7'),
          where: 'Bodyweight lb');

      await tester.pumpWidget(harness.wrap(_profile()));
      await settleReal(tester);
      expect(find.text('181.7lb'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('in kg, a two-decimal entry reads one decimal everywhere',
        (tester) async {
      await harness.open(tester, seed: _seedBodyweightOnly);
      setPhone(tester, width: 412);
      await tester.pumpWidget(harness.wrap(_today()));
      await settleUntilFound(tester, find.byType(Sparkline), where: 'Today kg');
      expect(find.text('82.4'), findsOneWidget);
      expect(find.text('82.37'), findsNothing);

      await tester.pumpWidget(harness.wrap(
          const Scaffold(body: ProgressScreen(initialTarget: bwId))));
      await settleUntilFound(tester, find.text('82.4'),
          where: 'Bodyweight kg');
      expect(find.text('82.3'), findsOneWidget); // Lowest
      // 82.33 → 82.37 displays 82.3 → 82.4: the 30-day tile and the newest
      // history row both read the change they show, not "same".
      expect(find.text('+0.1'), findsNWidgets(2));

      await tester.pumpWidget(harness.wrap(_profile()));
      await settleReal(tester);
      expect(find.text('82.4kg'), findsOneWidget);
      await harness.unmount(tester);
    });
  });
}
