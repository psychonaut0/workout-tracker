import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/catalog_seed.dart';
import 'package:workout_tracker/data/session_writer.dart';

class _FakeExec implements SqlExecutor {
  final List<(String, List<Object?>)> calls = [];
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  test('starterExercises holds the full catalog', () {
    expect(starterExercises.length, 24);
    for (final e in starterExercises) {
      expect(e.slug, isNotEmpty);
      expect(e.name, isNotEmpty);
      expect(e.muscleGroup, isNotEmpty);
    }
    expect(starterExercises.map((e) => e.slug).toSet().length, 24);
  });

  test('seedStarterCatalog inserts one INSERT per exercise, owned by the user', () async {
    final exec = _FakeExec();
    await seedStarterCatalog(exec, 'user-1');
    expect(exec.calls.length, 24);
    final (sql, args) = exec.calls.first;
    expect(sql, contains('INSERT INTO exercises'));
    expect(sql, contains('created_by'));
    expect(sql, contains('is_template'));
    expect(args, contains('user-1'));
    expect(args, contains(0));
  });
}
