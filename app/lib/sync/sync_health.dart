import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_status_ui.dart';

/// App-wide sync health for Today's data-at-risk card and Profile's
/// "Offline · synced …". Owns one subscription to the PowerSync status
/// stream and remembers the last sync time itself, because PowerSync may
/// report none after a restart until it connects again.
class SyncHealth extends ChangeNotifier {
  SyncHealth({
    required Stream<SyncStatus> status,
    required SyncStatus initial,
    required Future<int> Function() pendingChanges,
    required bool Function() signedIn,
    required bool Function() syncEnabled,
    Listenable? settings,
    DateTime Function()? clock,
    Duration poll = const Duration(minutes: 5),
  })  : _statusStream = status,
        _status = initial,
        _pendingChanges = pendingChanges,
        _signedIn = signedIn,
        _syncEnabled = syncEnabled,
        _settings = settings,
        _clock = clock ?? DateTime.now,
        _poll = poll;

  static const _prefsKey = 'sync.last_synced_at_ms';

  final Stream<SyncStatus> _statusStream;
  final Future<int> Function() _pendingChanges;
  final bool Function() _signedIn;
  final bool Function() _syncEnabled;
  final Listenable? _settings;
  final DateTime Function() _clock;
  final Duration _poll;

  SyncStatus _status;
  StreamSubscription<SyncStatus>? _sub;
  Timer? _timer;
  DateTime? _saved;
  bool _atRisk = false;
  bool _disposed = false;

  bool get atRisk => _atRisk;

  /// The newest of PowerSync's time and the one remembered here.
  DateTime? get lastSyncedAt {
    final live = _status.lastSyncedAt;
    final saved = _saved;
    if (live == null) return saved;
    if (saved == null) return live;
    return live.isAfter(saved) ? live : saved;
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefsKey);
    _saved = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    _sub = _statusStream.listen((s) {
      _status = s;
      recompute();
    });
    _settings?.addListener(recompute);
    _timer = Timer.periodic(_poll, (_) => recompute());
    await recompute();
  }

  Future<void> recompute() async {
    final live = _status.lastSyncedAt;
    if (live != null && (_saved == null || live.isAfter(_saved!))) {
      _saved = live;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, live.millisecondsSinceEpoch);
    }
    final pending = await _pendingChanges();
    if (_disposed) return;
    final next = syncAtRisk(
      signedIn: _signedIn(),
      syncEnabled: _syncEnabled(),
      connected: _status.connected,
      pendingChanges: pending,
      lastSyncedAt: lastSyncedAt,
      now: _clock(),
    );
    if (next != _atRisk) {
      _atRisk = next;
      notifyListeners();
    } else if (live != null) {
      notifyListeners(); // Profile shows the new time
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _timer?.cancel();
    _settings?.removeListener(recompute);
    super.dispose();
  }
}
