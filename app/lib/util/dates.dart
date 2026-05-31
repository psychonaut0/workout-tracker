// Date / relative-time helpers.
//
// Dart's DateTime.weekday: 1=Mon, 2=Tue, ..., 7=Sun  (ISO-8601).

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Returns the Monday 00:00 of the ISO week containing [d].
///
/// Dart weekday: 1=Mon .. 7=Sun → subtract (weekday-1) days.
DateTime weekStart(DateTime d) {
  final daysFromMonday = d.weekday - 1; // 0 for Mon, 6 for Sun
  return DateTime(d.year, d.month, d.day - daysFromMonday);
}

/// Formats [d] as a zero-padded ISO-8601 date string (`yyyy-MM-dd`).
String isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Returns a human-readable label for how long ago [iso] was.
///
/// [now] defaults to [DateTime.now()]; comparisons are date-only.
///
/// * <=0 days → 'today'
/// * 1 day    → 'yesterday'
/// * <7 days  → '{n}d ago'
/// * else     → '{n÷7}w ago'
String daysAgo(String iso, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final d = DateTime.parse('${iso}T00:00:00');
  final pastDate = DateTime(d.year, d.month, d.day);
  final diff = todayDate.difference(pastDate).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'yesterday';
  if (diff < 7) return '${diff}d ago';
  return '${diff ~/ 7}w ago';
}

/// Converts a 0-based Monday-origin index to a short weekday name.
///
/// [mon0] must be in 0..6 (0=Mon, 6=Sun).
String weekdayShort(int mon0) => _weekdays[mon0];

/// Formats an ISO date string as a display date.
///
/// With [weekday]=true: `'Ddd D Mmm'` (e.g. `'Sun 31 May'`).
/// Without: `'D Mmm'` (e.g. `'31 May'`).
///
/// The weekday is derived via `weekdayShort(DateTime.parse(iso).weekday - 1)`.
/// The `-1` is required: Dart's weekday is 1=Mon..7=Sun; subtracting 1 gives
/// a 0-based Monday-origin index suitable for [weekdayShort] (Sunday→6, not 7).
String fmtDate(String iso, {bool weekday = false}) {
  final d = DateTime.parse('${iso}T00:00:00');
  final month = _months[d.month - 1];
  if (weekday) {
    final wd = weekdayShort(d.weekday - 1);
    return '$wd ${d.day} $month';
  }
  return '${d.day} $month';
}
