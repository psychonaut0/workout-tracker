import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/line_chart.dart';

void main() {
  group('dateFractions', () {
    test('positions points by date, not by index', () {
      final f = dateFractions(['2026-06-01', '2026-06-02', '2026-06-11']);
      expect(f[0], 0);
      expect(f[1], closeTo(0.1, 1e-9));
      expect(f[2], 1);
    });

    test('points on the same date share an x', () {
      final f = dateFractions(['2026-06-01', '2026-06-05', '2026-06-05', '2026-06-09']);
      expect(f[1], f[2]);
      expect(f[1], closeTo(0.5, 1e-9));
    });

    test('all dates equal falls back to even spacing by index', () {
      expect(dateFractions(['2026-06-01', '2026-06-01', '2026-06-01']), [0, 0.5, 1]);
    });

    test('an unparseable date falls back to its index fraction', () {
      final f = dateFractions(['2026-06-01', 'garbage', '2026-06-03']);
      expect(f[1], closeTo(0.5, 1e-9));
    });

    test('a single point sits at 0', () {
      expect(dateFractions(['2026-06-01']), [0]);
    });
  });

  group('valueLabelOrigin', () {
    const canvas = Size(300, 200);
    const label = Size(60, 20);

    test('prefers above-right of the point', () {
      final o = valueLabelOrigin(point: const Offset(100, 100), label: label, canvas: canvas);
      expect(o, const Offset(108, 72));
    });

    test('flips to the left when it would overflow the right edge', () {
      final o = valueLabelOrigin(point: const Offset(290, 100), label: label, canvas: canvas);
      expect(o.dx, 290 - 8 - 60);
      expect(o.dy, 72);
    });

    test('drops below the point when it would overflow the top', () {
      final o = valueLabelOrigin(point: const Offset(100, 10), label: label, canvas: canvas);
      expect(o.dy, 10 + 8);
    });

    test('never leaves the canvas', () {
      final o = valueLabelOrigin(point: const Offset(295, 5), label: label, canvas: canvas);
      expect(o.dx, inInclusiveRange(0, canvas.width - label.width));
      expect(o.dy, inInclusiveRange(0, canvas.height - label.height));
    });
  });
}
