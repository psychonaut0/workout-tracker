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

    // Signed in with sync on, offline, last synced 3h ago: the longest
    // sync status ("Offline · synchronisiert vor 3 Std").
    testWidgets('Profile signed in holds at $name', (tester) async {
      await harness.open(tester,
          prefs: syncOnPrefs,
          lastSyncedAt:
              DateTime.now().subtract(const Duration(hours: 3, minutes: 5)));
      setPhone(tester, width: c.width, textScale: c.textScale);
      final auth = await signedInAuth(tester);
      await tester.pumpWidget(harness.wrap(
          ProfileScreen(onClose: () {}, onLogout: () async {}, auth: auth),
          locale: c.locale));
      await settleReal(tester);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProfileScreen), 'Profile signed in $name');
      await harness.unmount(tester);
    });
  }
}
