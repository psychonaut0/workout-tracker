import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/split_tab.dart';

import '../support/l10n_harness.dart';

void main() {
  testWidgets('shows "Push · 7 exercises" for the day card meta', (tester) async {
    await tester.pumpWidget(wrapL10n(SplitDayCard(
      weekday: 1,
      name: 'Upper A',
      focus: 'Push',
      exerciseCount: 7,
      onTap: () {},
    )));

    expect(find.text('Push · 7 exercises'), findsOneWidget);
  });

  testWidgets('fits at 320dp and 1.3x in German', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SplitDayCard(
            weekday: 1,
            name: 'Oberkörper A',
            focus: 'Grundübungen',
            exerciseCount: 7,
            onTap: () {},
          ),
        ),
        locale: const Locale('de'),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
