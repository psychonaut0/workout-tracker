import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('Profile holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
          locale: c.locale));
      await settleReal(tester);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProfileScreen), 'Profile $name');
      await harness.unmount(tester);
    });
  }
}
