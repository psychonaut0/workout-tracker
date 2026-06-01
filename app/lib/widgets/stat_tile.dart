import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A compact stat tile: mono uppercase label, big value, optional unit,
/// and either a sparkline widget or a sub-label below.
///
/// Visual spec: `screen-today.jsx` → `StatTile`.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.spark,
    this.sub,
    this.onTap,
  });

  /// Short uppercase label shown above the value (e.g. 'Bodyweight').
  final String label;

  /// Primary value (e.g. '82.5').
  final String value;

  /// Optional unit shown baseline-aligned to the value (e.g. 'kg').
  final String? unit;

  /// Optional sparkline widget shown below the value row (takes priority
  /// over [sub] when both are provided).
  final Widget? spark;

  /// Optional secondary text shown below the value row when [spark] is null.
  final String? sub;

  /// Optional tap handler; wraps the tile in an [InkWell] when set.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget content = Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        border: Border.all(color: tokens.line),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mono uppercase label
          Text(
            label.toUpperCase(),
            style: WorkoutType.mono(
              size: 10,
              color: tokens.faint,
              letterSpacing: 0.08 * 10,
            ),
          ),
          const SizedBox(height: 8),
          // Value + unit baseline row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: WorkoutType.display(
                  size: 27,
                  weight: FontWeight.w700,
                  color: tokens.text,
                  letterSpacing: 27 * -0.02,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: WorkoutType.mono(
                    size: 12,
                    color: tokens.dim,
                  ),
                ),
              ],
            ],
          ),
          // Spark or sub label
          if (spark != null) ...[
            const SizedBox(height: 8),
            spark!,
          ] else if (sub != null) ...[
            const SizedBox(height: 6),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkoutType.mono(
                size: 10.5,
                color: tokens.dim,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        child: content,
      );
    }

    return content;
  }
}
