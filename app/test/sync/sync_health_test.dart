// SyncStatus's constructor is @internal but is the only way to fake a status.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/sync_health.dart';

void main() {
  final now = DateTime(2026, 9, 29, 12);
  late StreamController<SyncStatus> status;
  late int pending;
  late bool syncOn;
  late ValueNotifier<int> settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    status = StreamController<SyncStatus>.broadcast();
    pending = 2;
    syncOn = true;
    settings = ValueNotifier(0);
  });
  tearDown(() => status.close());

  SyncHealth health({SyncStatus initial = const SyncStatus()}) => SyncHealth(
        status: status.stream,
        initial: initial,
        pendingChanges: () async => pending,
        signedIn: () => true,
        syncEnabled: () => syncOn,
        settings: settings,
        clock: () => now,
      );

  test('an old last sync with pending changes is at risk; a new status event recomputes', () async {
    final h = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(days: 5))));
    await h.start();
    expect(h.atRisk, isTrue);
    status.add(SyncStatus(connected: true, lastSyncedAt: now));
    await pumpEventQueue();
    expect(h.atRisk, isFalse);
    expect(h.lastSyncedAt, now);
    h.dispose();
  });

  test('a persisted last sync survives a null status', () async {
    final h1 = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(hours: 2))));
    await h1.start();
    h1.dispose();
    final h2 = health(); // after a restart, offline: PowerSync reports no time
    await h2.start();
    expect(h2.lastSyncedAt, now.subtract(const Duration(hours: 2)));
    expect(h2.atRisk, isFalse);
    h2.dispose();
  });

  test('turning sync off recomputes', () async {
    final h = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(days: 5))));
    await h.start();
    expect(h.atRisk, isTrue);
    syncOn = false;
    settings.value++;
    await pumpEventQueue();
    expect(h.atRisk, isFalse);
    h.dispose();
  });

  test('dispose cancels the subscription', () async {
    final h = health();
    await h.start();
    h.dispose();
    expect(status.hasListener, isFalse);
  });

  test('repeated identical status events do not notify; a newer sync does', () async {
    final h = health(initial: SyncStatus(lastSyncedAt: now));
    await h.start();
    var n = 0;
    h.addListener(() => n++);
    status.add(SyncStatus(connected: true, lastSyncedAt: now));
    status.add(SyncStatus(connected: true, lastSyncedAt: now));
    await pumpEventQueue();
    expect(n, 0);
    final newer = now.add(const Duration(minutes: 1));
    status.add(SyncStatus(connected: true, lastSyncedAt: newer));
    await pumpEventQueue();
    expect(n, 1);
    expect(h.lastSyncedAt, newer);
    h.dispose();
  });

  test('clear() forgets the last sync, in memory and on disk', () async {
    final h1 = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(hours: 2))));
    await h1.start();
    var n = 0;
    h1.addListener(() => n++);
    // After logout PowerSync has no time for the next account either.
    status.add(const SyncStatus());
    await pumpEventQueue();
    await h1.clear();
    expect(h1.lastSyncedAt, isNull);
    expect(n, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('sync.last_synced_at_ms'), isNull);
    h1.dispose();
    final h2 = health(); // the next account, before its first sync
    await h2.start();
    expect(h2.lastSyncedAt, isNull);
    h2.dispose();
  });

  test('clear() ignores a status that still reports the old time; a newer sync shows', () async {
    final old = now.subtract(const Duration(hours: 2));
    final h = health(initial: SyncStatus(lastSyncedAt: old));
    await h.start();
    await h.clear(); // PowerSync's status has not caught up yet
    expect(h.lastSyncedAt, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('sync.last_synced_at_ms'), isNull);
    status.add(SyncStatus(connected: true, lastSyncedAt: now));
    await pumpEventQueue();
    expect(h.lastSyncedAt, now);
    h.dispose();
  });
}
