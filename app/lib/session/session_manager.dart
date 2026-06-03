import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/active_session_draft.dart';
import 'active_session_controller.dart';
import 'workout_notification.dart';

/// App-scoped owner of the active workout. The session screen renders
/// [active]; minimizing the screen leaves the workout running here. Also the
/// single driver of the ongoing Android notification (when [notifier] is set).
class SessionManager extends ChangeNotifier {
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

  /// Stops the rest automatically when it expires while the screen is closed
  /// (with the screen open, its ticker handles this; stopRest is guarded).
  Timer? _restExpiry;

  void register(ActiveSessionController c) {
    _restExpiry?.cancel(); // defensive: never let a stale timer poke a new session
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
    _armRestExpiry(c);
    notifier?.showFor(
      name: c.draft.name,
      startedAt: c.draft.startedAt,
      restStart: c.restStart,
      restTotal: c.restTotal,
    );
    notifyListeners(); // mini-bar rest-mode swap
  }

  void _armRestExpiry(ActiveSessionController c) {
    _restExpiry?.cancel();
    final start = c.restStart;
    if (start == null) return;
    final remaining =
        start.add(Duration(seconds: c.restTotal)).difference(DateTime.now());
    _restExpiry = Timer(
      remaining.isNegative ? Duration.zero : remaining + const Duration(seconds: 1),
      c.stopRest, // guarded no-op if already stopped
    );
  }

  void clear() {
    _restExpiry?.cancel();
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
    _restExpiry?.cancel();
    _active?.removeListener(_onControllerChange);
    super.dispose();
  }
}
