import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/active_session_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('the live workout holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      final controller = ActiveSessionController()..seedForTest(longDraft());
      await tester.pumpWidget(harness.wrap(
        const ActiveSessionScreen(),
        locale: c.locale,
        extra: [
          ChangeNotifierProvider<ActiveSessionController>.value(
              value: controller),
        ],
      ));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ActiveSessionScreen), 'Live $name');
      await harness.unmount(tester);
    });
  }
}
