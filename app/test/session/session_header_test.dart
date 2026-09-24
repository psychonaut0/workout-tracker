import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_header.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

const _ex = Exercise(
  id: 'lc', name: 'Lying leg curl', slug: 'lc', muscleGroup: 'hamstrings',
  compound: false, plateStepKg: 2.5, isTemplate: false,
);

final _draft = SessionDraft(templateId: 't', name: 'Lower B', focus: 'Posterior Chain',
    startedAt: DateTime(2026, 9, 24, 16), blocks: const []);

void main() {
  late int adds, skips, menus, mins;
  setUp(() => adds = skips = menus = mins = 0);

  Widget header({DateTime? restStart, int restTotal = 0, Locale locale = const Locale('en')}) => wrapL10n(
        SessionHeader(
          draft: _draft, elapsed: const Duration(minutes: 1, seconds: 2),
          doneWork: 1, totalWork: 14, prCount: 0,
          restStart: restStart, restTotal: restTotal,
          nextLabel: 'Next · Lying leg curl · set 1 · 40kg × 8',
          onMinimize: () => mins++, onMenu: () => menus++,
          onAdd30s: () => adds++, onSkip: () => skips++,
        ),
        locale: locale,
      );

  testWidgets('not resting: no rest row', (tester) async {
    await tester.pumpWidget(header());
    expect(find.text('REST'), findsNothing);
    expect(find.text('+30s'), findsNothing);
    expect(find.text('1:02'), findsOneWidget);
  });

  testWidgets('resting: countdown, next line and 48dp chips that fire', (tester) async {
    await tester.pumpWidget(header(restStart: DateTime.now(), restTotal: 90));
    expect(find.text('REST'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('Next · Lying leg curl · set 1 · 40kg × 8'), findsOneWidget);
    final add = find.byKey(const Key('rest-add'));
    final skip = find.byKey(const Key('rest-skip'));
    expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(48));
    await tester.tap(add);
    await tester.tap(skip);
    expect((adds, skips), (1, 1));
  });

  testWidgets('menu and minimize are labelled 48dp buttons', (tester) async {
    await tester.pumpWidget(header());
    await tester.tap(find.bySemanticsLabel('Workout options'));
    await tester.tap(find.bySemanticsLabel('Minimize'));
    expect((menus, mins), (1, 1));
    expect(tester.getSize(find.byKey(const Key('session-menu'))).height, greaterThanOrEqualTo(48));
  });

  testWidgets('no overflow at 320dp / 1.3× (de) while resting', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: header(restStart: DateTime.now(), restTotal: 180, locale: const Locale('de')),
    ));
    expect(tester.takeException(), isNull);
  });

  group('restNextLabel', () {
    final l = lookupAppLocalizations(const Locale('en'));
    final unit = UnitService();
    BlockState block(List<SetState> warm, List<SetState> work) => BlockState(
        exercise: _ex,
        resolved: const ResolvedSlot(exercise: _ex, workSets: 1, warmupSets: 0,
            repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 1),
        warmupSets: warm, workingSets: work, expanded: true);

    test('names the exercise, set and prescription', () {
      final s = SetState(id: 's', weightKg: 40, reps: 8, rir: 1, isWarmup: false, done: false);
      expect(restNextLabel(l, unit, (block: block([], [s]), set: s)),
          'Next · Lying leg curl · set 1 · 40kg × 8');
    });
    test('warm-up variant', () {
      final w = SetState(id: 'w', weightKg: 20, reps: 8, rir: null, isWarmup: true, done: false);
      expect(restNextLabel(l, unit, (block: block([w], []), set: w)),
          'Next · Lying leg curl · warm-up · 20kg × 8');
    });
    test('nothing left: finish', () {
      expect(restNextLabel(l, unit, null), 'Next · Finish workout');
    });
  });
}
