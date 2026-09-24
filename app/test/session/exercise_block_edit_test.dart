import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/exercise_block.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

BlockState _block({bool firstDone = false}) {
  final exercise = Exercise(
    id: 'e1', name: 'Bench Press', slug: 'bench', muscleGroup: 'chest',
    compound: true, plateStepKg: 2.5, isTemplate: false,
  );
  return BlockState(
    exercise: exercise,
    resolved: ResolvedSlot(exercise: exercise, workSets: 2, warmupSets: 0,
        repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 2),
    warmupSets: [],
    workingSets: [
      SetState(id: 's1', weightKg: 60, reps: 8, rir: 1, isWarmup: false, done: firstDone),
      SetState(id: 's2', weightKg: 60, reps: 8, rir: 1, isWarmup: false, done: false),
    ],
    expanded: true,
  );
}

void main() {
  late List<String> removed;
  late int warmups;
  late int ups;
  late int downs;

  setUp(() {
    removed = [];
    warmups = 0;
    ups = 0;
    downs = 0;
  });

  Widget host(BlockState b, {bool canMoveUp = true, bool canMoveDown = true}) => wrapL10n(
        SingleChildScrollView(
          child: ExerciseBlock(
            key: const ValueKey('e1'),
            block: b,
            unit: UnitService(),
            onToggleDone: (_, __) {},
            onSetChanged: (_, __) {},
            onAddSet: (_) {},
            onRemoveBlock: (_) {},
            onRemoveSet: (_, s) => removed.add(s.id),
            onAddWarmup: (_) => warmups++,
            onMoveUp: canMoveUp ? () => ups++ : null,
            onMoveDown: canMoveDown ? () => downs++ : null,
          ),
        ),
      );

  Finder rowOf(String setId) => find.byKey(ValueKey('dismiss-$setId'));

  testWidgets('swiping an unticked set left removes it without asking', (tester) async {
    await tester.pumpWidget(host(_block()));
    await tester.pumpAndSettle();
    await tester.drag(rowOf('s2'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove set?'), findsNothing);
    expect(removed, ['s2']);
  });

  testWidgets('swiping a ticked set asks first; cancelling keeps it', (tester) async {
    await tester.pumpWidget(host(_block(firstDone: true)));
    await tester.pumpAndSettle();
    await tester.drag(rowOf('s1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove set?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
    expect(rowOf('s1'), findsOneWidget);

    await tester.drag(rowOf('s1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, ['s1']);
  });

  testWidgets('swiping right does nothing', (tester) async {
    await tester.pumpWidget(host(_block()));
    await tester.pumpAndSettle();
    await tester.drag(rowOf('s2'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
  });

  testWidgets('the warm-up button sits next to Add set and fires its callback', (tester) async {
    await tester.pumpWidget(host(_block()));
    await tester.pumpAndSettle();
    expect(find.text('Add set'), findsOneWidget);
    await tester.tap(find.text('Warm-up'));
    expect(warmups, 1);
  });

  testWidgets('the footer does not overflow on a narrow phone at large text (Italian)', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 900), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(
        SingleChildScrollView(
          child: ExerciseBlock(
            block: _block(),
            unit: UnitService(),
            onToggleDone: (_, __) {},
            onSetChanged: (_, __) {},
            onAddSet: (_) {},
            onRemoveBlock: (_) {},
            onRemoveSet: (_, __) {},
            onAddWarmup: (_) {},
            onMoveUp: () {},
            onMoveDown: () {},
          ),
        ),
        locale: const Locale('it'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Riscaldamento'), findsOneWidget);
  });

  testWidgets('move arrows fire, and a missing callback disables its arrow', (tester) async {
    await tester.pumpWidget(host(_block(), canMoveUp: false));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Move up'));
    await tester.tap(find.bySemanticsLabel('Move down'));
    expect(ups, 0);
    expect(downs, 1);
  });
}
