import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../widgets/stepper.dart';
import 'active_session_controller.dart';

/// The focused set of the workout: large weight and reps steppers, the
/// last-session reference, and — for a logged set being corrected — a
/// "mark as not done" action. Logging itself is the log bar's job.
///
/// Weight is held in kg; typed input converts back through
/// [UnitService.toKg] (see the stepper rules in app/CLAUDE.md).
class LiveSetCard extends StatelessWidget {
  const LiveSetCard({
    super.key,
    required this.set,
    required this.exercise,
    required this.workIndex,
    required this.lastTop,
    required this.unit,
    required this.onChanged,
    required this.onMarkNotDone,
  });

  final SetState set;
  final Exercise exercise;

  /// 1-based working-set index; -1 for warm-ups.
  final int workIndex;
  final ({double weight, int reps, String date})? lastTop;
  final UnitService unit;

  /// Called after the card mutates [set] in place.
  final VoidCallback onChanged;
  final VoidCallback onMarkNotDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final base = set.isWarmup ? l.sessionLiveWarmup : l.sessionLiveSet(workIndex);
    final label = set.done ? l.sessionLiveLogged(base) : base;
    final last = lastTop;

    TextStyle caption() => WorkoutType.mono(
        size: 10, color: tokens.faint, letterSpacing: 0.08 * 10);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.8),
        border: Border.all(color: tokens.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: WorkoutType.mono(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: tokens.accent,
                  letterSpacing: 0.08 * 10.5)),
          const SizedBox(height: 10),
          Text('${l.sessionColWeight} · ${unit.uLabel.toUpperCase()}', style: caption()),
          const SizedBox(height: 4),
          WStepper(
            value: set.weightKg,
            step: exercise.plateStepKg,
            format: (v) => unit.fmtWt(v),
            editable: true,
            large: true,
            parseDisplay: (v) => UnitService.toKg(v, unit.unit),
            min: 0,
            onChanged: (v) {
              set.weightKg = v;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Text(l.sessionColReps, style: caption()),
          const SizedBox(height: 4),
          WStepper(
            value: set.reps.toDouble(),
            step: 1,
            format: (v) => v.toInt().toString(),
            editable: true,
            large: true,
            allowDecimal: false,
            min: 0,
            onChanged: (v) {
              set.reps = v.toInt();
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Text(
            last == null
                ? l.sessionNoPreviousData
                : l.sessionLastRef('${unit.fmtWt(last.weight)}${unit.uLabel}',
                    last.reps, localizedDaysAgo(l, last.date)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkoutType.mono(size: 11.5, color: tokens.dim),
          ),
          if (set.done)
            GestureDetector(
              key: const Key('live-mark-not-done'),
              behavior: HitTestBehavior.opaque,
              onTap: onMarkNotDone,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Text(
                    l.sessionMarkNotDone,
                    style: WorkoutType.body(size: 14, weight: FontWeight.w600, color: tokens.dim),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
