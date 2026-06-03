/// Pure presentation mapping for the Profile sync-status row.
/// Kept free of PowerSync types so it is trivially testable.
library;

enum SyncDotState { syncing, synced, offline, error }

/// Maps raw connection facts to a dot state. Error wins; then syncing;
/// then connected-idle; else offline.
SyncDotState syncDotStateFor({
  required bool connected,
  required bool syncing,
  required bool hasError,
}) {
  if (hasError) return SyncDotState.error;
  if (connected && syncing) return SyncDotState.syncing;
  if (connected) return SyncDotState.synced;
  return SyncDotState.offline;
}

/// Human label for a dot state. [lastSyncedAt] only matters for `synced`.
String syncLabelFor(SyncDotState state, DateTime? lastSyncedAt, DateTime now) {
  switch (state) {
    case SyncDotState.syncing:
      return 'Syncing…';
    case SyncDotState.error:
      return 'Sync error';
    case SyncDotState.offline:
      return 'Offline';
    case SyncDotState.synced:
      if (lastSyncedAt == null) return 'Synced';
      return 'Synced · ${relativeTime(lastSyncedAt, now)}';
  }
}

/// "just now" / "Xm ago" / "Xh ago" / "d/M" (older than a day).
String relativeTime(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${t.day}/${t.month}';
}
