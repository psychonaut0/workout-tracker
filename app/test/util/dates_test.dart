import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/dates.dart';

void main() {
  test('weekStart returns the Monday 00:00 of the given date', () {
    // 2026-05-31 is a Sunday → week started Mon 2026-05-25
    expect(isoDate(weekStart(DateTime(2026, 5, 31))), '2026-05-25');
    // 2026-05-25 is a Monday → itself
    expect(isoDate(weekStart(DateTime(2026, 5, 25, 14))), '2026-05-25');
  });
  test('daysAgo labels', () {
    final now = DateTime(2026, 5, 31);
    expect(daysAgo('2026-05-31', now: now), 'today');
    expect(daysAgo('2026-05-30', now: now), 'yesterday');
    expect(daysAgo('2026-05-28', now: now), '3d ago');
    expect(daysAgo('2026-05-10', now: now), '3w ago');
  });
  test('weekdayShort: 0=Mon .. 6=Sun', () {
    expect(weekdayShort(0), 'Mon');
    expect(weekdayShort(6), 'Sun');
  });
  test('fmtDate', () {
    expect(fmtDate('2026-05-31', weekday: true), 'Sun 31 May');
    expect(fmtDate('2026-05-25', weekday: true), 'Mon 25 May'); // non-Sunday: catches a wrong weekday offset
    expect(fmtDate('2026-05-31'), '31 May');
  });
}
