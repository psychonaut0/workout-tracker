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

  testWidgets('the weekday block stays on one line at 1.3x ("WED")',
      (tester) async {
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
            weekday: 2, // Monday-origin: Wednesday
            name: 'Legs',
            focus: null,
            exerciseCount: 5,
            onTap: () {},
          ),
        ),
      ),
    ));

    final badge = find.text('WED');
    expect(badge, findsOneWidget);
    final text = tester.widget<Text>(badge);
    expect(text.maxLines, 1);
    // One display line at 20 * 1.3 is ~30dp tall; a wrap would be twice that.
    final lineHeight = 20 * 1.3 * 1.5;
    expect(tester.getSize(badge).height, lessThan(lineHeight));
    expect(tester.takeException(), isNull);
  });
}
