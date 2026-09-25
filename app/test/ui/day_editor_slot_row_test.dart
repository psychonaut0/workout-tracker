import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/ui/day_editor.dart';

import '../support/l10n_harness.dart';

Exercise _exercise(String id, String name) => Exercise(
  id: id,
  name: name,
  slug: id,
  muscleGroup: 'chest',
  compound: true,
  plateStepKg: 2.5,
  isTemplate: false,
);

DaySlotState _slot(String exerciseId) => DaySlotState(
  draft: SlotDraft(
    exerciseId: exerciseId,
    workSets: 3,
    warmupSets: 0,
    repLow: 8,
    repHigh: 10,
    rirLow: 1,
    rirHigh: 1,
  ),
  rirText: '1',
);

/// Hosts two [DaySlotRow]s in a [ReorderableListView], mirroring the shape
/// used inside the real day editor. Exposes the current order and which
/// row is expanded/removed so tests can assert on callback wiring.
class _Harness extends StatefulWidget {
  const _Harness({this.expandedIndex});

  final int? expandedIndex;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<Exercise> exercises;
  late List<DaySlotState> slots;
  int? expandedIndex;
  int toggleCount = 0;
  String? removedExerciseId;

  @override
  void initState() {
    super.initState();
    exercises = [
      _exercise('ex1', 'Incline bench press'),
      _exercise('ex2', 'Lat pulldown'),
    ];
    slots = [_slot('ex1'), _slot('ex2')];
    expandedIndex = widget.expandedIndex;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: slots.length,
      onReorderItem: (from, to) =>
          setState(() => slots.insert(to, slots.removeAt(from))),
      itemBuilder: (context, i) => DaySlotRow(
        key: ValueKey(slots[i].exerciseId),
        index: i,
        reorderIndex: i,
        total: slots.length,
        slot: slots[i],
        exercise: exercises.firstWhere((e) => e.id == slots[i].exerciseId),
        tokens: tokens,
        expanded: expandedIndex == i,
        onToggle: () {
          toggleCount++;
          setState(() => expandedIndex = expandedIndex == i ? null : i);
        },
        onRemove: () => removedExerciseId = slots[i].exerciseId,
        onChanged: () {},
      ),
    );
  }
}

void main() {
  testWidgets('the handle is 48x48 and labelled for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrapL10n(const _Harness()));

    final handleFinder = find.byIcon(Icons.drag_handle).first;
    final handleBox = find.ancestor(
      of: handleFinder,
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(handleBox.first), const Size(48, 48));

    expect(
      find.bySemanticsLabel(RegExp('Reorder Incline bench press')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the trash button is 48x48, labelled, and fires onRemove', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrapL10n(const _Harness()));

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(
      find.bySemanticsLabel(RegExp('Remove Incline bench press')),
      findsOneWidget,
    );

    final trashBox = find.ancestor(
      of: find.byIcon(Icons.delete_outline).first,
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(trashBox.first), const Size(48, 48));

    await tester.tap(trashBox.first);
    await tester.pumpAndSettle();
    expect(state.removedExerciseId, 'ex1');
    handle.dispose();
  });

  testWidgets('tapping the name toggles the row', (tester) async {
    await tester.pumpWidget(wrapL10n(const _Harness()));
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.tap(find.text('Incline bench press'));
    await tester.pumpAndSettle();

    expect(state.toggleCount, 1);
    expect(state.expandedIndex, 0);
  });

  testWidgets('the handle is absent when the row is expanded', (tester) async {
    await tester.pumpWidget(wrapL10n(const _Harness(expandedIndex: 0)));

    // Row 0 is expanded — no drag handle for it, but row 1's is present.
    expect(find.byIcon(Icons.drag_handle), findsOneWidget);
  });

  testWidgets('dragging row 2 up by its handle reorders the list', (
    tester,
  ) async {
    await tester.pumpWidget(wrapL10n(const _Harness()));
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final handles = find.byIcon(Icons.drag_handle);
    expect(handles, findsNWidgets(2));

    final g = await tester.startGesture(tester.getCenter(handles.at(1)));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(state.slots.map((s) => s.exerciseId), ['ex2', 'ex1']);
  });
}
