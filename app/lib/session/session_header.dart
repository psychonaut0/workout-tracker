import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import 'active_session_controller.dart';

/// "Next · …" for the header rest row: the live set, or finishing.
String restNextLabel(AppLocalizations l, UnitService unit, LiveSet? live) {
  if (live == null) return l.sessionRestNext(l.sessionFinishWorkout);
  final s = live.set;
  final weight = '${unit.fmtWt(s.weightKg)}${unit.uLabel}';
  final name = live.block.exercise.name;
  return l.sessionRestNext(s.isWarmup
      ? l.sessionNextWarmup(name, weight, s.reps)
      : l.sessionNextSet(name, live.block.workingSets.indexOf(s) + 1, weight, s.reps));
}

/// The live workout's sticky header: minimize, title and set count, the ⋯
/// menu and elapsed time; under it the progress bar, which becomes a thicker
/// draining rest countdown while resting, with a rest row (countdown, what is
/// next, +30s / Skip). Replaces the old floating rest card, so nothing ever
/// covers the exercise list.
class SessionHeader extends StatelessWidget {
  const SessionHeader({
    super.key,
    required this.draft,
    required this.elapsed,
    required this.doneWork,
    required this.totalWork,
    required this.prCount,
    required this.restStart,
    required this.restTotal,
    required this.nextLabel,
    required this.onMinimize,
    required this.onMenu,
    required this.onAdd30s,
    required this.onSkip,
  });

  final SessionDraft draft;
  final Duration elapsed;
  final int doneWork;
  final int totalWork;
  final int prCount;
  final DateTime? restStart;
  final int restTotal;
  final String nextLabel;
  final VoidCallback onMinimize;
  final VoidCallback onMenu;
  final VoidCallback onAdd30s;
  final VoidCallback onSkip;

  /// Threshold (inclusive) for the final-seconds accent.
  static const _finalThreshold = 5;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final prText = prCount > 0 ? l.sessionPrCount(prCount) : '';
    final setsText = '${l.sessionSetsProgress(doneWork, totalWork)}$prText';
    final mm = elapsed.inMinutes;
    final ss = elapsed.inSeconds % 60;

    final start = restStart;
    final remaining = start == null
        ? 0
        : (restTotal - DateTime.now().difference(start).inSeconds).clamp(0, restTotal);
    final resting = start != null && remaining > 0;
    final progress = totalWork > 0 ? doneWork / totalWork : 0.0;
    final barFraction =
        resting ? (restTotal > 0 ? remaining / restTotal : 0.0) : progress.clamp(0.0, 1.0);

    Widget circleButton({required Key key, required String label, required VoidCallback onTap, required Widget icon}) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surface,
                    border: Border.all(color: tokens.line),
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
              ),
            ),
          ),
        );

    return Container(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
            child: Row(
              children: [
                circleButton(
                  key: const Key('session-minimize'),
                  label: l.sessionMinimize,
                  onTap: onMinimize,
                  icon: Transform.rotate(
                    angle: 1.5708,
                    child: Icon(WIcons.chevron, size: 18, color: tokens.dim),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: WorkoutType.display(
                              size: 18, weight: FontWeight.w700, color: tokens.text),
                          children: [
                            TextSpan(text: draft.name),
                            if (draft.focus.isNotEmpty)
                              TextSpan(
                                text: ' · ${draft.focus}',
                                style: WorkoutType.display(
                                    size: 18, weight: FontWeight.w600, color: tokens.faint),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(setsText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkoutType.mono(size: 11, color: tokens.faint)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$mm:${ss.toString().padLeft(2, '0')}',
                        style: WorkoutType.mono(
                            size: 18, weight: FontWeight.w700, color: tokens.accent)),
                    const SizedBox(height: 2),
                    Text(l.sessionElapsed,
                        style: WorkoutType.mono(
                            size: 9, color: tokens.faint, letterSpacing: 0.06 * 9)),
                  ],
                ),
                const SizedBox(width: 4),
                circleButton(
                  key: const Key('session-menu'),
                  label: l.sessionWorkoutOptions,
                  onTap: onMenu,
                  icon: Icon(WIcons.more, size: 18, color: tokens.dim),
                ),
              ],
            ),
          ),
          if (resting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Row(
                children: [
                  Text(l.restLabel,
                      style: WorkoutType.mono(
                          size: 10, color: tokens.faint, letterSpacing: 0.08 * 10)),
                  const SizedBox(width: 8),
                  AnimatedDefaultTextStyle(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.curve,
                    style: WorkoutType.display(
                      size: 20,
                      weight: FontWeight.w700,
                      color: remaining <= _finalThreshold ? tokens.accent : tokens.text,
                    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    child: Text('${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(nextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.mono(size: 11, color: tokens.dim)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _RestChip(
                      key: const Key('rest-add'),
                      label: l.restAdd30s,
                      filled: false,
                      tokens: tokens,
                      onTap: onAdd30s,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: _RestChip(
                      key: const Key('rest-skip'),
                      label: l.commonSkip,
                      filled: true,
                      tokens: tokens,
                      onTap: onSkip,
                    ),
                  ),
                ],
              ),
            ),
          // Progress bar; while resting, a thicker draining countdown whose
          // fraction glides linearly between the one-second ticks.
          AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            height: resting ? 6 : 3,
            color: tokens.surface3,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: barFraction),
              duration: Motion.of(context, const Duration(seconds: 1)),
              curve: Curves.linear,
              builder: (_, value, __) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: tokens.accent),
              ),
            ),
          ),
          Container(height: 1, color: tokens.line),
        ],
      ),
    );
  }
}

class _RestChip extends StatelessWidget {
  const _RestChip({
    super.key,
    required this.label,
    required this.filled,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: filled ? tokens.accent : null,
          border: filled ? null : Border.all(color: tokens.lineStrong),
          borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
        ),
        alignment: Alignment.center,
        // Fixed sizing widens beyond 56dp for longer translations (e.g. the
        // German "Überspringen"); ellipsize instead of forcing the row to
        // overflow at small widths / large text scale.
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkoutType.mono(
                size: 12,
                weight: FontWeight.w700,
                color: filled ? tokens.accentInk : tokens.dim)),
      ),
    );
  }
}
