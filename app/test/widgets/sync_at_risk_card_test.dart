// ignore_for_file: invalid_use_of_internal_member
// SyncStatus's constructor is @internal; tests build it directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/sync_health.dart';
import 'package:workout_tracker/widgets/sync_at_risk_card.dart';

import '../support/l10n_harness.dart';

void main() {
  final now = DateTime(2026, 9, 29, 12);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SyncHealth> health({DateTime? last, int pending = 1}) async {
    final h = SyncHealth(
      status: const Stream.empty(),
      initial: SyncStatus(lastSyncedAt: last),
      pendingChanges: () async => pending,
      signedIn: () => true,
      syncEnabled: () => true,
      clock: () => now,
    );
    await h.start();
    return h;
  }

  testWidgets('at risk: shows the date and opens Profile on tap',
      (tester) async {
    final h = await tester.runAsync(() => health(last: DateTime(2026, 9, 4)));
    var taps = 0;
    await tester.pumpWidget(wrapL10n(SyncAtRiskCard(
        health: h!, expired: ValueNotifier(false), onTap: () => taps++)));
    expect(find.textContaining('Not synced since'), findsOneWidget);
    expect(find.textContaining('Sep'), findsOneWidget);
    await tester.tap(find.byType(SyncAtRiskCard));
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('never synced uses the never copy', (tester) async {
    final h = await tester.runAsync(() => health(last: null));
    await tester.pumpWidget(wrapL10n(SyncAtRiskCard(
        health: h!, expired: ValueNotifier(false), onTap: () {})));
    expect(find.text('Not synced yet · changes are on this phone only'),
        findsOneWidget);
    h.dispose();
  });

  testWidgets('not at risk, or the session expired: nothing', (tester) async {
    final safe = await tester.runAsync(() => health(last: now, pending: 1));
    await tester.pumpWidget(wrapL10n(SyncAtRiskCard(
        health: safe!, expired: ValueNotifier(false), onTap: () {})));
    expect(find.textContaining('Not synced'), findsNothing);
    final risky = await tester.runAsync(() => health(last: null));
    await tester.pumpWidget(wrapL10n(SyncAtRiskCard(
        health: risky!, expired: ValueNotifier(true), onTap: () {})));
    expect(find.textContaining('Not synced'), findsNothing);
    safe.dispose();
    risky.dispose();
  });
}
