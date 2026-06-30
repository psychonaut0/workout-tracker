import 'package:flutter/material.dart';

import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Centered trash-icon + [label] delete button used by the plan editors.
/// The label is caller-supplied (the editors use different ARB strings).
class WDeleteButton extends StatelessWidget {
  const WDeleteButton({
    super.key,
    required this.tokens,
    required this.label,
    required this.onTap,
  });

  final WorkoutTokens tokens;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(WIcons.trash, size: 15, color: tokens.faint),
            const SizedBox(width: 6),
            Text(
              label,
              style: WorkoutType.mono(
                size: 12.5,
                weight: FontWeight.w600,
                color: tokens.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
