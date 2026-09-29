import '../l10n/app_localizations.dart';
import 'sync_status_ui.dart';

/// The Profile sync row's text for [state]. Offline and synced carry the
/// last sync time when it is known.
String syncStatusLabel(
    AppLocalizations l, SyncDotState state, DateTime? lastSyncedAt, DateTime now) {
  switch (state) {
    case SyncDotState.syncing:
      return l.syncSyncing;
    case SyncDotState.error:
      return l.syncError;
    case SyncDotState.offline:
      if (lastSyncedAt == null) return l.syncOffline;
      return l.syncOfflineSince(relativeSyncTime(l, lastSyncedAt, now));
    case SyncDotState.synced:
      if (lastSyncedAt == null) return l.syncSynced;
      return l.syncSyncedAt(relativeSyncTime(l, lastSyncedAt, now));
  }
}

/// "just now" / "5m ago" / "3h ago" / "4/9" for [t].
String relativeSyncTime(AppLocalizations l, DateTime t, DateTime now) {
  final b = relativeTimeBucket(t, now);
  return switch (b.kind) {
    RelativeTimeKind.justNow => l.syncJustNow,
    RelativeTimeKind.minutes => l.syncMinutesAgo(b.value),
    RelativeTimeKind.hours => l.syncHoursAgo(b.value),
    RelativeTimeKind.date => l.syncDateShort(b.date!.day, b.date!.month),
  };
}
