import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/pr_badge.dart';
import '../widgets/tag.dart';
import 'active_session_controller.dart';
import 'set_row.dart';

/// A collapsible accordion card for one exercise in the active session.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `ExerciseBlock`.
class ExerciseBlock extends StatefulWidget {
  const ExerciseBlock({
    super.key,
    required this.block,
    required this.unit,
    required this.onToggleDone,
    required this.onSetChanged,
    required this.onAddSet,
    required this.onRemoveBlock,
  });

  final BlockState block;
  final UnitService unit;
  final void Function(BlockState, SetState) onToggleDone;
  final void Function(BlockState, SetState) onSetChanged;
  final void Function(BlockState) onAddSet;
  final void Function(BlockState) onRemoveBlock;

  @override
  State<ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends State<ExerciseBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final block = widget.block;
    final ex = block.exercise;
    final resolved = block.resolved;
    final unit = widget.unit;

    final working = block.workingSets;
    final doneWorking = working.where((s) => s.done).toList();
    final allDone = working.isNotEmpty && doneWorking.length == working.length;

    // Live top weight among done working sets
    final completedTop = doneWorking.isEmpty
        ? 0.0
        : doneWorking.fold<double>(
            0, (m, s) => s.weightKg > m ? s.weightKg : m);

    final bestKg = block.bestKg;
    final isLivePr =
        completedTop > 0 && (bestKg == null || completedTop > bestKg);

    // RIR display string for the sub-label
    final rirStr = resolved.rirLow == resolved.rirHigh
        ? '${resolved.rirLow}'
        : '${resolved.rirLow}–${resolved.rirHigh}';

