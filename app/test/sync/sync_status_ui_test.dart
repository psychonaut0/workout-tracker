import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/sync/sync_status_ui.dart';

void main() {
  final now = DateTime(2026, 6, 3, 12, 0);

  group('syncDotStateFor', () {
    test('error wins over everything', () {
      expect(
        syncDotStateFor(
            connected: true, syncing: true, hasError: true),
        SyncDotState.error,
      );
    });
    test('syncing while connected', () {
      expect(
        syncDotStateFor(connected: true, syncing: true, hasError: false),
        SyncDotState.syncing,
      );
    });
    test('idle connected', () {
      expect(
        syncDotStateFor(connected: true, syncing: false, hasError: false),
        SyncDotState.synced,
      );
    });
    test('disconnected', () {
      expect(
        syncDotStateFor(connected: false, syncing: false, hasError: false),
        SyncDotState.offline,
      );
    });
  });

  group('syncLabelFor', () {
    test('syncing', () {
      expect(syncLabelFor(SyncDotState.syncing, null, now), 'Syncing…');
    });
    test('error', () {
      expect(syncLabelFor(SyncDotState.error, null, now), 'Sync error');
    });
    test('offline', () {
      expect(syncLabelFor(SyncDotState.offline, null, now), 'Offline');
    });
    test('synced with no timestamp', () {
      expect(syncLabelFor(SyncDotState.synced, null, now), 'Synced');
    });
    test('synced just now', () {
      expect(
        syncLabelFor(
            SyncDotState.synced, now.subtract(const Duration(seconds: 30)), now),
        'Synced · just now',
      );
    });
    test('synced minutes ago', () {
      expect(
        syncLabelFor(
            SyncDotState.synced, now.subtract(const Duration(minutes: 5)), now),
        'Synced · 5m ago',
      );
    });
    test('synced hours ago', () {
      expect(
        syncLabelFor(
            SyncDotState.synced, now.subtract(const Duration(hours: 3)), now),
        'Synced · 3h ago',
      );
    });
    test('synced days ago shows date', () {
      expect(
        syncLabelFor(
            SyncDotState.synced, DateTime(2026, 5, 30, 9, 0), now),
        'Synced · 30/5',
      );
    });
  });
}
