import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/util/dates.dart';

void main() {
  setUpAll(() async {
    // DateFormat for non-system locales needs the symbol tables loaded.
    await initializeDateFormatting();
  });

  test('weekStart returns the Monday 00:00 of the given date', () {
    // 2026-05-31 is a Sunday → week started Mon 2026-05-25
    expect(isoDate(weekStart(DateTime(2026, 5, 31))), '2026-05-25');
    // 2026-05-25 is a Monday → itself
    expect(isoDate(weekStart(DateTime(2026, 5, 25, 14))), '2026-05-25');
  });
  test('daysAgo buckets', () {
    final now = DateTime(2026, 5, 31);
    expect(daysAgo('2026-05-31', now: now), (kind: 'today', count: 0));
    expect(daysAgo('2026-05-30', now: now), (kind: 'yesterday', count: 0));
    expect(daysAgo('2026-05-28', now: now), (kind: 'days', count: 3));
    expect(daysAgo('2026-05-10', now: now), (kind: 'weeks', count: 3));
  });
  test('weekdayShort: 0=Mon .. 6=Sun (en)', () {
    expect(weekdayShort(0, 'en'), 'Mon');
    expect(weekdayShort(6, 'en'), 'Sun');
  });
  test('fmtDate (en) keeps day-before-month order', () {
    expect(fmtDate('2026-05-31', 'en', weekday: true), 'Sun 31 May');
    // non-Sunday: catches a wrong weekday offset
    expect(fmtDate('2026-05-25', 'en', weekday: true), 'Mon 25 May');
    expect(fmtDate('2026-05-31', 'en'), '31 May');
  });
}
