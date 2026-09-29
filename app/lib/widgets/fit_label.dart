import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A label that shrinks a little, then ellipsizes — and never splits a word
/// across lines.
///
/// It lays out at the full [style]. If the text needs more than [maxLines]
/// lines, or any single word (split on whitespace) is wider than the space
/// available, it retries at smaller sizes in 0.05 steps down to [minScale].
/// If it still doesn't fit, it renders at [minScale] on one line with an
/// ellipsis: "BODYWEIGHT" becomes smaller, then "BODYWEI…", never
/// "BODYWEI/GHT".
///
/// The shrink multiplies the ambient [TextScaler], so the user's text size is
/// respected, never replaced. A real [Text] stays in the tree, so finders,
/// semantics (the full text) and selection behave as for any label.
///
/// Unlike a `LayoutBuilder` it answers intrinsic-size queries, so it works
/// under `IntrinsicHeight` (the Today stat row and the week strip).
class FitLabel extends StatelessWidget {
  const FitLabel(
    String this.text, {
    super.key,
    required TextStyle this.style,
    this.maxLines = 1,
    this.minScale = 0.8,
    this.textAlign,
  }) : span = null,
       assert(maxLines >= 1),
       assert(minScale > 0 && minScale <= 1);

  /// A label of several styled runs (e.g. a name and a dimmer focus).
  const FitLabel.rich(
    InlineSpan this.span, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.minScale = 0.8,
    this.textAlign,
  }) : text = null,
       assert(maxLines >= 1),
       assert(minScale > 0 && minScale <= 1);

  final String? text;
  final InlineSpan? span;
  final TextStyle? style;
  final int maxLines;
  final double minScale;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final ambient = MediaQuery.textScalerOf(context);
    final label = span == null
        ? Text(
            text!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textScaler: ambient,
          )
        : Text.rich(
            span!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textScaler: ambient,
          );
    return _FitScope(
      ambient: ambient,
      maxLines: maxLines,
      minScale: minScale,
      child: label,
    );
  }
}

class _FitScope extends SingleChildRenderObjectWidget {
  const _FitScope({
    required this.ambient,
    required this.maxLines,
    required this.minScale,
    required Widget super.child,
  });

  final TextScaler ambient;
  final int maxLines;
  final double minScale;

  @override
  RenderFitLabel createRenderObject(BuildContext context) =>
      RenderFitLabel(ambient: ambient, maxLines: maxLines, minScale: minScale);

  @override
  void updateRenderObject(BuildContext context, RenderFitLabel renderObject) {
    renderObject
      ..ambient = ambient
      ..maxLines = maxLines
      ..minScale = minScale;
  }
}

typedef _Fit = ({TextScaler scaler, double scale, bool ellipsized});

/// Lays its [Text] child out at the largest scale, from 1.0 down to
/// [minScale] in 0.05 steps, at which the text needs at most [maxLines]
/// lines and no word is wider than the line; failing that, at [minScale] on
/// one ellipsized line.
class RenderFitLabel extends RenderProxyBox {
  RenderFitLabel({
    required TextScaler ambient,
    required int maxLines,
    required double minScale,
  }) : _ambient = ambient,
       _maxLines = maxLines,
       _minScale = minScale;

  static const double _step = 0.05;
  static const String _ellipsis = '…';

  TextScaler get ambient => _ambient;
  TextScaler _ambient;
  set ambient(TextScaler value) {
    if (value == _ambient) return;
    _ambient = value;
    markNeedsLayout();
  }

  int get maxLines => _maxLines;
  int _maxLines;
  set maxLines(int value) {
    if (value == _maxLines) return;
    _maxLines = value;
    markNeedsLayout();
  }

  double get minScale => _minScale;
  double _minScale;
  set minScale(double value) {
    if (value == _minScale) return;
    _minScale = value;
    markNeedsLayout();
  }

  /// The scale the last layout applied (1.0 = the full style).
  double get appliedScale => _appliedScale;
  double _appliedScale = 1.0;

  /// Whether the last layout fell back to one ellipsized line.
  bool get ellipsized => _ellipsized;
  bool _ellipsized = false;

