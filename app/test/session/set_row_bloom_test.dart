import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/set_row.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/ambient_layer.dart';

import '../support/l10n_harness.dart';

const _kExercise = Exercise(
  id: 'ex-1',
  name: 'Bench Press',
  slug: 'bench-press',
  muscleGroup: 'chest',
  compound: true,
  plateStepKg: 2.5,
  isTemplate: false,
);

void main() {
  testWidgets('completing a live-PR set fires the ambient bloom',
      (tester) async {
    final ambient = AmbientController();
    var toggled = false;

    await tester.pumpWidget(
      wrapL10n(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UnitService>(create: (_) => UnitService()),
            ChangeNotifierProvider<AmbientController>.value(value: ambient),
          ],
          child: SetRow(
            set: SetState(
              id: 'set-1',
              weightKg: 100,
              reps: 8,
              rir: 1,
              isWarmup: false,
              done: false,
            ),
            exercise: _kExercise,
            workIndex: 1,
            unit: UnitService(),
            isLiveTop: true,
            isLivePr: true,
            onChanged: (_) {},
            onToggleDone: () => toggled = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the check control: the live-PR branch must fire the bloom.
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();

    expect(toggled, isTrue);
    expect(ambient.bloomCount, 1);
  });
}
