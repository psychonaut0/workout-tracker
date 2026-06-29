import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Floating rest-timer card shown after a working set is completed.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `RestTimer`.
///
/// The timer is driven by a start timestamp + stored total duration so that:
/// - `+30s` extends [totalSeconds] by 30 (not "remaining"), which correctly
///   updates both the countdown and the ring fill.
/// - "remaining" is always computed as `totalSeconds − (now − startTime)`,
///   never mutated directly.
/// - Auto-dismiss at 0 is handled by the parent (it reads remaining from the
///   controller state); the card itself emits [onDismiss] when Skip is tapped.
///
/// The parent ([ActiveSessionScreen]) owns [startTime] and [totalSeconds] so
/// that `+30s` only increments the `_restTotal` field rather than a local
/// state variable that could be reset on rebuild.
class RestTimerCard extends StatefulWidget {
  const RestTimerCard({
    super.key,
    required this.totalSeconds,
    required this.startTime,
    required this.onAdd30s,
    required this.onDismiss,
  });

  /// Total planned rest duration (seconds). Increases when +30s is tapped.
  final int totalSeconds;

  /// When the rest period started.
  final DateTime startTime;

  /// Called when the user taps +30s — the parent should add 30 to [totalSeconds].
  final VoidCallback onAdd30s;

  /// Called when the user taps Skip (or auto-dismiss fires).
  final VoidCallback onDismiss;

  @override
  State<RestTimerCard> createState() => _RestTimerCardState();
}

class _RestTimerCardState extends State<RestTimerCard>
    with SingleTickerProviderStateMixin {
  /// Threshold (inclusive) for the "final seconds" emphasis state.
  static const int _finalThreshold = 5;

  /// Repeating 1.0↔1.03 pulse used in the final-5s window. Started on entering
  /// the window, stopped + reset to 1.0 on exit / zero / dismiss.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    lowerBound: 1.0,
    upperBound: 1.03,
  );

  bool _pulsing = false;

  int get _remaining {
    final elapsed = DateTime.now().difference(widget.startTime).inSeconds;
    return (widget.totalSeconds - elapsed).clamp(0, widget.totalSeconds);
  }

  bool get _inFinalWindow {
    final r = _remaining;
    return r > 0 && r <= _finalThreshold;
  }

  void _syncPulse() {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final shouldPulse = _inFinalWindow && !reducedMotion;
    if (shouldPulse && !_pulsing) {
      _pulsing = true;
      _pulse.repeat(reverse: true);
    } else if (!shouldPulse && _pulsing) {
      _pulsing = false;
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);

    final remaining = _remaining;
    final mm = remaining ~/ 60;
    final ss = remaining % 60;
    final pct = widget.totalSeconds > 0
        ? (1 - remaining / widget.totalSeconds).clamp(0.0, 1.0)
        : 1.0;

    final isFinal = _inFinalWindow;
    final emphasisColor = isFinal ? tokens.accent : tokens.text;

    // Start/stop the pulse loop in response to the current remaining value.
    // Runs after build so MediaQuery is available and we don't mutate the
    // controller mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPulse();
    });

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        border: Border.all(color: tokens.lineStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Circular progress ring ─────────────────────────────────────
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Smooth per-second sweep: the fraction is tweened linearly
                // over 1s so the arc glides instead of stepping. When +30s
                // pushes the fraction back UP, a 1s linear tween toward the
                // higher value is acceptable.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: pct),
                  duration: Motion.of(context, const Duration(seconds: 1)),
                  curve: Curves.linear,
                  builder: (_, value, __) => CustomPaint(
                    size: const Size(40, 40),
                    painter: _RingPainter(
                      progress: value,
                      trackColor: tokens.surface3,
                      arcColor: tokens.accent,
                      strokeWidth: 3,
                    ),
                  ),
                ),
                Icon(WIcons.timer, size: 14, color: tokens.accent),
              ],
            ),
          ),
          const SizedBox(width: 13),

          // ── "Rest" label + countdown ───────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.restLabel,
                  style: WorkoutType.mono(
                    size: 10,
                    color: tokens.faint,
                    letterSpacing: 0.08 * 10,
                  ),
                ),
                AnimatedDefaultTextStyle(
                  duration: Motion.of(context, Motion.base),
                  curve: Motion.curve,
                  style: WorkoutType.display(
                    size: 22,
                    weight: FontWeight.w700,
                    color: emphasisColor,
                  ),
                  child: Text('$mm:${ss.toString().padLeft(2, '0')}'),
                ),
              ],
            ),
          ),

          // ── +30s button ────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onAdd30s,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(AppRadius.radius * 0.5),
                border: Border.all(color: tokens.lineStrong),
              ),
              alignment: Alignment.center,
              child: Text(
                l.restAdd30s,
                style: WorkoutType.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: tokens.dim,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Skip button ────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius:
                    BorderRadius.circular(AppRadius.radius * 0.5),
              ),
              alignment: Alignment.center,
              child: Text(
                l.commonSkip,
                style: WorkoutType.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: tokens.accentInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Gentle scale pulse during the final-5s window. AnimatedBuilder reads the
    // controller value directly so it stays at exactly 1.0 when not pulsing.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
      child: card,
    );
  }
}

// ── CustomPainter for the circular ring ──────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
    required this.strokeWidth,
  });

  /// 0.0 = empty, 1.0 = full ring.
  final double progress;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Full background ring
    canvas.drawCircle(center, radius, trackPaint);

    // Arc filled according to progress, starting from the top (−π/2)
    if (progress > 0) {
      const startAngle = -3.14159 / 2; // −90°
      final sweepAngle = 2 * 3.14159 * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.arcColor != arcColor ||
      old.strokeWidth != strokeWidth;
}
