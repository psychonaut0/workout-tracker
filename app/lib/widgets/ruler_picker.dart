import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';
import '../util/number_input.dart';

/// Friction of the fling projection (the fraction of velocity left after one
/// second): lower stops sooner.
const double kFlingDrag = 0.08;

/// Release speeds up to this many dp/s count as a placement, not a fling:
/// the tape settles on the nearest value instead of travelling on. Faster
/// releases fling with only the excess speed, so a careful release never
/// jumps a value.
const double kFlingDeadZone = 300;

/// The longest glide after a fling.
const Duration kMaxGlide = Duration(milliseconds: 1200);

/// The value grid behind a [RulerPicker]: `base + i * step` for
/// `i in [0, count)`, anchored so [anchor] is always exactly on it. A value
/// off the plain step grid (101 kg on a 2.5 kg plate step, from history or
/// typing) therefore shows as itself instead of being rounded, and the tape
/// moves in steps from there.
class RulerScale {
  RulerScale({
    required double anchor,
    required double step,
    required double min,
    required double max,
  }) : step = step > 0 ? step : 1 {
    // A non-positive step (a bad plate_step_kg row) would divide by zero;
    // fall back to 1 rather than render an error.
    final top = math.max(max, anchor);
    final lo = math.min(min, anchor);
    // Walk down from the anchor to the lowest grid value still >= lo.
    final below = ((anchor - lo) / this.step + 1e-9).floor();
    base = clampRound2(anchor - below * this.step, min: double.negativeInfinity);
    count = ((top - base) / this.step + 1e-9).floor() + 1;
  }

  final double step;
  late final double base;
  late final int count;

  double get first => valueAt(0);
  double get last => valueAt(count - 1);

  double valueAt(int i) =>
      clampRound2(base + i.clamp(0, count - 1) * step, min: double.negativeInfinity);

  int indexOf(double v) => ((v - base) / step).round().clamp(0, count - 1);

  /// The grid value nearest [v], clamped to the ends of the tape.
  double snap(double v) => valueAt(indexOf(v));
}

/// A horizontal measuring-tape number picker: values sit in a row, a swipe
/// moves the tape (a fling moves many values), and on release it snaps so a
/// value sits under the centre marker. The centre value is the selected one —
/// large and accent-coloured — and neighbours shrink and fade with distance.
///
/// Values are in the caller's space (kg for weight); [format] renders them.
/// [onChanged] fires once per value that crosses the centre, never for a
/// value the parent handed in, so an external change (typed entry, undo)
/// re-centres the tape without echoing back. Tapping the centre value calls
/// [onTapValue] (typed entry).
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.value,
    required this.step,
    required this.format,
    required this.onChanged,
    this.min = 0,
    required this.max,
    this.itemExtent = defaultItemExtent,
    this.fineStep,
    this.onTapValue,
    this.semanticLabel,
  });

  static const double defaultItemExtent = 72;

  static final Set<RulerPickerState> _mounted = {};

  /// Stops every ruler that is still gliding after a fling, exactly on the
  /// value it currently shows. Call before anything acts on the values (the
  /// log bar, switching the live set): otherwise the glide keeps writing
  /// into a set after the tap — one tick after logging it, in practice.
  static void settleAll() {
    for (final r in _mounted) {
      r.settle();
    }
  }

  final double value;

  /// The distance between neighbouring values on the tape.
  final double step;

  /// A finer step for precise adjustments; not used yet.
  final double? fineStep;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final double min;

  /// Upper end of the tape; it grows to include [value] when that is higher.
  final double max;

  /// The on-screen distance between neighbouring values.
  final double itemExtent;
  final VoidCallback? onTapValue;
  final String? semanticLabel;

  @override
  State<RulerPicker> createState() => RulerPickerState();
}

@visibleForTesting
class RulerPickerState extends State<RulerPicker> with SingleTickerProviderStateMixin {
  late RulerScale scale;

  /// The last value this picker reported or was handed; a rebuild carrying
  /// it is not an external change.
  late double _current;

  /// The value under the centre marker, continuous while the tape moves.
  late double _pos;

