import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/history_screen.dart';

import 'pump_until.dart';
import 'screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('mounts a screen with a one-shot read over the seeded database',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(
        harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
    await pumpUntilFound(tester, find.text(longExercise));
    tester.takeException(); // layout is the sweep's job; this pins the harness
    await harness.unmount(tester);
  });

  testWidgets('drives the stream-owning shell across tabs without hanging',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(harness
        .wrap(AppShell(onLogout: () async {}, auth: AuthStore())));
    await settleReal(tester);
    await openTab(tester, WIcons.history);
    expect(
        find.descendant(
            of: find.byType(HistoryScreen), matching: find.byType(SessionCard)),
        findsWidgets);
    tester.takeException();
    await harness.unmount(tester);
  });
}
