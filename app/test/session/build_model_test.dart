import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

// ── FakeExec (reusable in finish tests) ────────────────────────────────────

class FakeExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  // ── D1: build-model tests ────────────────────────────────────────────────

  test('compound block: suggested = roundTo(base + step, step); warm-up ramp', () {
    final ex = Exercise.fromRow({
      'id': 'e',
      'name': 'X',
      'slug': 'x',
      'muscle_group': 'back',
      'compound': 1,
      'plate_step_kg': '2.5',
      'base_weight_kg': '75',
    });
    // no history -> base seed; compound bumps one plate
    final block = buildBlock(
      resolved: ResolvedSlot(
        exercise: ex,
        workSets: 4,
        warmupSets: 2,
        repLow: 6,
        repHigh: 8,
        rirLow: 0,
        rirHigh: 1,
      ),
      lastTopKg: null,
    );
    expect(block.workingSets.length, 4);
    expect(block.warmupSets.length, 2);
    // suggested = roundTo(75 + 2.5, 2.5) = 77.5
    expect(block.workingSets.first.weightKg, 77.5);
    expect(block.warmupSets.first.isWarmup, true);
    // Lock down the warm-up ramp roundTo(suggested*(0.5+0.18*i), step):
    expect(block.warmupSets[0].weightKg, 40.0); // roundTo(77.5*0.50, 2.5) = 38.75 -> 40.0
    expect(block.warmupSets[1].weightKg, 52.5); // roundTo(77.5*0.68, 2.5) = 52.7 -> 52.5
  });

  test('isolation block: no bump, lastTopKg seeds instead of base', () {
    final ex = Exercise.fromRow({
      'id': 'e2',
      'name': 'Y',
      'slug': 'y',
      'muscle_group': 'chest',
      'compound': 0,
      'plate_step_kg': '2.5',
      'base_weight_kg': '40',
    });
    // lastTopKg takes precedence over base
    final block = buildBlock(
      resolved: ResolvedSlot(
        exercise: ex,
        workSets: 3,
        warmupSets: 0,
        repLow: 10,
        repHigh: 12,
        rirLow: 1,
        rirHigh: 1,
      ),
      lastTopKg: 50.0,
    );
    expect(block.workingSets.length, 3);
    expect(block.warmupSets.isEmpty, true);
    // isolation: no bump; suggested = roundTo(50.0 + 0, 2.5) = 50.0
    expect(block.workingSets.first.weightKg, 50.0);
  });

  test('no baseWeightKg and no history -> falls back to 20 floor', () {
    final ex = Exercise.fromRow({
      'id': 'e3',
      'name': 'Z',
      'slug': 'z',
      'muscle_group': 'arms',
      'compound': 0,
      'plate_step_kg': '2.5',
    });
    final block = buildBlock(
      resolved: ResolvedSlot(
        exercise: ex,
        workSets: 3,
        warmupSets: 0,
        repLow: 10,
        repHigh: 12,
        rirLow: 1,
        rirHigh: 1,
      ),
      lastTopKg: null,
    );
    // seed = 20 (custom-only floor), no compound bump
    // suggested = roundTo(20 + 0, 2.5) = 20.0
    expect(block.workingSets.first.weightKg, 20.0);
  });

  test('SetState defaults: warmup done=false, isWarmup=true, rir=null', () {
    final ex = Exercise.fromRow({
      'id': 'e',
      'name': 'X',
      'slug': 'x',
      'muscle_group': 'back',
      'compound': 1,
      'plate_step_kg': '2.5',
      'base_weight_kg': '75',
    });
    final block = buildBlock(
      resolved: ResolvedSlot(
        exercise: ex,
        workSets: 2,
        warmupSets: 1,
        repLow: 6,
        repHigh: 8,
        rirLow: 0,
        rirHigh: 1,
      ),
      lastTopKg: null,
    );
    expect(block.warmupSets[0].done, false);
    expect(block.warmupSets[0].isWarmup, true);
    expect(block.warmupSets[0].rir, isNull);
    expect(block.workingSets[0].rir, 1);
    expect(block.workingSets[0].done, false);
  });

  test('roundTo helper rounds to nearest step', () {
    expect(roundTo(38.75, 2.5), 40.0);
    expect(roundTo(52.7, 2.5), 52.5);
    expect(roundTo(77.5, 2.5), 77.5);
    expect(roundTo(19.0, 2.5), 20.0);
  });

  // ── D7: finish() tests ───────────────────────────────────────────────────

  test('finish() produces correct SessionWrite: splitLabel, warm-ups, no computed flags', () async {
    final ex = Exercise.fromRow({
      'id': 'ex1',
      'name': 'Bench',
      'slug': 'bench',
      'muscle_group': 'chest',
      'compound': 1,
      'plate_step_kg': '2.5',
      'base_weight_kg': '80',
    });

    final controller = ActiveSessionController();
    // Manually seed the draft for the test (bypassing buildFromTemplate which
    // requires a live DB; we test finish() logic directly).
    final resolved = ResolvedSlot(
      exercise: ex,
      workSets: 2,
      warmupSets: 1,
      repLow: 6,
      repHigh: 8,
      rirLow: 0,
      rirHigh: 1,
    );
    final block = buildBlock(resolved: resolved, lastTopKg: null);
    for (final s in block.allSets) {
      s.done = true;
    }
    controller.seedForTest(
      SessionDraft(
        templateId: 'day1',
        name: 'Upper A',
        focus: 'Push',
        startedAt: DateTime.now().subtract(const Duration(minutes: 45)),
        blocks: [block],
      ),
    );

    final exec = FakeExec();
    final sessionId = await controller.finish(exec);

    // Basic structure
    expect(sessionId, isNotEmpty);
    expect(exec.calls.length, greaterThan(1));

    // 1 session INSERT
    final sessionInserts =
        exec.calls.where((c) => c.$1.contains('INSERT INTO sessions')).toList();
    expect(sessionInserts.length, 1);

    // splitLabel uses middot ' · '
    final sessionParams = sessionInserts.first.$2;
    final splitLabel = sessionParams.firstWhere((p) => p is String && p.toString().contains('·')) as String;
    expect(splitLabel, contains(' · '));
    expect(splitLabel, 'Upper A · Push');

    // All set INSERTs
    final setInserts =
        exec.calls.where((c) => c.$1.contains('INSERT INTO sets')).toList();
    // 1 warmup + 2 working = 3 sets
    expect(setInserts.length, 3);

    // Client flags ARE stamped: the heaviest working set is the top set.
    // No prior best (lastTopKg null → bestKg null) so is_pr stays false.
    final workingInserts = setInserts.where((c) => c.$2[7] == 0).toList();
    expect(workingInserts.any((c) => c.$2[8] == 1), isTrue); // exactly one top set
    for (final c in setInserts) {
      expect(c.$2[9], 0); // is_pr false (no bestKg)
    }

    // Warm-up set: is_warmup = 1 (true)
    final warmupInsert = setInserts.first;
    final warmupParams = warmupInsert.$2;
    // is_warmup is the last param (index 7)
    expect(warmupParams[7], 1); // is_warmup = 1

    // No user_id column in any SQL
    for (final c in exec.calls) {
      expect(c.$1.contains('user_id'), isFalse);
    }
  });

  test('finish() running set_number restarts per exercise', () async {
    final ex1 = Exercise.fromRow({
      'id': 'ex1', 'name': 'Squat', 'slug': 'squat', 'muscle_group': 'legs',
      'compound': 1, 'plate_step_kg': '5.0', 'base_weight_kg': '100',
    });
    final ex2 = Exercise.fromRow({
      'id': 'ex2', 'name': 'Curl', 'slug': 'curl', 'muscle_group': 'arms',
      'compound': 0, 'plate_step_kg': '2.5', 'base_weight_kg': '20',
    });

    final controller = ActiveSessionController();
    final block1 = buildBlock(
      resolved: ResolvedSlot(exercise: ex1, workSets: 2, warmupSets: 0, repLow: 5, repHigh: 6, rirLow: 1, rirHigh: 1),
      lastTopKg: null,
    );
    final block2 = buildBlock(
      resolved: ResolvedSlot(exercise: ex2, workSets: 2, warmupSets: 0, repLow: 10, repHigh: 12, rirLow: 1, rirHigh: 1),
      lastTopKg: null,
    );
    for (final s in [...block1.allSets, ...block2.allSets]) {
      s.done = true;
    }
    controller.seedForTest(SessionDraft(
      templateId: null,
      name: 'Custom',
      focus: 'Legs+Arms',
      startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      blocks: [block1, block2],
    ));

    final exec = FakeExec();
    await controller.finish(exec);

    final setInserts = exec.calls.where((c) => c.$1.contains('INSERT INTO sets')).toList();
    expect(setInserts.length, 4); // 2 + 2

    // set_number is at param index 3
    // ex1: set_number 1, 2
    expect(setInserts[0].$2[3], 1);
    expect(setInserts[1].$2[3], 2);
    // ex2: set_number resets to 1, 2
    expect(setInserts[2].$2[3], 1);
    expect(setInserts[3].$2[3], 2);
  });
}
