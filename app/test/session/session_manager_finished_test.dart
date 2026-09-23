import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/util/dates.dart';

import '../support/fake_stores.dart';

class _NoopExec implements SqlExecutor {
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {}
}

FinishedSession fin({String id = 'S', String date = '2026-09-23', DateTime? at}) => FinishedSession(
      sessionId: id,
      sessionDate: date,
      finishedAt: at ?? DateTime(2026, 9, 23, 10, 0),
      elapsedSeconds: 2400,
      draft: SessionDraft(
        templateId: null, name: 'Upper A', focus: '',
        startedAt: DateTime(2026, 9, 23, 9, 20), blocks: [],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordFinished adopts, notifies and persists the snapshot', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    var notifies = 0;
    m.addListener(() => notifies++);
    final f = fin();

    final pending = m.recordFinished(f, now: f.finishedAt);
    expect(m.lastFinished, same(f)); // adopted before the first await
    await pending;
    expect(notifies, 1);
    expect(store.stored, same(f));
  });

  test('a failed save clears the store, so an older snapshot cannot survive', () async {
    final store = FakeFinishedSessionStore(stored: fin(at: DateTime(2026, 9, 23, 9, 0)), failSave: true);
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    final f = fin();
    await m.recordFinished(f, now: f.finishedAt);
    expect(store.stored, isNull);
    expect(store.clearCount, 1);
    expect(m.lastFinished, same(f)); // still resumable in this process
  });

  test('finishing a registered controller alone adopts nothing', () async {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    final c = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
    m.register(c);
    await c.finish(_NoopExec());
    expect(c.lastFinished, isNotNull);
    expect(m.lastFinished, isNull);
    expect(m.hasActive, isFalse);
  });

  test('loadLastFinished keeps a resumable snapshot', () async {
    final f = fin();
    final m = SessionManager(finishedStore: FakeFinishedSessionStore(stored: f));
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 23, 18, 0));
    expect(m.lastFinished?.sessionId, 'S');
  });

  test('loadLastFinished drops and deletes an expired snapshot', () async {
    final store = FakeFinishedSessionStore(stored: fin());
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 25, 8, 0));
    expect(m.lastFinished, isNull);
    expect(store.stored, isNull);
  });

  test('loadLastFinished survives a store that throws', () async {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore(failLoad: true));
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 23, 10, 5));
    expect(m.lastFinished, isNull);
  });

  test('forgetFinished drops only a matching session, and notifies', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    final f = fin();
    await m.recordFinished(f, now: f.finishedAt);
    var notifies = 0;
    m.addListener(() => notifies++);

    m.forgetFinished('other');
    expect(m.lastFinished, same(f));
    expect(notifies, 0);

    m.forgetFinished('S');
    await Future<void>.delayed(Duration.zero);
    expect(m.lastFinished, isNull);
    expect(notifies, 1);
    expect(store.stored, isNull);
  });

  testWidgets('the snapshot is forgotten when its window closes', (tester) async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    // Finished 23:50 → resumable until 00:50 (grace past midnight).
    final f = fin(date: '2026-09-23', at: DateTime(2026, 9, 23, 23, 50));
    await m.recordFinished(f, now: f.finishedAt);

    await tester.pump(const Duration(minutes: 59));
    expect(m.lastFinished, isNotNull);
    await tester.pump(const Duration(minutes: 2));
    expect(m.lastFinished, isNull);
    expect(store.stored, isNull);
    m.dispose();
  });

  test('back in the foreground, a snapshot whose window closed while asleep is forgotten', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    // Adopted "then": its expiry timer is armed for hours, and a suspended
    // device's monotonic clock would not have advanced it.
    final at = DateTime.now().subtract(const Duration(days: 3));
    final f = fin(date: isoDate(at), at: at);
    await m.recordFinished(f, now: f.finishedAt);
    expect(m.lastFinished, same(f));

    m.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(m.lastFinished, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(store.stored, isNull);
  });

  test('back in the foreground, a snapshot still in its window is kept', () async {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    final at = DateTime.now();
    final f = fin(date: isoDate(at), at: at);
    await m.recordFinished(f, now: f.finishedAt);

    m.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(m.lastFinished, same(f));
  });

  test('tryBeginLaunch refuses a second launch until endLaunch', () {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    expect(m.tryBeginLaunch(), isTrue);
    expect(m.launching, isTrue);
    expect(m.tryBeginLaunch(), isFalse);
    m.endLaunch();
    expect(m.launching, isFalse);
    expect(m.tryBeginLaunch(), isTrue);
  });

  test('register refuses a second controller while one is active', () {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    final a = ActiveSessionController()..seedEmpty(name: 'A', focus: '');
    final b = ActiveSessionController()..seedEmpty(name: 'B', focus: '');
    m.register(a);
    m.register(a); // re-registering the same controller is harmless
    expect(() => m.register(b), throwsAssertionError);
  });
}
