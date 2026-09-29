import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/ui/plan_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/ui/today_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('Today, Progress, History and Plan hold at $name',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      final l = lookupAppLocalizations(c.locale);
      await tester.pumpWidget(harness.wrap(
          AppShell(onLogout: () async {}, auth: AuthStore()),
          locale: c.locale));
      await settleReal(tester);

      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(TodayScreen), 'Today $name');

      await openTab(tester, WIcons.chart);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProgressScreen), 'Progress $name');

      await openTab(tester, WIcons.history);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(HistoryScreen), 'History $name');
      final card = find
          .descendant(
              of: find.byType(HistoryScreen), matching: find.byType(SessionCard))
          .first;
      await tester.ensureVisible(card);
      await tester.tap(card, warnIfMissed: false);
      await settleReal(tester, ticks: 15);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(HistoryScreen), 'History expanded $name');

      await openTab(tester, WIcons.plan);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(PlanScreen), 'Plan split $name');
      for (final (label, where) in [
        (l.planTabExercises, 'Plan exercises'),
        (l.planTabTargets, 'Plan targets'),
      ]) {
        await tester.tap(find
            .descendant(of: find.byType(PlanScreen), matching: find.text(label))
            .first);
        await settleReal(tester, ticks: 15);
        await expectLayoutHoldsWhileScrolling(
            tester, find.byType(PlanScreen), '$where $name');
      }

      await harness.unmount(tester);
    });
  }
}
