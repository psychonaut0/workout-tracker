// Date / relative-time helpers.
//
// Dart's DateTime.weekday: 1=Mon, 2=Tue, ..., 7=Sun  (ISO-8601).

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Returns the Monday 00:00 of the ISO week containing [d].
///
/// Dart weekday: 1=Mon .. 7=Sun → subtract (weekday-1) days.
DateTime weekStart(DateTime d) {
  final daysFromMonday = d.weekday - 1; // 0 for Mon, 6 for Sun
  return DateTime(d.year, d.month, d.day - daysFromMonday);
}

/// Formats [d] as a zero-padded ISO-8601 date string (`yyyy-MM-dd`).
///
/// MACHINE format — storage keys and inclusive string-compare range queries
/// depend on this exact shape. Never localize it.
String isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// A locale-independent bucket describing how long ago a date was.
///
/// `kind` is one of `today` / `yesterday` / `days` / `weeks`; `count` carries
/// the day or week magnitude for the `days` / `weeks` buckets (0 otherwise).
/// The widget layer maps this to a localized ARB string via [localizedDaysAgo].
typedef RelativeDay = ({String kind, int count});

/// Buckets how long ago [iso] was relative to [now] (date-only comparison).
///
/// [now] defaults to [DateTime.now()].
///
/// * <=0 days → today
/// * 1 day    → yesterday
/// * <7 days  → days (count = n)
/// * else     → weeks (count = n÷7)
RelativeDay daysAgo(String iso, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final d = DateTime.parse('${iso}T00:00:00');
  final pastDate = DateTime(d.year, d.month, d.day);
  final diff = todayDate.difference(pastDate).inDays;
  if (diff <= 0) return (kind: 'today', count: 0);
  if (diff == 1) return (kind: 'yesterday', count: 0);
  if (diff < 7) return (kind: 'days', count: diff);
  return (kind: 'weeks', count: diff ~/ 7);
}

/// Localized "how long ago" label for [iso] — "today" / "yesterday" /
/// "{n}d ago" / "{n}w ago" in the active locale.
String localizedDaysAgo(AppLocalizations l, String iso, {DateTime? now}) {
  final r = daysAgo(iso, now: now);
  switch (r.kind) {
    case 'today':
      return l.sessionToday;
    case 'yesterday':
      return l.sessionYesterday;
    case 'weeks':
      return l.sessionWeeksAgo(r.count);
    default:
      return l.sessionDaysAgo(r.count);
  }
}

/// Short localized weekday name for a 0-based Monday-origin index.
///
/// [mon0] must be in 0..6 (0=Mon, 6=Sun). [localeName] is an intl locale name
/// such as `'en'`, `'it'`, `'de'`, `'es'`. Output is `DateFormat.E`-shaped
/// (e.g. "Mon" / "lun" / "Mo" / "lun").
String weekdayShort(int mon0, String localeName) {
  // Anchor on a known Monday (2024-01-01) and add the Monday-origin offset so
  // DateFormat.E resolves the localized short name without an arbitrary date.
  final date = DateTime(2024, 1, 1).add(Duration(days: mon0));
  return DateFormat.E(localeName).format(date);
}

/// Formats an ISO date string as a localized display date.
///
/// With [weekday]=true: `'Ddd D Mmm'` (e.g. en `'Sun 31 May'`).
/// Without: `'D Mmm'` (e.g. `'31 May'`).
///
/// Day-before-month order is preserved across locales (matching the prior
/// hand-rolled formatter); only the weekday and month NAMES are localized via
/// [localeName] (`'en'` / `'it'` / `'de'` / `'es'`).
String fmtDate(String iso, String localeName, {bool weekday = false}) {
  final d = DateTime.parse('${iso}T00:00:00');
  final pattern = weekday ? 'E d MMM' : 'd MMM';
  return DateFormat(pattern, localeName).format(d);
}
