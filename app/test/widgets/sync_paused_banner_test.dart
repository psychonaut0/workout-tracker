import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/sync_paused_banner.dart';

import '../support/l10n_harness.dart';

void main() {
  const label = 'Sync paused · Sign in again';

  testWidgets('hidden while the session is live', (tester) async {
    final expired = ValueNotifier(false);
    addTearDown(expired.dispose);
    await tester.pumpWidget(
        wrapL10n(SyncPausedBanner(expired: expired, onTap: () {})));

    expect(find.text(label), findsNothing);
  });

  testWidgets('appears when the session expires and taps through',
      (tester) async {
    final expired = ValueNotifier(false);
    addTearDown(expired.dispose);
    var taps = 0;
    await tester.pumpWidget(wrapL10n(
        SyncPausedBanner(expired: expired, onTap: () => taps++)));

    expect(find.text(label), findsNothing);
    expired.value = true;
    await tester.pump();

    expect(find.text(label), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pump();
    expect(taps, 1);

    expect(tester.getSize(find.byType(SyncPausedBanner)).height,
        greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel(label), findsOneWidget);

    expired.value = false;
    await tester.pump();
    expect(find.text(label), findsNothing);
  });

  testWidgets('fits at 320dp and 1.3x in Italian', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final expired = ValueNotifier(true);
    addTearDown(expired.dispose);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SyncPausedBanner(expired: expired, onTap: () {}),
        ),
        locale: const Locale('it'),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Sincronizzazione in pausa · Accedi di nuovo'),
        findsOneWidget);
  });
}
