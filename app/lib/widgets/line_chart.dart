import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';

/// A progression line chart ported from `ui.jsx` `LineChart`.
///
/// Renders a [CustomPaint] with area-fill gradient, polyline, PR markers,
/// month x-labels, and a floating value label at the last point. Falls back
/// to an empty [SizedBox] when `series.length < 2`.
///
/// Series values are already in display units — callers convert.
/// Each record includes a [date] (ISO-8601 date string, e.g. '2024-03-15')
/// used to derive month boundary x-labels, mirroring `ui.jsx` `s.date`.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.height = 210,
    required this.unit,
    this.showReps = true,
  });

  final List<({String date, double value, int reps, bool isPr})> series;
  final double height;
  final String unit;
  final bool showReps;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) return SizedBox(height: height);

    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _LineChartPainter(
            series: series,
            unit: unit,
            showReps: showReps,
            accent: tokens.accent,
            bg: tokens.bg,
            faint: tokens.faint,
            text: tokens.text,
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.unit,
    required this.showReps,
    required this.accent,
    required this.bg,
    required this.faint,
    required this.text,
  });

  final List<({String date, double value, int reps, bool isPr})> series;
  final String unit;
  final bool showReps;
  final Color accent;
  final Color bg;
  final Color faint;
  final Color text;

  // Padding constants (ported from ui.jsx pad object)
  static const double _padT = 18;
  static const double _padR = 16;
  static const double _padB = 26;
  static const double _padL = 34;

  // Month abbreviations — mirrors MONTHS array in ui.jsx
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final iw = W - _padL - _padR;
    final ih = H - _padT - _padB;
    final n = series.length;

    // ── y-domain ──────────────────────────────────────────────────────────────
    final values = series.map((s) => s.value).toList();
    var lo = values.reduce(min);
    var hi = values.reduce(max);
    final span = max(hi - lo, 4.0);
    lo -= span * 0.18;
    hi += span * 0.22;

    double xAt(int i) => _padL + (i / (n - 1)) * iw;
    double yAt(double v) => _padT + ih - ((v - lo) / (hi - lo)) * ih;

    // ── 5 gridlines + left y labels ───────────────────────────────────────────
    // ticks=4 produces 5 lines (i = 0..4), matching ui.jsx grid (ticks+1 items)
    const ticks = 4;
    final gridPaint = Paint()
      ..color = faint.withValues(alpha: 0.18)
      ..strokeWidth = 1;

    for (var i = 0; i <= ticks; i++) {
      final gv = lo + ((hi - lo) / ticks) * i;
      final gy = yAt(gv);

      canvas.drawLine(Offset(_padL, gy), Offset(W - _padR, gy), gridPaint);

      _paintText(
        canvas,
        text: '${gv.round()}',
        x: _padL - 7,
        y: gy + 3.5,
        rightAlign: true,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 9,
          color: faint,
        ),
      );
    }

    // ── area-fill gradient (vertical: accent@0.22 → accent@0) ─────────────────
    final areaPath = Path()..moveTo(xAt(0), _padT + ih);
    for (var i = 0; i < n; i++) {
      areaPath.lineTo(xAt(i), yAt(series[i].value));
    }
    areaPath
      ..lineTo(xAt(n - 1), _padT + ih)
      ..close();

    final areaGradient = ui.Gradient.linear(
      Offset(0, _padT),
      Offset(0, _padT + ih),
      [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0)],
    );
    canvas.drawPath(areaPath, Paint()..shader = areaGradient);

    // ── polyline — accent stroke w2.4 round ───────────────────────────────────
    final linePath = Path()..moveTo(xAt(0), yAt(series[0].value));
    for (var i = 1; i < n; i++) {
      linePath.lineTo(xAt(i), yAt(series[i].value));
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = accent
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // ── per-point dots (skip last — handled separately) ───────────────────────
    for (var i = 0; i < n - 1; i++) {
      final cx = xAt(i);
      final cy = yAt(series[i].value);

      if (series[i].isPr) {
        // PR: r4.5 accent fill + bg-color halo stroke w2
        canvas.drawCircle(Offset(cx, cy), 4.5, Paint()..color = accent);
        canvas.drawCircle(
          Offset(cx, cy),
          4.5,
          Paint()
            ..color = bg
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      } else {
        // Mid dot: r2.2 accent@0.55
        canvas.drawCircle(
          Offset(cx, cy),
          2.2,
          Paint()..color = accent.withValues(alpha: 0.55),
        );
      }
    }

    // ── month x-labels at month boundaries ────────────────────────────────────
    // Mirrors ui.jsx: track lastM, emit label on first point of each new month.
    var lastM = -1;
    for (var i = 0; i < n; i++) {
      final dateStr = series[i].date;
      // Parse month from ISO date string (yyyy-MM-dd); avoid DateTime.parse for
      // performance and to match the ui.jsx `new Date(s.date+'T00:00:00')` approach.
      final m = dateStr.length >= 7 ? int.tryParse(dateStr.substring(5, 7)) : null;
      if (m != null && m != lastM) {
        lastM = m;
        final monthLabel = _months[(m - 1).clamp(0, 11)];
        _paintText(
          canvas,
          text: monthLabel,
          x: xAt(i),
          y: H - 8,
          rightAlign: false,
          centreAlign: true,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            color: faint,
          ),
        );
      }
    }

    // ── last point: r9 accent@0.16 halo + r4.5 dot + floating value label ─────
    final last = series[n - 1];
    final lastX = xAt(n - 1);
    final lastY = yAt(last.value);

    // r9 halo
    canvas.drawCircle(
      Offset(lastX, lastY),
      9,
      Paint()..color = accent.withValues(alpha: 0.16),
    );
    // r4.5 accent dot + bg-color halo stroke w2
    canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = accent);
    canvas.drawCircle(
      Offset(lastX, lastY),
      4.5,
      Paint()
        ..color = bg
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Floating value label — translate(min(lastX, W-58), max(lastY-26, 4))
    final label =
        '${fmtPlain(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}';
    final labelX = min(lastX, W - 58);
    final labelY = max(lastY - 26, 4.0);

    _paintText(
      canvas,
      text: label,
      x: labelX,
      y: labelY,
      rightAlign: false,
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    );
  }

  /// Paints [text] at logical position ([x], [y]).
  ///
  /// Alignment options (only one should be true at a time):
  /// - [rightAlign]: right edge of the text box at [x] (SVG `textAnchor="end"`)
  /// - [centreAlign]: horizontal centre of the text box at [x]
  ///   (SVG `textAnchor="middle"`)
  /// - neither: left edge at [x].
  ///
  /// The vertical centre of the text box is always placed at [y].
  void _paintText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required bool rightAlign,
    bool centreAlign = false,
    required TextStyle style,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final double dx;
    if (rightAlign) {
      dx = x - tp.width;
    } else if (centreAlign) {
      dx = x - tp.width / 2;
    } else {
      dx = x;
    }
    tp.paint(canvas, Offset(dx, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(_LineChartPainter old) {
    return old.series != series ||
        old.unit != unit ||
        old.showReps != showReps ||
        old.accent != accent ||
        old.bg != bg ||
        old.faint != faint ||
        old.text != text;
  }
}
