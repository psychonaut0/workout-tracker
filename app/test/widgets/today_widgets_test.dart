import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/widgets/week_strip.dart';
import 'package:workout_tracker/widgets/volume_bars.dart';

import '../support/l10n_harness.dart';

/// Pump [widget] inside the localized workout-theme harness so that
/// `context.tokens` and `AppLocalizations.of(context)` both resolve.
Future<void> pumpWithTheme(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    wrapL10n(SingleChildScrollView(child: widget)),
  );
}

// ── WeekStrip ─────────────────────────────────────────────────────────────────

void main() {
  group('WeekStrip', () {
    const days = [
      (name: 'Upper A', weekday: 0, isNext: true, done: false),
      (name: 'Lower A', weekday: 1, isNext: false, done: true),
      (name: 'Upper B', weekday: 3, isNext: false, done: false),
      (name: 'Lower B', weekday: 4, isNext: false, done: false),
    ];

    testWidgets('renders NEXT label for the isNext chip', (tester) async {
      await pumpWithTheme(tester, const WeekStrip(days: days));

      // The NEXT label is a Text widget with exactly 'NEXT'.
      expect(find.text('NEXT'), findsOneWidget);
    });

    testWidgets('renders WIcons.check for a done chip', (tester) async {
      await pumpWithTheme(tester, const WeekStrip(days: days));

      // Lower A is done → expect a check Icon in the tree.
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == WIcons.check,
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not render NEXT or check for idle chips', (tester) async {
      await pumpWithTheme(tester, const WeekStrip(days: days));

      // Only one NEXT, only one check.
      expect(find.text('NEXT'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == WIcons.check,
        ),
        findsOneWidget,
      );
    });

    testWidgets('strips spaces from day names', (tester) async {
      await pumpWithTheme(tester, const WeekStrip(days: days));

      // 'Upper A' → 'UpperA'; original spaced form should not appear.
      expect(find.text('UpperA'), findsOneWidget);
      expect(find.text('Upper A'), findsNothing);
    });
  });

  // ── VolumeBars ───────────────────────────────────────────────────────────────

  group('VolumeBars', () {
    /// The app's dark-mode lime accent token for comparison.
    final darkTokens = WorkoutTokens.dark(accents[0]);

    const rows = [
      (muscle: 'quads', sets: 8, target: 16),   // under target → lineStrong
      (muscle: 'back', sets: 14, target: 14),    // on target    → accent
      (muscle: 'chest', sets: 13, target: 12),   // over target  → accent
    ];

    testWidgets('uses lineStrong fill when sets < target', (tester) async {
      await pumpWithTheme(tester, const VolumeBars(rows: rows));

      // Find Containers whose decoration uses lineStrong as their color.
      // The fill bar is a Container with a BoxDecoration color.
      final muteContainers = tester.widgetList<Container>(
        find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final deco = w.decoration;
          if (deco is! BoxDecoration) return false;
          return deco.color == darkTokens.lineStrong;
        }),
      );
      expect(muteContainers.isNotEmpty, isTrue,
          reason: 'Expected at least one fill bar with lineStrong color');
    });

    testWidgets('uses accent fill when sets >= target', (tester) async {
      await pumpWithTheme(tester, const VolumeBars(rows: rows));

      // There are 2 rows with sets >= target (back: 14/14, chest: 13/12).
      final accentContainers = tester.widgetList<Container>(
        find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final deco = w.decoration;
          if (deco is! BoxDecoration) return false;
          return deco.color == darkTokens.accent;
        }),
      );
      expect(accentContainers.length, greaterThanOrEqualTo(2),
          reason: 'Expected at least 2 fill bars with accent color');
    });

    testWidgets('shows sets/target text for each row', (tester) async {
      await pumpWithTheme(tester, const VolumeBars(rows: rows));

      expect(find.text('8/16'), findsOneWidget);
      expect(find.text('14/14'), findsOneWidget);
      expect(find.text('13/12'), findsOneWidget);
    });

    testWidgets('value text is dim when under target, text-color when met',
        (tester) async {
      await pumpWithTheme(tester, const VolumeBars(rows: rows));

      // '8/16' is under target → dim color.
      final underText = tester.widget<Text>(find.text('8/16'));
      expect(underText.style?.color, darkTokens.dim);

      // '14/14' is on target → text color.
      final onText = tester.widget<Text>(find.text('14/14'));
      expect(onText.style?.color, darkTokens.text);
    });
  });
}
