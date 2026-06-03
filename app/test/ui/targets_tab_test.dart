import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/ui/targets_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xFFD8FF3E)),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders all 8 canonical muscles', (tester) async {
    await tester.pumpWidget(_wrap(TargetsList(targets: const {}, onChanged: (_, __) {})));
    for (final label in ['Chest', 'Back', 'Shoulders', 'Quads', 'Hamstrings', 'Calves', 'Biceps', 'Triceps']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('increment reports (muscle, newValue)', (tester) async {
    String? muscle;
    int? sets;
    await tester.pumpWidget(_wrap(TargetsList(
      targets: const {'chest': MuscleTarget(id: 't1', muscle: 'chest', targetSets: 12)},
      onChanged: (m, s) {
        muscle = m;
        sets = s;
      },
    )));
    // Chest is the first row (kMuscleLabels order); WStepper's "+" uses Icons.add.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    expect(muscle, 'chest');
    expect(sets, 13);
  });
}
