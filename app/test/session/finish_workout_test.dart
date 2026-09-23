import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/shell/session_launcher.dart';

import '../support/fake_stores.dart';

class _NoopExec implements SqlExecutor {
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {}
}

FinishedSession previous() => FinishedSession(
      sessionId: 'P',
      sessionDate: '2026-09-23',
      finishedAt: DateTime(2026, 9, 23, 10, 0),
      elapsedSeconds: 2400,
      draft: SessionDraft(
        templateId: null, name: 'Upper A', focus: '',
        startedAt: DateTime(2026, 9, 23, 9, 20), blocks: [],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a committed finish hands its snapshot to the manager', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    final c = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
    m.register(c);

    final id = await finishWorkout(c, m, transact: (body) => body(_NoopExec()));

    expect(m.lastFinished, same(c.lastFinished));
    expect(m.lastFinished!.sessionId, id);
    await Future<void>.delayed(Duration.zero);
    expect(store.stored?.sessionId, id);
    expect(m.hasActive, isFalse);
  });

  test('a commit that fails after finish() keeps the previous snapshot', () async {
    final p = previous();
    final store = FakeFinishedSessionStore(stored: p);
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    await m.recordFinished(p, now: p.finishedAt);
    final c = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
    m.register(c);

    await expectLater(
      finishWorkout(c, m, transact: (body) async {
        await body(_NoopExec());
        throw StateError('commit failed');
      }),
      throwsStateError,
    );

    expect(c.lastFinished, isNotNull); // finish() itself ran to completion
    expect(m.lastFinished, same(p));
    await Future<void>.delayed(Duration.zero);
    expect(store.stored, same(p));
  });

  test('without a manager the finish still returns its session id', () async {
    final c = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
    final id = await finishWorkout(c, null, transact: (body) => body(_NoopExec()));
    expect(id, c.lastFinished!.sessionId);
  });
}
