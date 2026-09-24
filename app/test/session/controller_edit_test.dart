import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

class _RecordingExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

Exercise _ex(String id, {double step = 2.5}) => Exercise(
      id: id, name: id, slug: id, muscleGroup: 'chest',
      compound: true, plateStepKg: step, isTemplate: false,
    );

SetState _set(String id, double w, {bool warmup = false, bool done = false, int reps = 5}) =>
    SetState(id: id, weightKg: w, reps: reps, rir: warmup ? null : 1, isWarmup: warmup, done: done);

BlockState _block(String exId, {List<SetState>? warm, List<SetState>? work, double step = 2.5}) {
  final e = _ex(exId, step: step);
  return BlockState(
    exercise: e,
    resolved: ResolvedSlot(exercise: e, workSets: 3, warmupSets: 1, repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2),
    warmupSets: warm ?? [],
    workingSets: work ?? [],
    expanded: true,
  );
}

ActiveSessionController _seeded(List<BlockState> blocks) => ActiveSessionController()
  ..seedForTest(SessionDraft(
    templateId: null, name: 'Upper A', focus: '',
    startedAt: DateTime.now().subtract(const Duration(minutes: 30)), blocks: blocks,
  ));

void main() {
  group('removeSet', () {
    test('removes a working set and notifies', () {
      final b = _block('bench', work: [_set('s1', 100), _set('s2', 100)]);
      final c = _seeded([b]);
      var notifies = 0;
      c.addListener(() => notifies++);
      c.removeSet(b, b.workingSets.first);
      expect(b.workingSets.map((s) => s.id), ['s2']);
      expect(notifies, 1);
    });

    test('removes a warm-up set', () {
      final b = _block('bench', warm: [_set('w1', 40, warmup: true)], work: [_set('s1', 100)]);
      final c = _seeded([b]);
      c.removeSet(b, b.warmupSets.single);
      expect(b.warmupSets, isEmpty);
      expect(b.workingSets.single.id, 's1');
    });

    test('a removed done set is not written at finish, and set numbers stay contiguous', () async {
      final b = _block('bench', work: [_set('s1', 100, done: true), _set('s2', 95, done: true), _set('s3', 95, done: true)]);
      final c = _seeded([b]);
      c.removeSet(b, b.workingSets[1]);
      final exec = _RecordingExec();
      await c.finish(exec);
      final sets = exec.calls.where((call) => call.$1.startsWith('INSERT INTO sets')).toList();
      expect(sets.map((call) => call.$2[0]), ['s1', 's3']);
      expect(sets.map((call) => call.$2[3]), [1, 2]);
    });
  });

  group('addWarmupSet', () {
    test('the first warm-up is half the first working weight, 8 reps, unticked', () {
      final b = _block('bench', work: [_set('s1', 100), _set('s2', 100)]);
      final c = _seeded([b]);
      var notifies = 0;
      c.addListener(() => notifies++);
      c.addWarmupSet(b);
      final w = b.warmupSets.single;
      expect(w.isWarmup, isTrue);
      expect(w.weightKg, 50);
      expect(w.reps, 8);
      expect(w.rir, isNull);
      expect(w.done, isFalse);
      expect(notifies, 1);
    });

    test('later warm-ups follow the ramp, rounded to the plate step', () {
      final b = _block('bench', warm: [_set('w1', 50, warmup: true, reps: 8)], work: [_set('s1', 100)]);
      final c = _seeded([b]);
      c.addWarmupSet(b);
      c.addWarmupSet(b);
      expect(b.warmupSets.map((s) => s.weightKg), [50, 67.5, 85]);
      expect(b.warmupSets.map((s) => s.reps), [8, 6, 4]);
      expect(b.warmupSets.map((s) => s.id).toSet().length, 3);
    });

    test('a warm-up never exceeds the working weight', () {
      final b = _block('bench',
          warm: [for (var i = 0; i < 4; i++) _set('w$i', 50, warmup: true)], work: [_set('s1', 100)]);
      final c = _seeded([b]);
      c.addWarmupSet(b); // ramp step 4 → 1.22 × 100
      expect(b.warmupSets.last.weightKg, 100);
      expect(b.warmupSets.last.reps, 1);
    });

    test('with no working sets the ramp is based on the exercise seed', () {
      final b = _block('curl');
      final c = _seeded([b]);
      c.addWarmupSet(b);
      // No base weight → the 20 kg floor used for new sets, plus one plate for a
      // compound (22.5); half of that rounded to the 2.5 plate step is 12.5.
      expect(b.warmupSets.single.weightKg, 12.5);
    });
  });

  group('moveBlock', () {
    late BlockState a, b, d;
    late ActiveSessionController c;
    setUp(() {
      a = _block('a');
      b = _block('b');
      d = _block('d');
      c = _seeded([a, b, d]);
    });

    test('moves a block down and up and notifies', () {
      var notifies = 0;
      c.addListener(() => notifies++);
      c.moveBlock(a, 1);
      expect(c.draft.blocks.map((x) => x.exercise.id), ['b', 'a', 'd']);
      c.moveBlock(d, -1);
      expect(c.draft.blocks.map((x) => x.exercise.id), ['b', 'd', 'a']);
      expect(notifies, 2);
    });

    test('is a no-op past either end', () {
      var notifies = 0;
      c.addListener(() => notifies++);
      c.moveBlock(a, -1);
      c.moveBlock(d, 1);
      expect(c.draft.blocks.map((x) => x.exercise.id), ['a', 'b', 'd']);
      expect(notifies, 0);
    });

    test('the finished workout keeps the new order', () async {
      a.workingSets.add(_set('sa', 50, done: true));
      d.workingSets.add(_set('sd', 50, done: true));
      c.moveBlock(d, -2);
      final exec = _RecordingExec();
      await c.finish(exec);
      final sets = exec.calls.where((call) => call.$1.startsWith('INSERT INTO sets')).map((call) => call.$2[0]);
      expect(sets, ['sd', 'sa']);
      expect(c.lastFinished!.draft.blocks.map((x) => x.exercise.id), ['d', 'a', 'b']);
    });
  });
}
