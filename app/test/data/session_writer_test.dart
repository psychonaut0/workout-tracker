import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_writer.dart';

class FakeExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  test('persistSession writes 1 session + N sets, omits computed flags', () async {
    final exec = FakeExec();
    await persistSession(exec, SessionWrite(
      id: 'sess1', dateIso: '2026-05-30', dayTemplateId: 'day1',
      splitLabel: 'Upper A - Push', durationMin: 42,
      sets: [
        SetWrite(id:'s1', exerciseId:'e1', setNumber:1, weightKg:'60.00', reps:8, rir:1, isWarmup:false),
        SetWrite(id:'s2', exerciseId:'e1', setNumber:2, weightKg:'80.00', reps:6, rir:1, isWarmup:false),
      ],
    ));
    expect(exec.calls.length, 3); // 1 session + 2 sets
    expect(exec.calls.first.$1, contains('INSERT INTO sessions'));
    expect(exec.calls.where((c) => c.$1.contains('INSERT INTO sets')).length, 2);
    // computed flags never written:
    for (final c in exec.calls) {
      expect(c.$1.contains('is_top_set'), isFalse);
      expect(c.$1.contains('is_pr'), isFalse);
    }
  });
}
