import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/active_session_draft.dart';
import '../data/finished_session_store.dart';
import 'active_session_controller.dart';
import 'resume.dart';
import 'workout_notification.dart';

/// App-scoped owner of the active workout. The session screen renders
/// [active]; minimizing the screen leaves the workout running here. Also the
/// single driver of the ongoing Android notification (when [notifier] is set).
class SessionManager extends ChangeNotifier with WidgetsBindingObserver {
  SessionManager({FinishedSessionStore? finishedStore})
      : _finishedStore = finishedStore ?? FinishedSessionStore();

  ActiveSessionController? _active;
  ActiveSessionController? get active => _active;
  bool get hasActive => _active != null;

  /// Set by the session screen (initState/dispose) so the shell knows whether
  /// to show the mini-bar and entry points know whether to resume vs reopen.
  bool _screenOpen = false;
  bool get screenOpen => _screenOpen;
  set screenOpen(bool v) {
    if (v == _screenOpen) return;
    _screenOpen = v;
    notifyListeners();
  }

  /// Optional notification surface (null on Linux/tests).
  WorkoutNotification? notifier;

  /// Registers the app-lifecycle observer (so a background +30s tap is
  /// reconciled into the live controller, and the finished-workout snapshot
  /// re-checked against the wall clock, on resume). Call once at startup.
  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Foreground +30s from the notification chip while the app is alive — the
  /// live controller is the source of truth, so just extend it directly.
  void add30FromNotification() {
    _active?.addRestTime(30);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileRestFromBlob();
      _recheckFinished(DateTime.now());
    }
  }

  Future<void> _reconcileRestFromBlob() async {
    final c = _active;
    if (c == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // background +30s wrote disk; refresh the frozen cache
    final startMs = prefs.getInt(restBlobStartMs);
    final total = prefs.getInt(restBlobTotal);
    if (startMs != null && total != null) {
      final blobStart = DateTime.fromMillisecondsSinceEpoch(startMs);
      // A background +30s changed the blob but not the live controller.
      // Reconcile only when it's the same rest (same start) with a different
      // total.
      if (c.restStart != null &&
          c.restStart!.millisecondsSinceEpoch == startMs &&
          c.restTotal != total) {
        c.setRestRaw(blobStart, total);
      }
    }
    // If rest already elapsed (e.g. expired while backgrounded, screen closed),
    // reconcile the controller to stopped — the OS alarm reverted the notif but
    // nothing cleared the live controller.
    final rs = c.restStart;
    if (rs != null &&
        DateTime.now().isAfter(rs.add(Duration(seconds: c.restTotal)))) {
      c.stopRest();
    }
  }

  @visibleForTesting
  Future<void> reconcileForTest() => _reconcileRestFromBlob();

  void register(ActiveSessionController c) {
    assert(_active == null || identical(_active, c),
        'A workout is already active: check hasActive and take tryBeginLaunch first.');
    _active?.removeListener(_onControllerChange);
    _active = c;
    c.addListener(_onControllerChange);
    notifier?.showFor(
      name: c.draft.name,
      startedAt: c.draft.startedAt,
      restStart: c.restStart,
      restTotal: c.restTotal,
    );
    notifyListeners();
  }

  void _onControllerChange() {
    final c = _active;
    if (c == null) return;
    if (!c.hasSession) {
      // discard()/finish() nulled the draft — tear everything down.
      clear();
      return;
    }
    notifier?.showFor(
      name: c.draft.name,
      startedAt: c.draft.startedAt,
      restStart: c.restStart,
      restTotal: c.restTotal,
    );
    notifyListeners(); // mini-bar rest-mode swap
  }

  void clear() {
    _active?.removeListener(_onControllerChange);
    _active = null;
    notifier?.cancel();
    notifyListeners();
  }

  /// Boot path: restore a persisted draft (crash / process-death recovery).
  Future<bool> resumeFromDraft({DraftStore? store}) async {
    final s = store ?? DraftStore();
    final draft = await s.load();
    if (draft == null) return false;
    register(ActiveSessionController.fromDraft(draft, draftStore: s));
    return true;
  }

  // ── Launch guard ────────────────────────────────────────────────────────

  bool _launching = false;

  /// True while a start or resume is building its controller.
  bool get launching => _launching;

  /// Claims the single launch slot; false if a start or resume is already in
  /// flight (a double tap). Pair with [endLaunch] in a `finally`. Take it
  /// synchronously, before the first await, or two taps both get through and
  /// register two workouts.
  bool tryBeginLaunch() {
    if (_launching) return false;
    _launching = true;
    return true;
  }

  void endLaunch() => _launching = false;

  // ── Finished-workout snapshot ───────────────────────────────────────────

  final FinishedSessionStore _finishedStore;
  FinishedSession? _lastFinished;
  Timer? _expiry;

  /// The last workout finished on this device while it may still be resumed
  /// from History (see `resume.dart`); null otherwise.
  FinishedSession? get lastFinished => _lastFinished;

  /// Adopts [f] as the resumable snapshot and persists it.
  ///
  /// Call ONLY after the finish's write transaction has committed: `finish()`
  /// runs and notifies inside the transaction, before the commit, and
  /// adopting then would let a failed commit replace a good snapshot with one
  /// describing writes that never happened. A failed save clears the file, so
  /// an older snapshot of the same session cannot be resumed after a restart.
  Future<void> recordFinished(FinishedSession f, {DateTime? now}) async {
    _adopt(f, now ?? DateTime.now());
    notifyListeners();
    try {
      await _finishedStore.save(f);
    } catch (_) {
      await _clearFinishedStore();
    }
  }

  /// Boot path: restores the persisted snapshot if it is still resumable, and
  /// deletes it otherwise (or if it cannot be read).
  Future<void> loadLastFinished({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final FinishedSession? f;
    try {
      f = await _finishedStore.load();
    } catch (_) {
      return;
    }
    if (f == null) return;
    if (!isResumable(f, f.sessionId, t)) {
      await _clearFinishedStore();
      return;
    }
    _adopt(f, t);
    notifyListeners();
  }

  /// Drops the snapshot if it belongs to [sessionId] — the session was
  /// deleted, or its resume window closed.
  void forgetFinished(String sessionId) {
    if (_lastFinished?.sessionId != sessionId) return;
    _expiry?.cancel();
    _expiry = null;
    _lastFinished = null;
    notifyListeners();
    unawaited(_clearFinishedStore());
  }

  /// The expiry timer runs on the monotonic clock, which does not advance
  /// while the device sleeps: back in the foreground, re-check the snapshot
  /// against the wall clock, and re-arm the timer from it.
  void _recheckFinished(DateTime now) {
    final f = _lastFinished;
    if (f == null) return;
    if (!isResumable(f, f.sessionId, now)) {
      forgetFinished(f.sessionId);
    } else {
      _adopt(f, now); // same snapshot: nothing to notify
    }
  }

  /// Holds [f] and arms a one-shot timer for when it stops being resumable,
  /// so the Resume action disappears on its own.
  void _adopt(FinishedSession f, DateTime now) {
    _lastFinished = f;
    _expiry?.cancel();
    final wait = resumableUntil(f).difference(now);
    _expiry = Timer(wait.isNegative ? Duration.zero : wait,
        () => forgetFinished(f.sessionId));
  }

  Future<void> _clearFinishedStore() async {
    try {
      await _finishedStore.clear();
    } catch (_) {
      // Best effort: an undeletable stale file is dropped again at next boot.
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _active?.removeListener(_onControllerChange);
    super.dispose();
  }
}
