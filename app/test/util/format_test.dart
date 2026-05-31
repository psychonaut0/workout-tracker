import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/format.dart';
import 'package:workout_tracker/data/models.dart';

void main() {
  group('fmtPlain', () {
    test('whole number returns bare integer', () {
      expect(fmtPlain(80), '80');
      expect(fmtPlain(80.0), '80');
    });
    test('fractional returns 1dp, no trailing .0', () {
      expect(fmtPlain(72.5), '72.5');
    });
  });

  group('fmtThousands', () {
    test('comma-groups thousands', () {
      expect(fmtThousands(12500), '12,500');
    });
    test('values under 1000 have no comma', () {
      expect(fmtThousands(900), '900');
    });
  });

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
