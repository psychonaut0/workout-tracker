import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/typography.dart';

/// A mono uppercase section label with an optional right-aligned action widget.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/ui.jsx`.
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.label,
    this.action,
  });

  final String label;

  /// Optional widget placed at the trailing end (e.g. a text button).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: WorkoutType.mono(
            size: 11,
            weight: FontWeight.w600,
            color: tokens.faint,
            letterSpacing: 0.08 * 11,
          ),
        ),
        if (action != null) ...[
          const Spacer(),
          action!,
        ],
      ],
    );
  }
}
