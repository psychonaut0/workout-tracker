import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../widgets/pr_badge.dart';
import '../widgets/w_dialog.dart';
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
    this.onRemoveSet,
    this.onAddWarmup,
    this.onMoveUp,
    this.onMoveDown,
  });

  final BlockState block;
  final UnitService unit;
  final void Function(BlockState, SetState) onToggleDone;
  final void Function(BlockState, SetState) onSetChanged;
  final void Function(BlockState) onAddSet;
  final void Function(BlockState) onRemoveBlock;

  /// Swipe-left removal of a set. Null disables the swipe. A ticked set is
  /// confirmed first; an unticked one goes straight away.
  final void Function(BlockState, SetState)? onRemoveSet;

  /// The "+ Warm-up" button. Null hides it.
  final void Function(BlockState)? onAddWarmup;

  /// Footer reorder arrows. Null renders that arrow disabled (first / last
  /// exercise).
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends State<ExerciseBlock>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// A ticked set holds logged work, so removing it is confirmed (the same
  /// rule as removing an exercise); an unticked set goes without asking.
  Future<bool> _confirmRemoveSet(SetState s) async {
    if (!s.done) return true;
    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.sessionRemoveSetTitle,
      message: l.sessionRemoveSetMessage,
      confirmLabel: l.commonRemove,
      destructive: true,
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
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
            color: block.expanded ? tokens.lineStrong : tokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (always visible) ────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => widget.block.expanded = !widget.block.expanded),
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
                    turns: block.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(WIcons.chevron, size: 18, color: tokens.faint),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ───────────────────────────────────────────
          if (block.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Last · <ago>" reference row — last-session top set
                  _LastTopRow(
                      lastTop: block.lastTop,
                      unit: unit,
                      tokens: tokens,
                      l: l),
                  const SizedBox(height: 10),

                  // Column headers: SET / WEIGHT / REPS / RIR / (check btn)
                  Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          l.sessionColSet,
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
                                l.sessionColWeight,
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
                                l.sessionColReps,
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
                                l.sessionColRir,
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
                  AnimatedSize(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.curve,
                    alignment: Alignment.topCenter,
                    child: Column(
                      children: [
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

                          final row = SetRow(
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
                          final onRemoveSet = widget.onRemoveSet;
                          return Reveal(
                            key: ValueKey(s.id),
                            child: onRemoveSet == null
                                ? row
                                : Dismissible(
                                    key: ValueKey('dismiss-${s.id}'),
                                    direction: DismissDirection.endToStart,
                                    background: _RemoveSetBackground(tokens: tokens),
                                    confirmDismiss: (_) => _confirmRemoveSet(s),
                                    onDismissed: (_) => onRemoveSet(block, s),
                                    child: row,
                                  ),
                          );
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Dashed "+ Warm-up" and "Add set" buttons
                  Row(
                    children: [
                      if (widget.onAddWarmup != null) ...[
                        Expanded(
                          child: _DashedBlockButton(
                            height: 38,
                            icon: Icons.add,
                            label: l.sessionAddWarmup,
                            tokens: tokens,
                            onTap: () => widget.onAddWarmup!(block),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _DashedBlockButton(
                          height: 38,
                          icon: Icons.add,
                          label: l.sessionAddSet,
                          tokens: tokens,
                          onTap: () => widget.onAddSet(block),
                        ),
                      ),
                    ],
                  ),

                  // Reorder arrows + "Remove exercise"
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MoveButton(
                        icon: Icons.keyboard_arrow_up,
                        label: l.sessionMoveUp,
                        tokens: tokens,
                        onTap: widget.onMoveUp,
                      ),
                      _MoveButton(
                        icon: Icons.keyboard_arrow_down,
                        label: l.sessionMoveDown,
                        tokens: tokens,
                        onTap: widget.onMoveDown,
                      ),
                      Expanded(
                        child: _RemoveExerciseButton(
                          tokens: tokens,
                          label: l.sessionRemoveExercise,
                          onTap: () => widget.onRemoveBlock(block),
                        ),
                      ),
                      // Mirrors the two arrows so the label stays centred.
                      const SizedBox(width: 80),
                    ],
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
    required this.l,
  });

  final ({double weight, int reps, String date})? lastTop;
  final UnitService unit;
  final WorkoutTokens tokens;
  final AppLocalizations l;

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
            Flexible(
              child: Text(
                l.sessionNoPreviousData,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkoutType.mono(
                  size: 10.5,
                  color: tokens.faint,
                  letterSpacing: 0.06 * 10.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final agoLabel = localizedDaysAgo(l, lastTop!.date);
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
          Expanded(
            child: Text(
              l.sessionLastLabel(agoLabel.toUpperCase()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkoutType.mono(
                size: 10.5,
                color: tokens.faint,
                letterSpacing: 0.06 * 10.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
            // Two of these share a row: shrink rather than overflow at large
            // text scale or with long translations.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkoutType.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: tokens.dim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red trash background revealed while a set row is swiped left.
class _RemoveSetBackground extends StatelessWidget {
  const _RemoveSetBackground({required this.tokens});

  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: tokens.danger,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
      ),
      child: Icon(WIcons.trash, size: 18, color: tokens.bg),
    );
  }
}

/// One footer reorder arrow; a null [onTap] renders it disabled.
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final WorkoutTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 34,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? tokens.dim : tokens.line,
          ),
        ),
      ),
    );
  }
}

class _RemoveExerciseButton extends StatelessWidget {
  const _RemoveExerciseButton({
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
            // Shares its row with the reorder arrows: shrink rather than
            // overflow on narrow phones or at large text scale.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkoutType.mono(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: tokens.faint,
                  letterSpacing: 0.04 * 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
