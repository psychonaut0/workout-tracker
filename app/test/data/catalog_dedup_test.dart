import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/exercise_repository.dart';

Map<String, Object?> _ex(String id, String name, {int tmpl = 0}) =>
    {'id': id, 'name': name, 'is_template': tmpl};

void main() {
  test('hides a template when a same-named owned exercise exists', () {
    final rows = [
      _ex('u1', 'Back Squat', tmpl: 0),
      _ex('t1', 'Back Squat', tmpl: 1),
      _ex('t2', 'Bench Press', tmpl: 1),
    ];
    expect(dedupeCatalog(rows).map((r) => r['id']).toList(), ['u1', 't2']);
  });
  test('case-insensitive name match', () {
    expect(dedupeCatalog([_ex('u1', 'back squat', tmpl: 0), _ex('t1', 'Back Squat', tmpl: 1)])
        .map((r) => r['id']).toList(), ['u1']);
  });
  test('keeps everything when no overlap', () {
    expect(dedupeCatalog([_ex('u1', 'Curl', tmpl: 0), _ex('t1', 'Bench', tmpl: 1)]).length, 2);
  });
}
