import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/muscle_target_repository.dart';
import '../data/muscles.dart';
import '../identity/identity_service.dart';
import '../l10n/app_localizations.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/stepper.dart';

/// The Targets sub-tab: edit weekly per-muscle set goals.
///
/// Streams [MuscleTargetRepository.watchTargets], keys rows by muscle, and
/// renders a presentational [TargetsList]. Edits persist live via
/// [MuscleTargetRepository.setTarget] (0 = no goal / deletes the row).
class TargetsTab extends StatelessWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MuscleTargetRepository(db);

    return StreamBuilder<List<MuscleTarget>>(
      stream: repo.watchTargets(),
      builder: (context, snap) {
        final byMuscle = {
          for (final t in snap.data ?? const <MuscleTarget>[]) t.muscle: t,
        };

        return TargetsList(
          targets: byMuscle,
          onChanged: (muscle, sets) => repo.setTarget(
            muscle: muscle,
            sets: sets,
            userId: context.read<IdentityService>().currentUserId,
            existing: byMuscle[muscle],
          ),
        );
      },
    );
  }
}

/// Presentational list of weekly muscle targets — one row per canonical muscle.
///
/// [targets] maps muscle key → its current [MuscleTarget] (absent = no goal).
/// [onChanged] reports `(muscle, newSets)` on each stepper change.
class TargetsList extends StatelessWidget {
  const TargetsList({
    super.key,
    required this.targets,
    required this.onChanged,
  });

  final Map<String, MuscleTarget> targets;
  final void Function(String muscle, int sets) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, kBottomNavInset),
      children: [
        for (final entry in kMuscleLabels.entries)
          _TargetRow(
            muscle: entry.key,
            sets: targets[entry.key]?.targetSets ?? 0,
            tokens: tokens,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.muscle,
    required this.sets,
    required this.tokens,
    required this.onChanged,
  });

  final String muscle;
  final int sets;
  final WorkoutTokens tokens;
  final void Function(String muscle, int sets) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasGoal = sets > 0;
    final labelColor = hasGoal ? tokens.text : tokens.faint;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(AppRadius.radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localizedMuscle(context, muscle),
                    style: WorkoutType.body(
                      size: 15.5,
                      weight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasGoal ? l.targetsSetsPerWeek : l.targetsNoGoal,
                    style: WorkoutType.mono(size: 11, color: tokens.faint),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: WStepper(
                value: sets.toDouble(),
                step: 1,
                format: (v) => v.round() == 0 ? '—' : v.round().toString(),
                onChanged: (v) => onChanged(muscle, v.round().clamp(0, 40)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
