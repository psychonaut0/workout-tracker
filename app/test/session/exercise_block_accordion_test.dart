import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/exercise_block.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/units/unit_service.dart';

void main() {
  BlockState makeBlock() {
    final exercise = Exercise(
      id: 'e1',
      name: 'Bench Press',
      slug: 'bench',
      muscleGroup: 'chest',
      compound: true,
      plateStepKg: 2.5,
      isTemplate: false,
    );
    final resolved = ResolvedSlot(
      exercise: exercise,
      workSets: 1,
      warmupSets: 0,
      repLow: 8,
      repHigh: 10,
      rirLow: 1,
      rirHigh: 2,
    );
    return BlockState(
      exercise: exercise,
      resolved: resolved,
      warmupSets: [],
      workingSets: [
        SetState(
          id: 's1',
          weightKg: 60,
          reps: 8,
          rir: 1,
          isWarmup: false,
          done: false,
        ),
      ],
      expanded: true,
    );
  }

  Widget host(BlockState b, {required bool showBlock}) => MaterialApp(
        theme: buildTheme(Brightness.dark, accents[0]),
        home: Scaffold(
          body: showBlock
              ? SingleChildScrollView(
                  child: ExerciseBlock(
                    key: const ValueKey('e1'),
                    block: b,
                    unit: UnitService(),
                    onToggleDone: (_, __) {},
                    onSetChanged: (_, __) {},
                    onAddSet: (_) {},
                    onRemoveBlock: (_) {},
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );

  testWidgets('collapse survives State disposal (scroll-out simulation)',
      (tester) async {
    final b = makeBlock();

    await tester.pumpWidget(host(b, showBlock: true));
    await tester.pumpAndSettle();
    // Expanded: the "Add set" affordance is visible.
    expect(find.text('Add set'), findsOneWidget);

    // Collapse via the header tap.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(b.expanded, isFalse); // model field updated
    expect(find.text('Add set'), findsNothing);

    // Simulate scroll-out: unmount the block entirely, then remount.
    await tester.pumpWidget(host(b, showBlock: false));
    await tester.pump();
    await tester.pumpWidget(host(b, showBlock: true));
    await tester.pumpAndSettle();

    // Still collapsed after remount.
    expect(b.expanded, isFalse);
    expect(find.text('Add set'), findsNothing);
  });
}
