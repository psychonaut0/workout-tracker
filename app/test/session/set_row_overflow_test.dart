import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/session/set_row.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _kExercise = Exercise(
  id: 'ex-1',
  name: 'Bench Press',
  slug: 'bench-press',
  muscleGroup: 'chest',
  compound: true,
  plateStepKg: 2.5,
  isTemplate: false,
);

SetState _workingSet() => SetState(
      id: 'set-1',
      weightKg: 80,
      reps: 8,
      rir: 1,
      isWarmup: false,
      done: false,
    );

SetState _warmupSet() => SetState(
      id: 'set-w',
      weightKg: 40,
      reps: 8,
      rir: null,
      isWarmup: true,
      done: false,
    );

/// Pumps [child] inside a [SizedBox(width: 300)] with the app theme,
/// localization delegates, and a [UnitService] provider — narrow enough to
/// trigger the overflow before the fix.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    wrapL10n(
      ChangeNotifierProvider<UnitService>(
        create: (_) => UnitService(),
        child: SizedBox(
          width: 300,
          child: child,
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  final unit = UnitService();

  group('SetRow no overflow at 300 px', () {
    testWidgets('working set (edit mode) renders without overflow',
        (tester) async {
      await _pump(
        tester,
        SetRow(
          set: _workingSet(),
          exercise: _kExercise,
          workIndex: 1,
          unit: unit,
          isLiveTop: false,
          isLivePr: false,
          onChanged: (_) {},
          onToggleDone: () {},
        ),
      );

      // A RenderFlex overflow throws an exception in widget tests, so if we
      // reach this line without error the row is not overflowing.
      expect(tester.takeException(), isNull);
    });

    testWidgets('warm-up set (edit mode) renders without overflow',
        (tester) async {
      await _pump(
        tester,
        SetRow(
          set: _warmupSet(),
          exercise: _kExercise,
          workIndex: -1,
          unit: unit,
          isLiveTop: false,
          isLivePr: false,
          onChanged: (_) {},
          onToggleDone: () {},
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
