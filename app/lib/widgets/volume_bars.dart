import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'card.dart';

/// A card listing per-muscle weekly volume bars with target ticks.
///
/// Each row shows:
///   • A 74 px muscle label
///   • A proportional fill bar (muted `lineStrong` when `sets < target`,
///     `accent` when `sets >= target`) with a 1.5 px tick at `target/max`
///   • A right-aligned `'{sets}/{target}'` value (dim when under target)
///
/// `target` is always a non-null int; Task 7 coalesces goalless muscles to
/// `target = sets` so nothing ever divides by zero or compares against null.
///
/// Visual spec: `screen-today.jsx` → `VolumeBars`.
class VolumeBars extends StatelessWidget {
  const VolumeBars({
    super.key,
    required this.rows,
  });

  /// Each entry describes one muscle row.
  ///
  /// - [muscle] — display name (e.g. 'quads')
  /// - [sets]   — actual working sets this week
  /// - [target] — target sets for the week (non-null)
  final List<({String muscle, int sets, int target})> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Compute the scale maximum across all sets + targets, with a floor of 1
    // to avoid division by zero when the list is empty.
    final maxVal = rows.fold<int>(
      1,
      (m, r) => [m, r.sets, r.target].reduce(max),
    );

    return WCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, row) in rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _VolumeRow(
                row: row,
                maxVal: maxVal,
                tokens: tokens,
                index: index,
              ),
            ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.row,
    required this.maxVal,
    required this.tokens,
    required this.index,
  });

  final ({String muscle, int sets, int target}) row;
  final int maxVal;
  final WorkoutTokens tokens;

  /// Row position, used to stagger the bar grow-in (~20ms per row).
  final int index;

  @override
  Widget build(BuildContext context) {
    final underTarget = row.sets < row.target;
    final fillColor = underTarget ? tokens.lineStrong : tokens.accent;
    final valueColor = underTarget ? tokens.dim : tokens.text;

    final fillFraction = row.sets / maxVal;
    final tickFraction = row.target / maxVal;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Muscle label — fixed width 74
        SizedBox(
          width: 74,
          child: Text(
            row.muscle,
            style: WorkoutType.body(
              size: 12.5,
              color: tokens.dim,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        // Track with fill bar + target tick
        Expanded(
          child: SizedBox(
            height: 7,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background track
                Container(
                  decoration: BoxDecoration(
                    color: tokens.surface3,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                // Fill bar — grows 0→fraction on mount, staggered by row index
                // (~20ms per row via a slightly longer per-row duration). On a
                // data rebuild the tween retargets old→new, which animates the
                // bar to its new width rather than re-growing from zero.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fillFraction.clamp(0.0, 1.0)),
                  duration: Motion.of(
                    context,
                    Motion.base + Duration(milliseconds: 20 * index),
                  ),
                  curve: Motion.curve,
                  builder: (_, factor, __) => FractionallySizedBox(
                    widthFactor: factor,
                    child: Container(
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
                // Target tick — 1.5 px wide, overhanging ±3 px vertically
                Align(
                  alignment: Alignment(
                    (tickFraction.clamp(0.0, 1.0) * 2 - 1),
                    0,
                  ),
                  child: OverflowBox(
                    maxHeight: double.infinity,
                    child: Container(
                      width: 1.5,
                      height: 7 + 6, // 7 track + 3 overhang each side
                      color: tokens.text.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // '{sets}/{target}' value — fixed width 38, right-aligned
        SizedBox(
          width: 38,
          child: Text(
            '${row.sets}/${row.target}',
            textAlign: TextAlign.right,
            style: WorkoutType.mono(
              size: 11.5,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
