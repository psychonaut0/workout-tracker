import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A tiny polyline sparkline, ported from `ui.jsx` → `Sparkline`.
///
/// Default size is 92×22 (wider than the JSX 64×24 to fit the stat-tile).
/// Returns [SizedBox.shrink] when fewer than 2 values are provided.
///
/// The [stroke] color defaults to `context.tokens.accent`; callers that want a
/// muted line (e.g. the bodyweight tile) pass `context.tokens.dim` explicitly.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.stroke,
    this.width = 92,
    this.height = 22,
  });

  final List<double> values;

  /// Stroke / fill colour. Defaults to [WorkoutTokens.accent].
  final Color? stroke;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final color = stroke ?? context.tokens.accent;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          stroke: color,
          canvasWidth: width,
          canvasHeight: height,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.stroke,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  final List<double> values;
  final Color stroke;
  final double canvasWidth;
  final double canvasHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = canvasWidth;
    final h = canvasHeight;
    final n = values.length;

    final lo = values.reduce(min);
    final hi = values.reduce(max);
    final sp = max(hi - lo, 0.001);

    double xOf(int i) => (i / (n - 1)) * w;
    double yOf(double v) => h - 2 - ((v - lo) / sp) * (h - 4);

    // Build polyline points.
    final points = [
      for (var i = 0; i < n; i++) Offset(xOf(i), yOf(values[i])),
    ];

    final linePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPoints(
      PointMode.polygon,
      points,
      linePaint,
    );

    // Filled dot at the last data point.
    final dotPaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(xOf(n - 1), yOf(values[n - 1])),
      2.0,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.stroke != stroke ||
      old.canvasWidth != canvasWidth ||
      old.canvasHeight != canvasHeight;
}
