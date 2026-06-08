/// Pure presentation mapping for the Profile sync-status row.
/// Kept free of PowerSync types AND of localized strings so it is trivially
/// testable; the widget turns these pure values into ARB-backed labels.
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

/// Which relative-time phrasing a timestamp falls into.
enum RelativeTimeKind { justNow, minutes, hours, date }

/// Pure bucketing of a timestamp into a relative-time phrasing. The widget
/// renders the localized string from [kind] + [value]/[date]:
///   • [justNow] → "just now"
///   • [minutes] → "{value}m ago"  (value = whole minutes elapsed)
///   • [hours]   → "{value}h ago"  (value = whole hours elapsed)
///   • [date]    → "d/M"           (use [date])
class RelativeTimeBucket {
  const RelativeTimeBucket(this.kind, {this.value = 0, this.date});

  final RelativeTimeKind kind;

  /// Minutes (for [minutes]) or hours (for [hours]); 0 otherwise.
  final int value;

  /// The original timestamp, only meaningful for [date].
  final DateTime? date;

  @override
  bool operator ==(Object other) =>
      other is RelativeTimeBucket &&
      other.kind == kind &&
      other.value == value &&
      other.date == date;

  @override
  int get hashCode => Object.hash(kind, value, date);

  @override
  String toString() =>
      'RelativeTimeBucket($kind, value: $value, date: $date)';
}

/// "just now" / "Xm ago" / "Xh ago" / "d/M" (older than a day) as pure buckets.
RelativeTimeBucket relativeTimeBucket(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return const RelativeTimeBucket(RelativeTimeKind.justNow);
  if (d.inHours < 1) {
    return RelativeTimeBucket(RelativeTimeKind.minutes, value: d.inMinutes);
  }
  if (d.inHours < 24) {
    return RelativeTimeBucket(RelativeTimeKind.hours, value: d.inHours);
  }
  return RelativeTimeBucket(RelativeTimeKind.date, date: t);
}
