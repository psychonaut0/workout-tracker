import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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
      _internalValue = widget.value;
    }
  }

  /// Round to 2 decimal places to avoid floating-point drift.
  static double _round2(double v) => (v * 100).round() / 100;

  void _step(int dir) {
    final next = _round2(_internalValue + dir * widget.step);
    final clamped = next < 0 ? 0.0 : next;
    setState(() => _internalValue = clamped);
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
          width: 34,
          height: 34,
          decoration: buttonDecoration,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: tokens.text),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(key: const Key('stepper-dec'), icon: Icons.remove, dir: -1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            widget.format(_internalValue),
            style: WorkoutType.mono(
              size: 15,
              weight: FontWeight.w700,
              color: tokens.text,
            ),
          ),
        ),
        btn(key: const Key('stepper-inc'), icon: Icons.add, dir: 1),
      ],
    );
  }
}
