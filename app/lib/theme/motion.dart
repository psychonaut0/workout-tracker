import 'package:flutter/widgets.dart';

/// Single source of motion truth: fast & snappy, zero bounce.
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;

  /// Honors the platform reduced-motion setting.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Animated integer count-up: 0→value on first build, old→new on changes
/// (TweenAnimationBuilder's natural retargeting). Renders via [builder] so the
/// final formatted output is identical to a static render.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder});
  final int value;
  final Widget Function(int value) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: Motion.of(context, Motion.slow),
      curve: Motion.curve,
      builder: (_, v, __) => builder(v),
    );
  }
}

/// One-shot fade + 12px rise on first mount, staggered by [index]. Never
/// re-plays on rebuilds.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.base);
  late final CurvedAnimation _a = CurvedAnimation(parent: _c, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - _a.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
