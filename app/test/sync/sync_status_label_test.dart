import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/sync/sync_status_label.dart';
import 'package:workout_tracker/sync/sync_status_ui.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 9, 29, 12);

  test('offline with a known last sync says when', () {
    expect(syncStatusLabel(l, SyncDotState.offline, now.subtract(const Duration(hours: 3)), now),
        'Offline · synced 3h ago');
  });
  test('offline with no known sync is just Offline', () {
    expect(syncStatusLabel(l, SyncDotState.offline, null, now), 'Offline');
  });
  test('error, syncing and synced keep their labels', () {
    expect(syncStatusLabel(l, SyncDotState.error, null, now), 'Sync error');
    expect(syncStatusLabel(l, SyncDotState.syncing, null, now), 'Syncing…');
    expect(syncStatusLabel(l, SyncDotState.synced, now.subtract(const Duration(minutes: 5)), now),
        'Synced · 5m ago');
    expect(syncStatusLabel(l, SyncDotState.synced, null, now), 'Synced');
  });
}
