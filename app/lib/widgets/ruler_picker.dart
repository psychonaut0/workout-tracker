import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';
import '../util/number_input.dart';

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

  double valueAt(int i) =>
      clampRound2(base + i.clamp(0, count - 1) * step, min: double.negativeInfinity);

  int indexOf(double v) => ((v - base) / step).round().clamp(0, count - 1);
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
  final double step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final double min;

  /// Upper end of the tape; it grows to include [value] when that is higher.
  final double max;
  final double itemExtent;
  final VoidCallback? onTapValue;
  final String? semanticLabel;

  @override
  State<RulerPicker> createState() => RulerPickerState();
}

@visibleForTesting
class RulerPickerState extends State<RulerPicker> {
  late RulerScale scale;
  late FixedExtentScrollController _controller;

  /// The last value this picker reported or was handed; a rebuild carrying
  /// it is not an external change.
  late double _current;

  static const double _height = 88;

  @override
  void initState() {
    super.initState();
    _current = widget.value;
    scale = _scaleFor(widget.value);
    _controller = FixedExtentScrollController(initialItem: scale.indexOf(widget.value));
    RulerPicker._mounted.add(this);
  }

  /// True while the picker moves its own tape (re-anchoring, settling), so
  /// the selection those moves cause is not reported as a user change.
  bool _jumping = false;

  void _jump(int index) {
    _jumping = true;
    try {
      _controller.jumpToItem(index);
    } finally {
      _jumping = false;
    }
  }

  /// Halts a glide on the currently selected value; see [RulerPicker.settleAll].
  void settle() {
    if (!_controller.hasClients) return;
    _jump(_controller.selectedItem);
  }

  RulerScale _scaleFor(double anchor) =>
      RulerScale(anchor: anchor, step: widget.step, min: widget.min, max: widget.max);

  @override
  void didUpdateWidget(RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stepChanged = widget.step != oldWidget.step;
    if (widget.value == _current && !stepChanged) return;
    _current = widget.value;
    if (stepChanged || scale.valueAt(scale.indexOf(widget.value)) != widget.value) {
      setState(() => scale = _scaleFor(widget.value));
    }
    final target = scale.indexOf(widget.value);
    if (_controller.hasClients && _controller.selectedItem != target) {
      _jump(target);
    }
  }

  @override
  void dispose() {
    RulerPicker._mounted.remove(this);
    _controller.dispose();
    super.dispose();
  }

  void _onSelected(int index) {
    if (_jumping) return;
    final v = scale.valueAt(index);
    if (v == _current) return;
    _current = v;
    HapticFeedback.selectionClick();
    widget.onChanged(v);
  }

  void _nudge(int delta) {
    final target = (_controller.selectedItem + delta).clamp(0, scale.count - 1);
    final duration = Motion.of(context, Motion.base);
    if (duration == Duration.zero) {
      _controller.jumpToItem(target);
    } else {
      _controller.animateToItem(target, duration: duration, curve: Motion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final extent = widget.itemExtent;
    final i = scale.indexOf(_current);

    final tape = RotatedBox(
      // The wheel scrolls vertically; turned a quarter anticlockwise its
      // top becomes the left, so higher values lie to the right and a
      // leftward swipe moves up the tape.
      quarterTurns: 3,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: extent,
        physics: const FixedExtentScrollPhysics(),
        // A near-flat wheel: the tape reads as a ruler, not a drum.
        diameterRatio: 1000,
        perspective: 0.0001,
        onSelectedItemChanged: _onSelected,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: scale.count,
          builder: (context, index) => RotatedBox(
            quarterTurns: 1,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final pos = _controller.hasClients
                    ? _controller.offset / extent
                    : _controller.initialItem.toDouble();
                return _RulerMark(
                  label: widget.format(scale.valueAt(index)),
                  distance: (index - pos).abs(),
                  extent: extent,
                );
              },
            ),
          ),
        ),
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
        child: SizedBox(
          height: _height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fade the tape out at both edges.
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.18, 0.82, 1],
                ).createShader(rect),
                child: tape,
              ),
              // Fixed centre marker under the selected value.
              Positioned(
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 2.5,
                    height: 20,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // A tap on the centre value opens typed entry; translucent so a
              // drag starting there still reaches the tape underneath.
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
    );
  }
}

/// One value on the tape plus its tick: full size and accent at the centre,
/// smaller and fainter with distance.
class _RulerMark extends StatelessWidget {
  const _RulerMark({required this.label, required this.distance, required this.extent});

  final String label;
  final double distance;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final d = distance.clamp(0.0, 3.0);
    final centre = d < 0.5;
    // 1.0 at the centre, 0.5 one step away, easing to 0.42 further out.
    final scale = d <= 1 ? 1 - 0.5 * d : 0.5 - 0.04 * (d - 1);
    final opacity = (1 - 0.3 * d).clamp(0.18, 1.0);
    return SizedBox(
      width: extent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Center(
              child: Transform.scale(
                scale: scale,
                // Fade through the text colour, not an Opacity widget: no
                // offscreen layer per mark while the tape moves.
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: WorkoutType.display(
                    size: 32,
                    weight: FontWeight.w700,
                    color: (centre ? tokens.accent : tokens.text).withValues(alpha: opacity),
                  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
          Container(
            width: 1.5,
            height: centre ? 0 : 10,
            color: tokens.lineStrong.withValues(alpha: opacity),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
