import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/number_input.dart';

void main() {
  group('clampRound2', () {
    test('rounds to two decimals', () {
      expect(clampRound2(1.005), 1.01);
      expect(clampRound2(72.4999), 72.5);
    });
    test('applies the floor', () {
      expect(clampRound2(-4), 0);
      expect(clampRound2(-4, min: 1), 1);
    });
    test('applies the ceiling', () {
      expect(clampRound2(150, max: 99), 99);
      expect(clampRound2(40, min: 0, max: 40), 40);
    });
  });

  group('parseNumberInput', () {
    test('parses a plain number', () {
      expect(parseNumberInput('92.5'), 92.5);
    });
    test('accepts a comma decimal separator', () {
      expect(parseNumberInput('12,5'), 12.5);
    });
    test('trims surrounding whitespace', () {
      expect(parseNumberInput('  8 '), 8);
    });
    test('returns null for text that is not a number', () {
      expect(parseNumberInput('abc'), isNull);
      expect(parseNumberInput('1.2.3'), isNull);
    });
    test('empty text yields emptyValue when given, else null', () {
      expect(parseNumberInput('', emptyValue: 0), 0);
      expect(parseNumberInput('   ', emptyValue: 0), 0);
      expect(parseNumberInput(''), isNull);
    });
    test('clamps to min and max', () {
      expect(parseNumberInput('150', min: 1, max: 99), 99);
      expect(parseNumberInput('0', min: 1, max: 99), 1);
      expect(parseNumberInput('-4'), 0);
    });
    test('applies parseDisplay before clamping', () {
      // Display space is double the caller space.
      expect(parseNumberInput('250', parseDisplay: (d) => d / 2), 125);
    });
    test('parseDisplay result is still clamped', () {
      expect(parseNumberInput('400', max: 99, parseDisplay: (d) => d / 2), 99);
    });
  });
}
