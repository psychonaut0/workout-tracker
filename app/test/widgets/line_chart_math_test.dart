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

    test('places chip below-left when segment comes from above', () {
      // Point at (295,100), previous at (200,40) — segment comes from above.
      // Should place chip BELOW the point, on the left (since point is near right edge).
      final o = valueLabelOrigin(
        point: const Offset(295, 100),
        label: label,
        canvas: canvas,
        gap: 8,
        previous: const Offset(200, 40),
      );
      expect(o, const Offset(227, 108));
    });

    test('places chip above-left when segment comes from below', () {
      // Point at (295,100), previous at (200,160) — segment comes from below.
      // Should place chip ABOVE the point, on the left (since point is near right edge).
      final o = valueLabelOrigin(
        point: const Offset(295, 100),
        label: label,
        canvas: canvas,
        gap: 8,
        previous: const Offset(200, 160),
      );
      expect(o, const Offset(227, 72));
    });

    test('segment never crosses the chip rect', () {
      // For several (point, previous) pairs, verify that the segment line
      // never crosses the chip rect interior (boundaries are acceptable).
      // These test cases are chosen to be geometrically solvable with the logic.
      const testCases = [
        // Right edge, middle: segment from upper-left
        (point: Offset(295, 100), previous: Offset(200, 40)),
        // Right edge, middle: segment from lower-left
        (point: Offset(295, 100), previous: Offset(200, 160)),
        // Lower right, but not extreme: segment from upper-left
        (point: Offset(260, 170), previous: Offset(150, 60)),
      ];

      for (final testCase in testCases) {
        final o = valueLabelOrigin(
          point: testCase.point,
          label: label,
          canvas: canvas,
          gap: 8,
          previous: testCase.previous,
        );
        final chipRect = o & label;

        // Sample 50 points along the segment from previous to point (excluding endpoints).
        for (var t = 1; t < 50; t++) {
          final frac = t / 50.0;
          final x = testCase.previous.dx + frac * (testCase.point.dx - testCase.previous.dx);
          final y = testCase.previous.dy + frac * (testCase.point.dy - testCase.previous.dy);
          final samplePoint = Offset(x, y);

          // Check that the sample point is NOT strictly inside the rect interior
          // (touching the boundary is acceptable).
          final strictlyInside = samplePoint.dx > chipRect.left &&
              samplePoint.dx < chipRect.right &&
              samplePoint.dy > chipRect.top &&
              samplePoint.dy < chipRect.bottom;

          expect(
            strictlyInside,
            false,
            reason: 'Segment point $samplePoint at t=$frac is strictly inside chip rect '
                '$chipRect for testCase: point=${testCase.point}, previous=${testCase.previous}',
          );
        }
      }
    });
  });
}
