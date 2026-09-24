import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/live_set_card.dart';
import 'package:workout_tracker/session/log_set_bar.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

const _ex = Exercise(
  id: 'lp', name: 'Leg press', slug: 'lp', muscleGroup: 'quads',
  compound: true, plateStepKg: 2.5, isTemplate: false,
);

BlockState _block(List<SetState> warm, List<SetState> work) => BlockState(
      exercise: _ex,
      resolved: const ResolvedSlot(exercise: _ex, workSets: 3, warmupSets: 1,
          repLow: 6, repHigh: 8, rirLow: 1, rirHigh: 1),
      warmupSets: warm, workingSets: work, expanded: true,
    );

SetState _s(String id, {bool warmup = false, bool done = false}) => SetState(
    id: id, weightKg: warmup ? 70 : 140, reps: warmup ? 8 : 6,
    rir: warmup ? null : 1, isWarmup: warmup, done: done);

void main() {
  final unit = UnitService();
  final l = lookupAppLocalizations(const Locale('en'));

  group('labelFor', () {
    final w = _s('w', warmup: true);
    final a1 = _s('a1', done: true);
    final a2 = _s('a2');
    final b = _block([w], [a1, a2]);

    test('pending working set', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: a2), true), 'Log set 2 · 140kg × 6');
    });
    test('pending warm-up', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: w), false), 'Log warm-up · 70kg × 8');
    });
    test('logged working set being corrected', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: a1), true), 'Update set 1');
    });
    test('logged warm-up being corrected', () {
      final dw = _s('dw', warmup: true, done: true);
      expect(LogSetBar.labelFor(l, unit, (block: _block([dw], []), set: dw), true), 'Update warm-up');
    });
    test('nothing live: finish when possible, hidden otherwise', () {
      expect(LogSetBar.labelFor(l, unit, null, true), 'Finish workout');
      expect(LogSetBar.labelFor(l, unit, null, false), isNull);
    });
  });

  testWidgets('the bar is 56dp tall, labelled, and logs on tap', (tester) async {
    final s = _s('a1');
    var logs = 0;
    await tester.pumpWidget(wrapL10n(Align(
      alignment: Alignment.bottomCenter,
      child: LogSetBar(
        live: (block: _block([], [s]), set: s), canFinish: false, unit: unit,
        onLog: () => logs++, onFinish: () {},
      ),
    )));
    final bar = find.byKey(const Key('log-set-bar'));
    expect(tester.getSize(bar).height, 56);
    expect(find.bySemanticsLabel('Log set 1 · 140kg × 6'), findsOneWidget);
    await tester.tap(bar);
    expect(logs, 1);
  });

  testWidgets('renders nothing when there is nothing to log or finish', (tester) async {
    await tester.pumpWidget(wrapL10n(LogSetBar(
      live: null, canFinish: false, unit: unit, onLog: () {}, onFinish: () {},
    )));
    expect(find.byKey(const Key('log-set-bar')), findsNothing);
  });

  testWidgets('with nothing live it finishes', (tester) async {
    var finishes = 0;
    await tester.pumpWidget(wrapL10n(Align(
      alignment: Alignment.bottomCenter,
      child: LogSetBar(live: null, canFinish: true, unit: unit, onLog: () {}, onFinish: () => finishes++),
    )));
    await tester.tap(find.byKey(const Key('log-set-bar')));
    expect(finishes, 1);
  });

  testWidgets('typed weight commits before the bar logs', (tester) async {
    final s = _s('a1');
    final block = _block([], [s]);
    final c = ActiveSessionController()
      ..seedForTest(SessionDraft(templateId: null, name: 'W', focus: '',
          startedAt: DateTime(2026, 9, 24), blocks: [block]));
    await tester.pumpWidget(wrapL10n(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        LiveSetCard(set: s, exercise: _ex, workIndex: 1, lastTop: null, unit: unit,
            onChanged: c.markChanged, onMarkNotDone: () {}),
        const Spacer(),
        LogSetBar(live: c.liveSet, canFinish: c.canFinish, unit: unit,
            onLog: () => setState(() => c.logLiveSet()), onFinish: () {}),
      ]),
    )));
    // Open the weight field and type without pressing Done.
    await tester.tap(find.text('140'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '152.5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('log-set-bar')));
    await tester.pump();
    expect(s.weightKg, 152.5);
    expect(s.done, isTrue);
  });

  testWidgets('a long German label ellipsises on a narrow phone', (tester) async {
    final s = _s('a1');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 320, child: LogSetBar(
          live: (block: _block([], [s]), set: s), canFinish: false, unit: unit,
          onLog: () {}, onFinish: () {},
        )),
      ), locale: const Locale('de')),
    ));
    expect(tester.takeException(), isNull);
  });
}