  /// Drives the glide after a release (and the screen-reader nudges).
  late final AnimationController _glide;

  /// True from the start of a horizontal drag until its end; cleared early
  /// when [settle] halts the tape under the finger.
  bool _dragging = false;

  final _labels = _LabelCache();

  static const double _height = 80;

  /// The value under the centre marker.
  @visibleForTesting
  double get position => _pos;

  double get _pxPerValue => widget.itemExtent / scale.step;

  @override
  void initState() {
    super.initState();
    _current = widget.value;
    _pos = widget.value;
    scale = _scaleFor(widget.value);
    _glide = AnimationController.unbounded(vsync: this)
      ..addListener(_onGlideTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _onRest();
      });
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    RulerPicker._mounted.add(this);
  }

  RulerScale _scaleFor(double anchor) =>
      RulerScale(anchor: anchor, step: widget.step, min: widget.min, max: widget.max);

  /// Whether [v] is the value the picker already holds, give or take the
  /// floating-point noise of a unit round trip in the parent.
  bool _same(double v) => (v - _current).abs() <= scale.step * 0.02;

  /// Halts a glide on the value last reported; see [RulerPicker.settleAll].
  /// Synchronous, and reports nothing.
  void settle() {
    if (!mounted) return;
    _glide.stop();
    _dragging = false;
    if (_pos == _current) return;
    setState(() => _pos = _current);
  }

  @override
  void didUpdateWidget(RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stepChanged = widget.step != oldWidget.step;
    if (!stepChanged && _same(widget.value)) return;
    _glide.stop();
    _dragging = false;
    _current = widget.value;
    if (stepChanged || scale.snap(widget.value) != widget.value) {
      scale = _scaleFor(widget.value);
    }
    _pos = widget.value;
  }

  @override
  void dispose() {
    RulerPicker._mounted.remove(this);
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _glide.dispose();
    _labels.dispose();
    super.dispose();
  }

  void _onFontsChanged() {
    // Cached labels were laid out with the fonts available then; a font that
    // finished loading since must re-measure them.
    _labels.clear();
    if (mounted) setState(() {});
  }

  /// Reports the grid value under the centre when it differs from the last
  /// one reported — and every value in between, in order, when one frame
  /// carried the tape past several.
  void _reportCentre() {
    final to = scale.indexOf(_pos);
    if (scale.valueAt(to) == _current) return;
    final from = scale.indexOf(_current);
    final dir = to > from ? 1 : -1;
    HapticFeedback.selectionClick();
    // from == to when the last value sat just off this grid (floating-point
    // noise from the parent): then only the grid value itself is new.
    for (var i = from == to ? to : from + dir; ; i += dir) {
      _current = scale.valueAt(i);
      widget.onChanged(_current);
      if (i == to) break;
    }
  }

  void _moveTo(double p) {
    setState(() => _pos = p.clamp(scale.first, scale.last));
    _reportCentre();
  }

  void _onGlideTick() => _moveTo(_glide.value);

  /// The tape came to rest after a glide.
  void _onRest() {}

  /// Moves the tape to [target], a grid value, easing out from the release
  /// speed [pxPerSecond] (positive = up the tape) when it is a fling.
  void _glideTo(double target, {double pxPerSecond = 0}) {
    _glide.stop();
    final distancePx = (target - _pos) * _pxPerValue;
    var duration = Motion.of(context, Motion.base);
    if (duration == Duration.zero || distancePx.abs() < 0.01) {
      _moveTo(target);
      _onRest();
      return;
    }
    final sameWay = distancePx.sign == pxPerSecond.sign;
    if (sameWay && pxPerSecond.abs() > kFlingDeadZone) {
      // An ease-out cubic starts at 3× its average speed: pick the duration
      // that starts the glide at the release speed, so the hand-off is smooth.
      final ms = 3000 * distancePx.abs() / pxPerSecond.abs();
      duration = Duration(
          milliseconds: ms.clamp(duration.inMilliseconds.toDouble(), kMaxGlide.inMilliseconds.toDouble()).round());
    }
    _glide.value = _pos;
    _glide.animateTo(target, duration: duration, curve: Motion.curve);
  }

  void _onPointerDown(PointerDownEvent e) {
    // A finger on the tape catches a glide where it is.
    if (_glide.isAnimating) _glide.stop();
  }

  void _onPointerUp(PointerEvent e) {
    // A touch that never became a drag (a tap, or a vertical scroll that won
    // the gesture) still leaves the tape on a value.
    if (_dragging || _glide.isAnimating) return;
    final target = scale.snap(_pos);
    if (target != _pos) _glideTo(target);
  }

  void _onDragStart(DragStartDetails d) {
    _glide.stop();
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    // A leftward swipe moves up the tape.
    _moveTo(_pos - d.primaryDelta! / _pxPerValue);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final pxPerSecond = -(d.primaryVelocity ?? 0);
    var projectedPx = 0.0;
    if (pxPerSecond.abs() > kFlingDeadZone) {
      final excess = pxPerSecond.sign * (pxPerSecond.abs() - kFlingDeadZone);
      projectedPx = FrictionSimulation(kFlingDrag, 0, excess).finalX;
    }
    _glideTo(scale.snap(_pos + projectedPx / _pxPerValue), pxPerSecond: pxPerSecond);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _glideTo(scale.snap(_pos));
  }

  void _nudge(int delta) {
    _glideTo(scale.valueAt(scale.indexOf(_current) + delta));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final extent = widget.itemExtent;
    final i = scale.indexOf(_current);
    _labels.configure(
      text: tokens.text,
      accent: tokens.accent,
      scaler: MediaQuery.textScalerOf(context),
    );

    final tape = CustomPaint(
      painter: _TapePainter(
        position: _pos,
        scale: scale,
        pxPerValue: _pxPerValue,
        extent: extent,
        format: widget.format,
        line: tokens.lineStrong,
        labels: _labels,
      ),
    );

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.format(_current),
      increasedValue: widget.format(scale.valueAt(i + 1)),
      decreasedValue: widget.format(scale.valueAt(i - 1)),
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      onTap: widget.onTapValue,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Like a scroll view, the tape starts moving once the finger
            // has travelled the touch slop, not from touch-down.
            dragStartBehavior: DragStartBehavior.start,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
            // No frame of its own: the values sit on the host surface over
            // one ruled edge, so the tape reads as part of the card it lives
            // in.
            child: SizedBox(
              height: _height,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Fade the tape out at both ends.
                  SizedBox.expand(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      // Fully clear for the outer 6% so the ruled edge
                      // dissolves before it meets the host card's border.
                      shaderCallback: (rect) => const LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: [0, 0.06, 0.3, 0.7, 0.94, 1],
                      ).createShader(rect),
                      child: tape,
                    ),
                  ),
                  // Fixed centre marker, rising from the ruled edge under the
                  // selected value.
                  Positioned(
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 2.5,
                        height: _majorTick + 8,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // A tap on the centre value opens typed entry; translucent
                  // so a drag starting there still reaches the tape.
                  GestureDetector(
                    key: const Key('ruler-centre'),
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onTapValue,
                    child: SizedBox(width: extent, height: _height),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _majorTick = 14;
const double _minorTick = 7;

/// Where label centres sit: midway down the space above the ruled edge,
/// clear of its ticks.
const double _labelCentreY = (RulerPickerState._height - _majorTick - 4) / 2;

/// Laid-out value labels, keyed by text, centre styling and a quantised
/// opacity, so the tape does not re-shape text on every frame.
class _LabelCache {
  final Map<String, TextPainter> _painters = {};
  Color? _text;
  Color? _accent;
  TextScaler? _scaler;

  /// Bumped whenever the cache is emptied, so a painter knows to repaint.
  int generation = 0;

  static const int _alphaSteps = 50;
  static const int _limit = 400;

  void configure({required Color text, required Color accent, required TextScaler scaler}) {
    if (text == _text && accent == _accent && scaler == _scaler) return;
    clear();
    _text = text;
    _accent = accent;
    _scaler = scaler;
  }

  TextPainter get(String label, {required bool centre, required double opacity}) {
    final a = (opacity.clamp(0.0, 1.0) * _alphaSteps).round();
    final key = '$label|${centre ? 1 : 0}|$a';
    final hit = _painters[key];
    if (hit != null) return hit;
    if (_painters.length >= _limit) clear();
    final color = (centre ? _accent! : _text!).withValues(alpha: a / _alphaSteps);
    return _painters[key] = TextPainter(
      text: TextSpan(
        text: label,
        style: WorkoutType.display(
          size: 28,
          weight: centre ? FontWeight.w700 : FontWeight.w600,
          color: color,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      textDirection: TextDirection.ltr,
      textScaler: _scaler ?? TextScaler.noScaling,
      maxLines: 1,
    )..layout();
  }

  void clear() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
    generation++;
  }

  void dispose() => clear();
}

/// The whole tape in one pass: the ruled edge along the bottom (a hairline
/// baseline, a major tick per value and four minor ones between, so the
/// scale reads evenly) and the value labels above it. A label is full size
/// and accent-coloured at the centre, smaller and fainter with distance.
class _TapePainter extends CustomPainter {
  _TapePainter({
    required this.position,
    required this.scale,
    required this.pxPerValue,
    required this.extent,
    required this.format,
    required this.line,
    required this.labels,
  }) : generation = labels.generation;

  final double position;
  final RulerScale scale;
  final double pxPerValue;
  final double extent;
  final String Function(double) format;
  final Color line;
  final _LabelCache labels;
  final int generation;

  double _x(double v, Size size) => size.width / 2 + (v - position) * pxPerValue;

  @override
  void paint(Canvas canvas, Size size) {
    final step = scale.step;
    final base = size.height - 0.5;
    final halfSpan = size.width / 2 / pxPerValue + step;
    final lo = math.max(position - halfSpan, scale.first - step / 2);
    final hi = math.min(position + halfSpan, scale.last + step / 2);

    // The baseline spans the tape, half a slot past each end value.
    canvas.drawLine(
      Offset(math.max(0, _x(scale.first - step / 2, size)), base),
      Offset(math.min(size.width, _x(scale.last + step / 2, size)), base),
      Paint()
        ..color = line.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Five ticks per value: a major one on it, minor ones between.
    final major = Paint()
      ..color = line
      ..strokeWidth = 1.5;
    final minor = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final sub = step / 5;
    final k0 = math.max(((lo - scale.base) / sub).ceil(), -2);
    final k1 = math.min(((hi - scale.base) / sub).floor(), (scale.count - 1) * 5 + 2);
    for (var k = k0; k <= k1; k++) {
      final x = _x(scale.base + k * sub, size);
      final isMajor = k % 5 == 0;
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - (isMajor ? _majorTick : _minorTick)),
        isMajor ? major : minor,
      );
    }

    // Labels.
    final i0 = math.max(((lo - scale.base) / step).floor(), 0);
    final i1 = math.min(((hi - scale.base) / step).ceil(), scale.count - 1);
    for (var i = i0; i <= i1; i++) {
      final v = scale.valueAt(i);
      final x = _x(v, size);
      _label(canvas, x, format(v), (x - size.width / 2).abs() / extent);
    }
  }

  void _label(Canvas canvas, double x, String text, double distance) {
    final d = distance.clamp(0.0, 3.0);
    final centre = d < 0.5;
    // A gentle falloff: 1.0 at the centre, 0.72 one step away, 0.56 at three.
    final size = d <= 1 ? 1 - 0.28 * d : 0.72 - 0.08 * (d - 1);
    final opacity = (1 - 0.26 * d).clamp(0.22, 1.0);
    final tp = labels.get(text, centre: centre, opacity: opacity);
    canvas
      ..save()
      ..translate(x, _labelCentreY)
      ..scale(size);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.position != position ||
      old.pxPerValue != pxPerValue ||
      old.scale != scale ||
      old.line != line ||
      old.format != format ||
      old.generation != generation;
}
