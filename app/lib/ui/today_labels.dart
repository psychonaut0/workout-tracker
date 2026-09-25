import '../l10n/app_localizations.dart';

/// Today's header line: the date, then either the workout in progress or the
/// next day in rotation. Today follows the rotation only — the weekday
/// schedule never decides what comes next.
String todayHeaderLine(
  AppLocalizations l, {
  required String date,
  String? nextName,
  String? activeName,
}) {
  if (activeName != null) return '$date · $activeName';
  if (nextName != null) return '$date · ${l.todayNext(nextName)}';
  return date;
}

/// The sets tile's comparison with last week: "+5 vs last wk", "−8 vs last
/// wk" (U+2212), or "same as last wk".
String setsVsLastWeek(AppLocalizations l, int thisWeek, int lastWeek) {
  final d = thisWeek - lastWeek;
  if (d == 0) return l.todaySameAsLastWeek;
  return l.todayVsLastWeek(d > 0 ? '+$d' : '−${-d}');
}
