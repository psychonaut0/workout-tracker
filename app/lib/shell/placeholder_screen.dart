import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/typography.dart';

/// A lightweight placeholder tab shown for sections not yet implemented.
///
/// Renders a faint icon glyph, a large title, and a 'Coming soon' label,
/// all centred on the app background. Bottom inset accounts for the tab bar
/// (96 px) plus the system safe area.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.title,
    this.icon,
  });

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bottomInset = 96 + MediaQuery.viewPaddingOf(context).bottom;

    return ColoredBox(
      color: tokens.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 52, color: tokens.faint),
                  const SizedBox(height: 16),
                ],
                Text(
                  title,
                  style: WorkoutType.display(
                    size: 22,
                    weight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coming soon',
                  style: WorkoutType.mono(size: 12, color: tokens.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
