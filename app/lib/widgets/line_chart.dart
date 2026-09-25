import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../util/format.dart';

/// Each ISO date's position in [0, 1] between the first and last date, so a
/// chart's x spacing reflects time rather than entry order. Equal dates share
/// an x. When every date is the same (or there is one point) the points are
/// spaced evenly by index instead; an unparseable date also falls back to its
/// index fraction. Tolerates unsorted input (extremes are found, not assumed).
List<double> dateFractions(List<String> isoDates) {
  final n = isoDates.length;
  if (n == 1) return const [0];
  double byIndex(int i) => i / (n - 1);
  // Calendar days in UTC, so a daylight-saving change can't make a day 23 or
  // 25 hours long.
  final days = isoDates.map((d) {
    final p = DateTime.tryParse(d);
    return p == null ? null : DateTime.utc(p.year, p.month, p.day);
  }).toList();
  final valid = days.whereType<DateTime>().toList();
  if (valid.length < 2) return [for (var i = 0; i < n; i++) byIndex(i)];
  final first = valid.reduce((a, b) => a.isBefore(b) ? a : b);
  final last = valid.reduce((a, b) => a.isAfter(b) ? a : b);
  final span = last.difference(first).inHours;
  if (span == 0) return [for (var i = 0; i < n; i++) byIndex(i)];
  return [
    for (var i = 0; i < n; i++)
      days[i] == null ? byIndex(i) : days[i]!.difference(first).inHours / span,
  ];
}

/// Where to put the chart's last-point value label so it never covers the
/// line: right of [point] if it fits, else left. When [previous] is given,
/// place the chip on the vertical side opposite the incoming segment direction
/// — below the point if the segment comes from above, above if from below —
/// flipping to the other side if that overflows the canvas. Always clamped
/// inside [canvas].
Offset valueLabelOrigin({
  required Offset point,
  required Size label,
  required Size canvas,
  double gap = 8,
  Offset? previous,
}) {
  // Horizontal: right if it fits, else left.
  var x = point.dx + gap;
  if (x + label.width > canvas.width) x = point.dx - gap - label.width;

  // Vertical: when previous is given, place on the side opposite the incoming
  // segment. If the previous point is above (dy < point.dy), place below;
  // otherwise above. If that overflows, use the other side.
  var y = point.dy - gap - label.height; // Default: above
  if (previous != null) {
    if (previous.dy < point.dy) {
      // Segment comes from above; prefer below.
      y = point.dy + gap;
      if (y + label.height > canvas.height) {
        // Overflow; try above instead.
        y = point.dy - gap - label.height;
      }
    } else {
      // Segment comes from below; prefer above.
      y = point.dy - gap - label.height;
      if (y < 0) {
        // Overflow; try below instead.
        y = point.dy + gap;
      }
    }
  } else {
    // No previous: use the original logic (above, drop to below if overflow).
    if (y < 0) y = point.dy + gap;
  }

  return Offset(
    x.clamp(0.0, math.max(0.0, canvas.width - label.width)),
    y.clamp(0.0, math.max(0.0, canvas.height - label.height)),
  );
}

/// A progression line chart ported from `ui.jsx` `LineChart`.
///
/// Renders a [CustomPaint] with area-fill gradient, polyline, PR markers,
/// month x-labels, and a value label on a chip beside the last point. Falls back
/// to an empty [SizedBox] when `series.length < 2`.
///
/// Series values are already in display units — callers convert.
/// Each record includes a [date] (ISO-8601 date string, e.g. '2024-03-15')
/// used to space the x-axis by calendar time (not entry index) and to derive
/// month boundary x-labels, mirroring `ui.jsx` `s.date`.
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
    final localeName = Localizations.localeOf(context).toLanguageTag();
    return LayoutBuilder(
      builder: (context, constraints) {
        return MountProgress(
          duration: const Duration(milliseconds: 450),
          builder: (_, t) => CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _LineChartPainter(
              series: series,
              unit: unit,
              showReps: showReps,
              accent: tokens.accent,
              bg: tokens.bg,
              faint: tokens.faint,
              text: tokens.text,
              localeName: localeName,
              progress: t,
            ),
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
    required this.localeName,
    this.progress = 1.0,
  });

  final List<({String date, double value, int reps, bool isPr})> series;
  final String unit;
  final bool showReps;
  final Color accent;
  final Color bg;
  final Color faint;
  final Color text;

  /// BCP-47 locale tag used to format month abbreviations on the x-axis.
  final String localeName;

  /// One-shot mount progress 0→1. Axes/grid/labels render fully from t=0;
  /// only the data line, area fill, and point dots draw in. At 1.0 the render
  /// is identical to a static chart.
  final double progress;

  // Padding constants (ported from ui.jsx pad object)
  static const double _padT = 18;
  static const double _padR = 16;
  static const double _padB = 26;
  static const double _padL = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final iw = W - _padL - _padR;
    final ih = H - _padT - _padB;
    final n = series.length;

    // ── y-domain ──────────────────────────────────────────────────────────────
    final values = series.map((s) => s.value).toList();
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    final span = math.max(hi - lo, 4.0);
    lo -= span * 0.18;
    hi += span * 0.22;

    final fractions = dateFractions([for (final s in series) s.date]);
    double xAt(int i) => _padL + fractions[i] * iw;
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
      // Fade the fill in with progress so it never pops; identical at t=1.
      [
        accent.withValues(alpha: 0.22 * progress),
        accent.withValues(alpha: 0),
      ],
    );
    canvas.drawPath(areaPath, Paint()..shader = areaGradient);

    // ── polyline — accent stroke w2.4 round ───────────────────────────────────
    final linePath = Path()..moveTo(xAt(0), yAt(series[0].value));
    for (var i = 1; i < n; i++) {
      linePath.lineTo(xAt(i), yAt(series[i].value));
    }
    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // Stroke the line on by progress fraction of its arc length. At t=1 the
    // extracted path equals the full path, so the render is unchanged.
    for (final m in linePath.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), linePaint);
    }

    // ── per-point dots (skip last — handled separately) ───────────────────────
    for (var i = 0; i < n - 1; i++) {
      // Reveal each dot once the stroke has reached its x-fraction.
      if (fractions[i] > progress) continue;

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
        final monthLabel = DateFormat.MMM(localeName).format(DateTime(2024, m));
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
    // The endpoint sits at x-fraction 1.0, so only reveal it once the stroke
    // has fully arrived (avoids the dot + label floating ahead of the line).
    if (progress < 1.0) return;

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

    // Value label on a small chip beside the last point — placed so it never
    // covers the line's final segment.
    final label =
        '${fmtPlain(last.value)}$unit${showReps ? ' ×${last.reps}' : ''}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const chipPad = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final chipSize = Size(tp.width + chipPad.horizontal, tp.height + chipPad.vertical);
    final prevX = xAt(n - 2);
    final prevY = yAt(series[n - 2].value);
    final origin = valueLabelOrigin(
      point: Offset(lastX, lastY),
      label: chipSize,
      canvas: size,
      gap: 10,
      previous: Offset(prevX, prevY),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(origin & chipSize, const Radius.circular(6)),
      Paint()..color = bg,
    );
    tp.paint(canvas, origin + Offset(chipPad.left, chipPad.top));
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
    return old.progress != progress ||
        old.series != series ||
        old.unit != unit ||
        old.showReps != showReps ||
        old.accent != accent ||
        old.bg != bg ||
        old.faint != faint ||
        old.text != text ||
        old.localeName != localeName;
  }
}
