import 'dates.dart';

/// Groups [items] by ISO week key (the Monday of the week, formatted as an
/// ISO date string).
///
/// [dateOf] extracts the ISO date string from each item.
/// Returns a map keyed by `isoDate(weekStart(DateTime.parse(dateOf(item))))`,
/// preserving insertion order (dart LinkedHashMap).
Map<String, List<T>> groupByWeek<T>(List<T> items, String Function(T) dateOf) {
  final result = <String, List<T>>{};
  for (final item in items) {
    final key = isoDate(weekStart(DateTime.parse(dateOf(item))));
    (result[key] ??= []).add(item);
  }
  return result;
}