  /// The label's paragraph: the child itself, or under single-child
  /// wrappers `Text` may add (e.g. a `MouseRegion` inside a `SelectionArea`).
  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node != null && node is! RenderParagraph) {
      node = node is RenderObjectWithChildMixin<RenderObject>
          ? node.child
          : null;
    }
    return node is RenderParagraph ? node : null;
  }

  TextScaler _scalerFor(double scale) =>
      scale == 1.0 ? _ambient : _MultipliedTextScaler(_ambient, scale);

  TextPainter _painter(
    RenderParagraph p,
    TextScaler scaler, {
    int? maxLines,
    bool ellipsis = false,
  }) {
    return TextPainter(
      text: p.text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: ellipsis ? _ellipsis : null,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
    );
  }

  bool _fits(RenderParagraph p, TextScaler scaler, double maxWidth) {
    final wrapped = _painter(p, scaler, maxLines: _maxLines)
      ..layout(maxWidth: maxWidth);
    final exceeded = wrapped.didExceedMaxLines;
    wrapped.dispose();
    if (exceeded) return false;
    // The widest word must fit whole, or the line breaker splits it.
    final plain = p.text.toPlainText(includeSemanticsLabels: false);
    final line = _painter(p, scaler)..layout();
    try {
      for (final word in RegExp(r'\S+').allMatches(plain)) {
        final boxes = line.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        );
        if (boxes.isEmpty) continue;
        final left = boxes.map((b) => b.left).reduce(math.min);
        final right = boxes.map((b) => b.right).reduce(math.max);
        if (right - left > maxWidth) return false;
      }
      return true;
    } finally {
      line.dispose();
    }
  }

  _Fit _resolve(RenderParagraph p, double maxWidth) {
    if (!maxWidth.isFinite) {
      return (scaler: _ambient, scale: 1.0, ellipsized: false);
    }
    var scale = 1.0;
    while (true) {
      final scaler = _scalerFor(scale);
      if (_fits(p, scaler, maxWidth)) {
        return (scaler: scaler, scale: scale, ellipsized: false);
      }
      if (scale <= _minScale) {
        return (scaler: scaler, scale: scale, ellipsized: true);
      }
      scale = math.max(_minScale, ((scale - _step) * 100).round() / 100);
    }
  }

  T _withFittedPainter<T>(
    RenderParagraph p,
    BoxConstraints constraints,
    T Function(TextPainter painter) read,
  ) {
    final fit = _resolve(p, constraints.maxWidth);
    final painter = _painter(
      p,
      fit.scaler,
      maxLines: fit.ellipsized ? 1 : _maxLines,
      ellipsis: true,
    )..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    try {
      return read(painter);
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final p = _paragraph;
    if (p == null) return super.computeMinIntrinsicWidth(height);
    final painter = _painter(p, _scalerFor(_minScale))..layout();
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final p = _paragraph;
    if (p == null) return super.computeMaxIntrinsicWidth(height);
    final painter = _painter(p, _ambient)..layout();
    final width = painter.maxIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final p = _paragraph;
    if (p == null) return super.computeMinIntrinsicHeight(width);
    return _withFittedPainter(
      p,
      BoxConstraints(maxWidth: width),
      (painter) => painter.height,
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final p = _paragraph;
    if (p == null) return super.computeMaxIntrinsicHeight(width);
    return _withFittedPainter(
      p,
      BoxConstraints(maxWidth: width),
      (painter) => painter.height,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final p = _paragraph;
    if (p == null) return super.computeDryLayout(constraints);
    return _withFittedPainter(
      p,
      constraints,
      (painter) => constraints.constrain(painter.size),
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final p = _paragraph;
    if (p == null) return super.computeDryBaseline(constraints, baseline);
    return _withFittedPainter(
      p,
      constraints,
      (painter) => painter.computeDistanceToActualBaseline(baseline),
    );
  }

  @override
  void performLayout() {
    final p = _paragraph;
    if (p != null) {
      final fit = _resolve(p, constraints.maxWidth);
      _appliedScale = fit.scale;
      _ellipsized = fit.ellipsized;
      // Mutating the child during our layout is only allowed inside a layout
      // callback — the same mechanism LayoutBuilder uses to build children.
      invokeLayoutCallback<BoxConstraints>((_) {
        p
          ..textScaler = fit.scaler
          ..maxLines = fit.ellipsized ? 1 : _maxLines;
      });
    }
    final child = this.child;
    if (child == null) {
      size = computeSizeForNoChild(constraints);
      return;
    }
    // Never hand the child tight constraints: a tightly constrained paragraph
    // is its own relayout boundary, so a rebuild (which resets its scaler and
    // maxLines to the widget's values) would re-lay out only the paragraph, at
    // full size, without refitting here. With an unbounded height every
    // change to the child bubbles up to this layout. The width stays as given,
    // so textAlign still has the full line to align in.
    child.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
  }

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // A tight parent shorter than the text leaves the child taller than this
    // box. Clip it, so the overspill can't hide from the layout checks.
    if (child.size.height > size.height) {
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
        oldLayer: _clipLayer.layer,
      );
    } else {
      _clipLayer.layer = null;
      super.paint(context, offset);
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }
}

/// The ambient [TextScaler] times a shrink factor: a fitted label still
/// follows the user's text size, including a non-linear system scaler.
class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
