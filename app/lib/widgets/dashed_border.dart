import 'dart:math' show min;

import 'package:flutter/material.dart';

/// Paints a dashed rounded-rectangle border (6px dashes, 4px gaps, 1px stroke,
/// inset by half the stroke). [radius] is the corner radius — the only thing
/// that varied between the previously-duplicated copies in split_tab,
/// day_editor and split_card.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _stroke = 1.0;
  static const double _dash = 6.0;
  static const double _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _stroke / 2,
        _stroke / 2,
        size.width - _stroke,
        size.height - _stroke,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
