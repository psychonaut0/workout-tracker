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

  group('relativeTimeBucket', () {
    test('just now (< 1 minute)', () {
      expect(
        relativeTimeBucket(now.subtract(const Duration(seconds: 30)), now),
        const RelativeTimeBucket(RelativeTimeKind.justNow),
      );
    });
    test('minutes ago carries the minute count', () {
      expect(
        relativeTimeBucket(now.subtract(const Duration(minutes: 5)), now),
        const RelativeTimeBucket(RelativeTimeKind.minutes, value: 5),
      );
    });
    test('hours ago carries the hour count', () {
      expect(
        relativeTimeBucket(now.subtract(const Duration(hours: 3)), now),
        const RelativeTimeBucket(RelativeTimeKind.hours, value: 3),
      );
    });
    test('older than a day carries the date', () {
      final t = DateTime(2026, 5, 30, 9, 0);
      expect(
        relativeTimeBucket(t, now),
        RelativeTimeBucket(RelativeTimeKind.date, date: t),
      );
    });
    test('exactly 1 minute is minutes, not just now', () {
      expect(
        relativeTimeBucket(now.subtract(const Duration(minutes: 1)), now).kind,
        RelativeTimeKind.minutes,
      );
    });
    test('exactly 24 hours falls into date', () {
      expect(
        relativeTimeBucket(now.subtract(const Duration(hours: 24)), now).kind,
        RelativeTimeKind.date,
      );
    });
  });
}
