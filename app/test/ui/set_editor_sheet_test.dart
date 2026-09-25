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

/// A host that opens the sheet the same way History does — via
/// `showModalBottomSheet` — so its route can actually be popped, exercising
/// the real dismissal path instead of just the sheet in isolation.
Widget host(FakeSessionRepository repo, List<LoggedSet> sets) => wrapL10n(
      Builder(
        builder: (context) => ElevatedButton(
          key: const Key('open-sheet'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => SetEditorSheet(
              block: ExerciseBlockData(
                  exerciseId: 'bench', sets: sets, topWeight: 100, topReps: 5, isPr: false),
              exercise: _exercise,
              sessionId: 'session-1',
              sessionRepo: repo,
              units: UnitService(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

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

    // The flushed timer must actually be cancelled — no second, stale fire
    // later.
    await tester.pump(const Duration(milliseconds: 500));
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

    await tester.tap(find.byKey(const Key('delete-set')));
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, isEmpty); // nothing before the confirm
    await tester.tap(find.text('Delete')); // the showWConfirm confirm button
    await tester.pumpAndSettle();

    expect(repo.deleteCalls, ['s1']);
    expect(find.byKey(const Key('live-weight')), findsNothing);
    expect(repo.updateCalls, isEmpty); // no updateSet call after the delete
  });

  testWidgets('delete set: cancelling the confirm leaves the card open and the set untouched',
      (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1', weight: 100, reps: 5, rir: 2)]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deleteCalls, isEmpty);
    // The card is still open with its original values.
    expect(find.byKey(const Key('live-weight')), findsOneWidget);
    expect(
        tester.widget<RulerPicker>(find.byKey(const Key('live-weight'))).value, 100);
    expect(tester.widget<RulerPicker>(find.byKey(const Key('live-reps'))).value, 5);
  });

  testWidgets('add set calls addSet, seeded from the last working set, and opens its card',
      (tester) async {
    final repo = FakeSessionRepository()..nextId = 's2';
    await tester.pumpWidget(sheet(repo, [_set('s1', weight: 102.5, reps: 6, rir: 2)]));

    await tester.tap(find.byKey(const Key('add-set')));
    await tester.pumpAndSettle();

    expect(repo.addCalls, hasLength(1));
    final call = repo.addCalls.single;
    expect(call.sessionId, 'session-1');
    expect(call.exerciseId, 'bench');
    expect(call.weightKg, '102.50');
    expect(call.reps, 6);
    expect(call.rir, 2);
    expect(call.isWarmup, isFalse);
    expect(find.byKey(const Key('live-weight')), findsOneWidget);
  });

  testWidgets('the RIR chips in the open card are at least 48dp tall', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('rir-0'))).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the Delete set action is at least 48dp tall', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('delete-set'))).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the Add set action is at least 48dp tall', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1')]));

    expect(tester.getSize(find.byKey(const Key('add-set'))).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a working set with no RIR recorded shows no RIR label on its line', (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(sheet(repo, [_set('s1', rir: null)]));

    expect(find.textContaining('RIR'), findsNothing);
  });

  testWidgets(
      'a pending edit is flushed synchronously when the sheet is popped, ahead of the '
      'exit animation and dispose',
      (tester) async {
    final repo = FakeSessionRepository();
    await tester.pumpWidget(host(repo, [_set('s1')]));
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('set-line-s1')));
    await tester.pumpAndSettle();

    await tester.timedDrag(find.byKey(const Key('live-weight')), dragOffset, dragDuration);
    await tester.pump();
    expect(repo.updateCalls, isEmpty); // debounce still pending

    // Dismiss by tapping the modal barrier — the real dismissal path a user
    // takes, distinct from Navigator.pop called directly. showModalBottomSheet
    // completes its future at pop, before the exit animation ends.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(); // let the pop's synchronous work run; no time elapses

    // The sheet is still mid-exit-animation (not yet disposed) — proves this
    // was PopScope firing at pop, not the dispose backstop.
    expect(find.byType(SetEditorSheet), findsOneWidget);
    expect(repo.updateCalls, hasLength(1));
    expect(repo.updateCalls.single.id, 's1');

    await tester.pumpAndSettle(); // let the exit animation and dispose finish
  });
}
