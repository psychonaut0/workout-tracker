import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A PR badge — filled bolt icon + "PR" text in accent color.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/ui.jsx` `PRBadge`.
class PRBadge extends StatelessWidget {
  const PRBadge({super.key, this.small = false});

  /// When true, uses smaller sizing (9.5px font, 9px icon).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final double fontSize = small ? 9.5 : 10.5;
    final double iconSize = small ? 9 : 11;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 5 : 7,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(WIcons.bolt, size: iconSize, color: tokens.accentInk),
          const SizedBox(width: 3),
          Text(
            'PR',
            style: WorkoutType.mono(
              size: fontSize,
              weight: FontWeight.w700,
              color: tokens.accentInk,
              letterSpacing: 0.06 * fontSize,
            ),
          ),
        ],
      ),
    );
  }
}
