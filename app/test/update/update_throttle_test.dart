import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/update/update_service.dart';

void main() {
  test('shouldAutoCheck: needs enabled + >24h since last', () {
    const day = 24 * 60 * 60 * 1000;
    final now = DateTime(2026, 6, 9).millisecondsSinceEpoch;
    expect(shouldAutoCheck(enabled: false, lastCheckMs: 0, nowMs: now), isFalse);
    expect(shouldAutoCheck(enabled: true, lastCheckMs: 0, nowMs: now), isTrue);
    expect(shouldAutoCheck(enabled: true, lastCheckMs: now - day - 1, nowMs: now), isTrue);
    expect(shouldAutoCheck(enabled: true, lastCheckMs: now - 1000, nowMs: now), isFalse);
  });
}