    final muscleLabel = ex.muscleGroup;
    final subLabel =
        '$muscleLabel · ${resolved.workSets}×${resolved.repLow}–${resolved.repHigh} @ RIR $rirStr';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        border: Border.all(
            color: _expanded ? tokens.lineStrong : tokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (always visible) ────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  // Completion badge
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: allDone ? tokens.accent : tokens.surface3,
                      borderRadius:
                          BorderRadius.circular(AppRadius.radius * 0.5),
                    ),
                    alignment: Alignment.center,
                    child: allDone
                        ? Icon(Icons.check,
                            size: 18, color: tokens.accentInk)
                        : Text(
                            '${doneWorking.length}/${working.length}',
                            style: WorkoutType.mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: tokens.dim,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Exercise name + sub-label
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex.name,
                          style: WorkoutType.body(
                            size: 15,
                            weight: FontWeight.w600,
                            color: tokens.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subLabel,
                          style: WorkoutType.mono(
                            size: 10.5,
                            color: tokens.faint,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Live top weight + PR badge
                  if (completedTop > 0) ...[
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: unit.fmtWt(completedTop),
                                style: WorkoutType.mono(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: tokens.text,
                                ),
                              ),
                              TextSpan(
                                text: unit.uLabel,
                                style: WorkoutType.mono(
                                  size: 10,
                                  color: tokens.faint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isLivePr) ...[
                          const SizedBox(height: 2),
                          const PRBadge(small: true),
                        ],
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],

                  // Chevron (rotates when expanded)
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(WIcons.chevron, size: 18, color: tokens.faint),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ───────────────────────────────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Last · <ago>" reference row — last-session top set
                  _LastTopRow(lastTop: block.lastTop, unit: unit, tokens: tokens),
                  const SizedBox(height: 10),

                  // Column headers: SET / WEIGHT / REPS / RIR / (check btn)
                  Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          'SET',
                          textAlign: TextAlign.center,
                          style: WorkoutType.mono(
                            size: 9.5,
                            color: tokens.faint,
                            letterSpacing: 0.05 * 9.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 100,
                              child: Text(
                                'WEIGHT',
                                textAlign: TextAlign.center,
                                style: WorkoutType.mono(
                                  size: 9.5,
                                  color: tokens.faint,
                                  letterSpacing: 0.05 * 9.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 76,
                              child: Text(
                                'REPS',
                                textAlign: TextAlign.center,
                                style: WorkoutType.mono(
                                  size: 9.5,
                                  color: tokens.faint,
                                  letterSpacing: 0.05 * 9.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 77,
                              child: Text(
                                'RIR',
                                textAlign: TextAlign.center,
                                style: WorkoutType.mono(
                                  size: 9.5,
                                  color: tokens.faint,
                                  letterSpacing: 0.05 * 9.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32), // check btn width
                    ],
                  ),

                  // Set rows
                  ...block.allSets.asMap().entries.map((entry) {
                    final s = entry.value;
                    final workIdx = s.isWarmup
                        ? -1
                        : block.workingSets.indexOf(s) + 1;

                    // Compute live flags: this set is the top working set
                    final isLiveTop = s.done &&
                        !s.isWarmup &&
                        completedTop > 0 &&
                        s.weightKg == completedTop;
                    final isLivePrSet = isLiveTop && isLivePr;

                    return SetRow(
                      key: ValueKey(s.id),
                      set: s,
                      exercise: ex,
                      workIndex: workIdx,
                      unit: unit,
                      isLiveTop: isLiveTop,
                      isLivePr: isLivePrSet,
                      onChanged: (updated) =>
                          widget.onSetChanged(block, updated),
                      onToggleDone: () => widget.onToggleDone(block, s),
                    );
                  }),

                  const SizedBox(height: 8),

                  // Dashed "Add set" button
                  _DashedBlockButton(
                    height: 38,
                    icon: Icons.add,
                    label: 'Add set',
                    tokens: tokens,
                    onTap: () => widget.onAddSet(block),
                  ),

                  // "Remove exercise" button
                  const SizedBox(height: 8),
                  _RemoveExerciseButton(
                    tokens: tokens,
                    onTap: () => widget.onRemoveBlock(block),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Helper sub-widgets ────────────────────────────────────────────────────────

/// Returns a human-readable "days ago" label from an ISO date string
/// (yyyy-mm-dd) compared to today.
///
/// Returns "today", "yesterday", or "{n}d ago".
String _daysAgoLabel(String isoDate) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  try {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    return '${diff}d ago';
  } catch (_) {
    return isoDate;
  }
}

/// Ghosted reference row showing the last-session top set.
///
/// Design: `screen-log.jsx` — "Last · {ago}" label on the left, weight×reps
/// on the right, all in faint/dim mono. If [lastTop] is null, shows a muted
/// "No previous data" placeholder.
class _LastTopRow extends StatelessWidget {
  const _LastTopRow({
    required this.lastTop,
    required this.unit,
    required this.tokens,
  });

  final ({double weight, int reps, String date})? lastTop;
  final UnitService unit;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (lastTop == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
        ),
        child: Row(
          children: [
            Icon(WIcons.history, size: 15, color: tokens.faint),
            const SizedBox(width: 8),
            Text(
              'No previous data',
              style: WorkoutType.mono(
                size: 10.5,
                color: tokens.faint,
                letterSpacing: 0.06 * 10.5,
              ),
            ),
          ],
        ),
      );
    }

    final agoLabel = _daysAgoLabel(lastTop!.date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
      ),
      child: Row(
        children: [
          Icon(WIcons.history, size: 15, color: tokens.faint),
          const SizedBox(width: 8),
          Text(
            'LAST · ${agoLabel.toUpperCase()}',
            style: WorkoutType.mono(
              size: 10.5,
              color: tokens.faint,
              letterSpacing: 0.06 * 10.5,
            ),
          ),
          const Spacer(),
          Text(
            '${unit.fmtWt(lastTop!.weight)}${unit.uLabel} × ${lastTop!.reps}',
            style: WorkoutType.mono(
              size: 12.5,
              weight: FontWeight.w700,
              color: tokens.dim,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBlockButton extends StatelessWidget {
  const _DashedBlockButton({
    required this.height,
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  final double height;
  final IconData icon;
  final String label;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: tokens.lineStrong),
          borderRadius:
              BorderRadius.circular(AppRadius.radius * 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: tokens.dim),
            const SizedBox(width: 6),
            Text(
              label,
              style: WorkoutType.mono(
                size: 12,
                weight: FontWeight.w600,
                color: tokens.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveExerciseButton extends StatelessWidget {
  const _RemoveExerciseButton({
    required this.tokens,
    required this.onTap,
  });

  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, size: 14, color: tokens.faint),
            const SizedBox(width: 6),
            Text(
              'Remove exercise',
              style: WorkoutType.mono(
                size: 11.5,
                weight: FontWeight.w600,
                color: tokens.faint,
                letterSpacing: 0.04 * 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exported for use in ExerciseBlock header
class PRBadgeWidget extends StatelessWidget {
  const PRBadgeWidget({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => PRBadge(small: small);
}

/// Exported for use in ExerciseBlock
class TopTag extends StatelessWidget {
  const TopTag({super.key});
  @override
  Widget build(BuildContext context) =>
      const Tag(label: 'TOP', tone: TagTone.solid);
}
