import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';

void main() {
  test('rir low/high <-> display string', () {
    expect(rirToString(1, 1), '1');
    expect(rirToString(0, 1), '0–1');
    expect(rirParse('1–0'), (low: 0, high: 1)); // normalize order
    expect(rirParse('2'), (low: 2, high: 2));
  });
  test('Exercise.fromRow parses traits', () {
    final ex = Exercise.fromRow({
      'id': 'x', 'name': 'Incline', 'slug': 'incline-bench', 'muscle_group': 'chest',
      'compound': 1, 'plate_step_kg': '2.5', 'base_weight_kg': '72.5',
      'default_working_sets': 4, 'default_rep_low': 6, 'default_rep_high': 8,
    });
    expect(ex.compound, true);
    expect(ex.plateStepKg, 2.5);
    expect(ex.baseWeightKg, 72.5);
  });
}
