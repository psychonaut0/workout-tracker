import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

/// Two owned training days.
Future<void> seedTwoDays(PowerSyncDatabase d) async {
  await seedDay(d, 'd1', 'Upper', position: 0);
  await seedDay(d, 'd2', 'Lower', position: 1);
}

/// Two finished workouts on fixed dates, inserted latest first; the first
/// one is in March 2026.
Future<void> seedTwoSessions(PowerSyncDatabase d) async {
  await seedSession(d, 's2',
      date: DateTime(2026, 5, 2), label: 'Lower', sets: const []);
  await seedSession(d, 's1',
      date: DateTime(2026, 3, 14), label: 'Upper', sets: const []);
}

Future<void> seedDaysAndSessions(PowerSyncDatabase d) async {
  await seedTwoDays(d);
  await seedTwoSessions(d);
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  final line = find.byKey(const Key('profile-training-line'));
  String lineText(WidgetTester tester) => tester.widget<Text>(line).data!;

  Future<void> pumpProfile(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(harness.wrap(
        ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
        locale: locale));
  }

  testWidgets('shows the first workout month and the number of training days',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'Profile en');
    expect(lineText(tester), 'Training since Mar 2026 · 2-day split');
    await harness.unmount(tester);
  });

  testWidgets('reads in the UI language', (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester, locale: const Locale('de'));
    await settleUntilFound(tester, line, where: 'Profile de');
    expect(lineText(tester), 'Training seit März 2026 · 2-Tage-Split');
    await harness.unmount(tester);
  });

  testWidgets('a fresh install shows no line, and no made-up one',
      (tester) async {
    await harness.open(tester, seed: (_) async {});
    await pumpProfile(tester);
    await settleReal(tester);
    expect(line, findsNothing);
    expect(find.textContaining('Training since'), findsNothing);
    // The line is live, not stalled: the first training day brings it in.
    await tester.runAsync(
        () => seedDay(harness.database, 'd1', 'Upper', position: 0));
    await settleUntilFound(tester, line, where: 'after the first day');
    expect(lineText(tester), '1-day split');
    await harness.unmount(tester);
  });

  testWidgets('training days without a workout show the split alone',
      (tester) async {
    await harness.open(tester, seed: seedTwoDays);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'days only');
    expect(lineText(tester), '2-day split');
    await harness.unmount(tester);
  });

  testWidgets('workouts without a training day show "since" alone',
      (tester) async {
    await harness.open(tester, seed: seedTwoSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'sessions only');
    expect(lineText(tester), 'Training since Mar 2026');
    await harness.unmount(tester);
  });

  testWidgets('deleting the first workout moves "since" forward',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(
        tester, find.text('Training since Mar 2026 · 2-day split'),
        where: 'before the delete');
    await tester.runAsync(() =>
        harness.database.execute("DELETE FROM sessions WHERE id = 's1'"));
    await settleUntilFound(
        tester, find.text('Training since May 2026 · 2-day split'),
        where: 'after the delete');
    await harness.unmount(tester);
  });

  testWidgets('editing the name hides the line, and saving brings it back',
      (tester) async {
    await harness.open(tester, seed: seedDaysAndSessions);
    await pumpProfile(tester);
    await settleUntilFound(tester, line, where: 'before editing');
    await tester.tap(find.text('Athlete'));
    await settleReal(tester, ticks: 2);
    expect(line, findsNothing);
    await tester.tap(find.text('Save'));
    // No new query: the line comes back from the value already held.
    await settleReal(tester, ticks: 2);
    expect(lineText(tester), 'Training since Mar 2026 · 2-day split');
    await harness.unmount(tester);
  });
}
