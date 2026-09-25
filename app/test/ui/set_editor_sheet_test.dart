import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/ui/set_editor_sheet.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

import '../support/l10n_harness.dart';

/// Records every mutating call instead of touching a database.
class FakeSessionRepository implements SessionRepository {
  final updateCalls = <({String id, String weightKg, int reps, int? rir})>[];
  final deleteCalls = <String>[];
  final addCalls = <({String sessionId, String exerciseId, String weightKg, int reps, int? rir, bool isWarmup})>[];
  String nextId = 'new-set';

  @override
  Future<void> updateSet(String id, {required String weightKg, required int reps, required int? rir}) {
    updateCalls.add((id: id, weightKg: weightKg, reps: reps, rir: rir));
    return Future.value();
  }

  @override
  Future<void> deleteSet(String id) {
    deleteCalls.add(id);
    return Future.value();
  }

  @override
  Future<String> addSet(String sessionId, String exerciseId,
      {required String weightKg, required int reps, required int? rir, required bool isWarmup}) {
    addCalls.add((
      sessionId: sessionId,
      exerciseId: exerciseId,
      weightKg: weightKg,
      reps: reps,
      rir: rir,
      isWarmup: isWarmup,
    ));
    return Future.value(nextId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _exercise = Exercise(
  id: 'bench',
  name: 'Bench',
  slug: 'bench',
  muscleGroup: 'chest',
  compound: true,
  plateStepKg: 2.5,
  isTemplate: false,
  defaultRepLow: 8,
);

LoggedSet _set(String id, {double weight = 100, int reps = 5, int? rir = 1, bool isWarmup = false}) =>
    LoggedSet(
      id: id,
      exerciseId: 'bench',
      setNumber: 1,
      weightKg: weight,
      reps: reps,
      rir: rir,
      isWarmup: isWarmup,
      isTopSet: false,
      isPr: false,
    );

Widget sheet(FakeSessionRepository repo, List<LoggedSet> sets) => wrapL10n(SetEditorSheet(
      block: ExerciseBlockData(exerciseId: 'bench', sets: sets, topWeight: 100, topReps: 5, isPr: false),
      exercise: _exercise,
      sessionId: 'session-1',
      sessionRepo: repo,
      units: UnitService(),
    ));

void main() {
  testWidgets('each set is a >=48dp line; tapping one opens its rulers', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1'), _set('s2', weight: 120, reps: 6)]));

    expect(
        tester.getSize(find.byKey(const Key('set-line-s1'))).height, greaterThanOrEqualTo(48));
    expect(
        tester.getSize(find.byKey(const Key('set-line-s2'))).height, greaterThanOrEqualTo(48));

    expect(find.byKey(const Key('live-weight')), findsNothing);
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-weight')), findsOneWidget);
  });

  // A short, single-item drag is used (rather than a longer multi-item one)
  // so exactly one ruler value-crossing happens, close to the drag's end —
  // that keeps the 400ms debounce window cleanly observable instead of
  // overlapping with earlier crossings mid-drag.
  const dragOffset = Offset(-1 * RulerPicker.defaultItemExtent, 0);
  const dragDuration = Duration(milliseconds: 100);

  testWidgets('an edit debounces 400ms before persisting', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.timedDrag(find.byKey(const Key('live-weight')), dragOffset, dragDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.updateCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.updateCalls, hasLength(1));
    expect(repo.updateCalls.single.id, 's1');

    // The persisted value matches whatever the ruler settled on — proves no
    // stale intermediate crossing was written.
    final settled = tester.widget<RulerPicker>(find.byKey(const Key('live-weight'))).value;
    expect(settled, isNot(100)); // sanity: the drag actually moved the ruler
    expect(repo.updateCalls.single.weightKg, settled.toStringAsFixed(2));
  });

  testWidgets('collapsing the open line flushes the pending edit immediately', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.timedDrag(find.byKey(const Key('live-weight')), dragOffset, dragDuration);
    await tester.pump();
    expect(repo.updateCalls, isEmpty); // debounce still pending

    // Tap the (still-open) line again to collapse it, without waiting out
    // the debounce.
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pump();
    expect(repo.updateCalls, hasLength(1));
  });

  testWidgets(
      'typing the original value back in after a swipe still persists it (the '
      "editor's unchanged-value guard must see the live value, not a stale build)",
      (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1', weight: 100)]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    // Swipe the weight away from its original value.
    await tester.timedDrag(find.byKey(const Key('live-weight')), dragOffset, dragDuration);
    await tester.pump();

    // Now type the ORIGINAL value back in.
    await tester.tap(find.descendant(
        of: find.byKey(const Key('live-weight')), matching: find.byKey(const Key('ruler-centre'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('number-entry-field')), '100');
    await tester.tap(find.byKey(const Key('number-entry-done')));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.updateCalls, isNotEmpty);
    expect(repo.updateCalls.last.weightKg, '100.00');
  });

  testWidgets('delete set: confirm calls deleteSet and removes the line', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete set'));
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, isEmpty); // nothing before the confirm
    await tester.tap(find.text('Delete')); // the showWConfirm confirm button
    await tester.pumpAndSettle();

    expect(repo.deleteCalls, ['s1']);
    expect(find.byKey(const Key('live-weight')), findsNothing);
  });

  testWidgets('add set calls addSet and opens the new set card', (tester) async {
    final repo = FakeSessionRepository()..nextId = 's2';
    await tester.pumpWidget(sheet(repo, [_set('s1')]));

    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();

    expect(repo.addCalls, hasLength(1));
    expect(repo.addCalls.single.sessionId, 'session-1');
    expect(repo.addCalls.single.exerciseId, 'bench');
    expect(find.byKey(const Key('live-weight')), findsOneWidget);
  });

  testWidgets('the RIR chips in the open card are at least 48dp tall', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('rir-0'))).height, greaterThanOrEqualTo(48));
  });
}
