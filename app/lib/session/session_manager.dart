import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/active_session_draft.dart';
import 'active_session_controller.dart';
import 'workout_notification.dart';

/// App-scoped owner of the active workout. The session screen renders
/// [active]; minimizing the screen leaves the workout running here. Also the
/// single driver of the ongoing Android notification (when [notifier] is set).
class SessionManager extends ChangeNotifier with WidgetsBindingObserver {
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
  /// reconciled into the live controller on resume). Call once at startup.
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active?.removeListener(_onControllerChange);
    super.dispose();
  }
}
