import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_writer.dart';

class FakeExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  test('persistSession writes 1 session + N sets, stamps client flags', () async {
    final exec = FakeExec();
    await persistSession(exec, SessionWrite(
      id: 'sess1', dateIso: '2026-05-30', dayTemplateId: 'day1',
      splitLabel: 'Upper A - Push', durationMin: 42,
      sets: [
        SetWrite(id:'s1', exerciseId:'e1', setNumber:1, weightKg:'60.00', reps:8, rir:1, isWarmup:false),
        SetWrite(id:'s2', exerciseId:'e1', setNumber:2, weightKg:'80.00', reps:6, rir:1, isWarmup:false, isTopSet:true, isPr:true),
      ],
    ));
    expect(exec.calls.length, 3); // 1 session + 2 sets
    expect(exec.calls.first.$1, contains('INSERT INTO sessions'));
    final setInserts = exec.calls.where((c) => c.$1.contains('INSERT INTO sets')).toList();
    expect(setInserts.length, 2);
    // client flags are written: is_top_set + is_pr are the last two params.
    expect(setInserts[0].$2.sublist(8, 10), [0, 0]); // default false
    expect(setInserts[1].$2.sublist(8, 10), [1, 1]); // top set + pr
  });
}
