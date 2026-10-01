import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';

void main() {
  group('est1rm', () {
    test('Epley formula rounds correctly', () {
      // 100 * (1 + 5/30) = 116.666... → 117
      expect(est1rm(100, 5), 117);
    });
    test('1 rep returns the weight itself', () {
      expect(est1rm(100, 1), (100 * (1 + 1 / 30)).round());
    });
  });
}
