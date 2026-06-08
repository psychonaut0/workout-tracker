import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/widgets/split_card.dart';

import '../support/l10n_harness.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// A minimal [DayTemplate] for use in tests.
DayTemplate _makeDay({
  required String id,
  required String name,
  String? focus,
  int? scheduledWeekday,
  int position = 0,
}) {
  return DayTemplate(
    id: id,
    name: name,
    focus: focus,
    scheduledWeekday: scheduledWeekday,
    position: position,
    slots: const [],
  );
}

/// Pumps [widget] inside the localized workout-theme harness.
Future<void> pumpWithTheme(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    wrapL10n(SingleChildScrollView(child: widget)),
  );
}

// ── fixtures ──────────────────────────────────────────────────────────────────

final _dayA = _makeDay(
  id: 'day-a',
  name: 'Upper A',
  focus: 'Push',
  scheduledWeekday: 0,
  position: 0,
);

final _dayB = _makeDay(
  id: 'day-b',
  name: 'Lower A',
  focus: 'Quad + Calf',
  scheduledWeekday: 1,
  position: 1,
);

final _twodays = [
  (day: _dayA, exerciseCount: 5, lastAgo: '3d ago'),
  (day: _dayB, exerciseCount: 4, lastAgo: '1w ago'),
];

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SplitCard', () {
    testWidgets(
        'Start on the initial day slide (nextIndex=0) calls onStart with that day',
        (tester) async {
      DayTemplate? received;
      bool called = false;

      await pumpWithTheme(
        tester,
        SplitCard(
          days: _twodays,
          nextIndex: 0,
          onStart: (d) {
            called = true;
            received = d;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap the Start button — it is rendered as an InkWell child inside the
      // animated card; find by text label.
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      expect(called, isTrue, reason: 'onStart should have been called');
      expect(received, equals(_dayA),
          reason: 'onStart should receive the day on the active slide');
    });

    testWidgets(
        'Swiping to the Custom slide makes Start call onStart(null)',
        (tester) async {
      DayTemplate? received;
      bool called = false;

      await pumpWithTheme(
        tester,
        SplitCard(
          days: _twodays,
          nextIndex: 0,
          onStart: (d) {
            called = true;
            received = d;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Drag through all day slides until the Custom slide is visible.
      // There are 2 day slides + 1 Custom slide = 3 slides total.
      // Starting at index 0, we drag left twice to reach the Custom slide.
      final pageView = find.byType(PageView);

      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Now on the Custom slide — button label should be 'Start empty'.
      expect(find.text('Start empty'), findsOneWidget,
          reason: 'Custom slide should show "Start empty" button');

      await tester.tap(find.text('Start empty'));
      await tester.pumpAndSettle();

      expect(called, isTrue, reason: 'onStart should have been called');
      expect(received, isNull,
          reason: 'onStart should receive null for the Custom slide');
    });

    testWidgets(
        'Eyebrow shows NEXT IN ROTATION for nextIndex slide, not always index 0',
        (tester) async {
      // nextIndex=1 → slide at index 1 should show 'NEXT IN ROTATION',
      // slide at index 0 should show 'SWITCH TO ·'.
      await pumpWithTheme(
        tester,
        SplitCard(
          days: _twodays,
          nextIndex: 1,
          onStart: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // Page starts at nextIndex=1, so 'NEXT IN ROTATION' should be visible.
      expect(find.text('NEXT IN ROTATION'), findsOneWidget);
    });

    testWidgets(
        'Navigating to Custom slide shows CustomSlide content',
        (tester) async {
      await pumpWithTheme(
        tester,
        SplitCard(
          days: _twodays,
          nextIndex: 0,
          onStart: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      final pageView = find.byType(PageView);

      // Drag past both day slides.
      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('NO TEMPLATE'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Build it as you go'), findsOneWidget);
    });

    testWidgets(
        'Initial slide shows NEXT IN ROTATION when nextIndex=0',
        (tester) async {
      await pumpWithTheme(
        tester,
        SplitCard(
          days: _twodays,
          nextIndex: 0,
          onStart: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NEXT IN ROTATION'), findsOneWidget);
    });
  });
}
