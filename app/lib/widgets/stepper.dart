import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A numeric stepper with − / + buttons flanking a formatted value label.
///
/// Values are clamped to ≥ 0. Button taps call [onChanged] with the new value
/// and do NOT bubble to enclosing widgets (stopPropagation via [GestureDetector]
/// with [HitTestBehavior.opaque]).
///
/// The stepper maintains an internal copy of [value] so that consecutive taps
/// without a parent-triggered rebuild still compound correctly (each tap steps
/// from the *previous tap's* value, not the last-rendered [value]).
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `Stepper`.
class WStepper extends StatefulWidget {
  const WStepper({
    super.key,
    required this.value,
    required this.step,
    required this.format,
    required this.onChanged,
  });

  final double value;
  final double step;

  /// Formats the current value for display.
  final String Function(double) format;

  final ValueChanged<double> onChanged;

  @override
  State<WStepper> createState() => _WStepperState();
}

class _WStepperState extends State<WStepper> {
  late double _internalValue;

  /// Direction of the most recent value change, used to slide the label in the
  /// direction of change (true = value went up).
  bool _up = true;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.value;
  }

  @override
  void didUpdateWidget(WStepper old) {
    super.didUpdateWidget(old);
    // Keep internal value in sync when the parent provides a new value
    // (e.g. after an undo or external reset).
    if (widget.value != old.value) {
      _up = widget.value > old.value;
      _internalValue = widget.value;
    }
  }

  /// Round to 2 decimal places to avoid floating-point drift.
  static double _round2(double v) => (v * 100).round() / 100;

  void _step(int dir) {
    final next = _round2(_internalValue + dir * widget.step);
    final clamped = next < 0 ? 0.0 : next;
    setState(() {
      _up = clamped > _internalValue;
      _internalValue = clamped;
    });
    HapticFeedback.selectionClick();
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final buttonDecoration = BoxDecoration(
      color: tokens.surface3,
      borderRadius: BorderRadius.circular(AppRadius.radius * 0.4),
    );

    Widget btn({
      required Key key,
      required IconData icon,
      required int dir,
    }) {
      return GestureDetector(
        key: key,
        // Stop tap from propagating to parent (e.g. accordion header).
        behavior: HitTestBehavior.opaque,
        onTap: () => _step(dir),
        child: Container(
          width: 25,
          height: 34,
          decoration: buttonDecoration,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: tokens.text),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        btn(key: const Key('stepper-dec'), icon: Icons.remove, dir: -1),
        const SizedBox(width: 4),
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(0, _up ? 0.4 : -0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                widget.format(_internalValue),
                key: ValueKey(widget.format(_internalValue)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkoutType.mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        btn(key: const Key('stepper-inc'), icon: Icons.add, dir: 1),
      ],
    );
  }
}
