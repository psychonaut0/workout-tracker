import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../util/number_input.dart';
import '../widgets/number_entry_sheet.dart';
import '../widgets/rir_picker.dart';
import '../widgets/ruler_picker.dart';
import 'active_session_controller.dart';

/// The focused set of the workout: weight and reps ruler pickers (a tap on
/// the centre value opens typed entry), the last-session reference, and —
/// for a logged set being corrected — its RIR and a "mark as not done"
/// action. Logging itself is the log bar's job.
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
    // Text keeps the card's inset; the rulers run the card's full width so
    // their ruled edge reads as part of the card, fading into its sides.
    Widget inset(Widget child) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: child);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.8),
        border: Border.all(color: tokens.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inset(Text(label,
              style: WorkoutType.mono(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: tokens.accent,
                  letterSpacing: 0.08 * 10.5))),
          const SizedBox(height: 10),
          inset(Text('${l.sessionColWeight} · ${unit.uLabel.toUpperCase()}', style: caption())),
          RulerPicker(
            key: const Key('live-weight'),
            value: set.weightKg,
            // A fixed fine step — the ruler is fast enough that plate-sized
            // jumps only get in the way. In lb it is exactly one pound, so the
            // whole-pound labels stay evenly spaced.
            step: unit.unit == Unit.lb ? UnitService.toKg(1, Unit.lb) : 0.5,
            max: 500,
            format: (v) => unit.fmtWt(v),
            semanticLabel: '${l.sessionWeight}, ${unit.uLabel}',
            onChanged: (v) {
              set.weightKg = v;
              onChanged();
            },
            onTapValue: () => _typeWeight(context, l),
          ),
          const SizedBox(height: 12),
          inset(Text(l.sessionColReps, style: caption())),
          RulerPicker(
            key: const Key('live-reps'),
            value: set.reps.toDouble(),
            step: 1,
            max: 50,
            itemExtent: 56,
            format: (v) => v.toInt().toString(),
            semanticLabel: l.sessionReps,
            onChanged: (v) {
              set.reps = v.toInt();
              onChanged();
            },
            onTapValue: () => _typeReps(context, l),
          ),
          if (set.done && !set.isWarmup) ...[
            const SizedBox(height: 12),
            inset(Row(
              children: [
                Text(l.sessionColRir, style: caption()),
                const SizedBox(width: 12),
                Expanded(
                  child: RirPicker(
                    value: set.rir,
                    height: 48,
                    onChanged: (v) {
                      set.rir = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            )),
          ],
          const SizedBox(height: 10),
          inset(Text(
            last == null
                ? l.sessionNoPreviousData
                : l.sessionLastRef('${unit.fmtWt(last.weight)}${unit.uLabel}',
                    last.reps, localizedDaysAgo(l, last.date)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkoutType.mono(size: 11.5, color: tokens.dim),
          )),
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

  Future<void> _typeWeight(BuildContext context, AppLocalizations l) async {
    final v = await showNumberEntrySheet(
      context,
      title: '${l.sessionColWeight} · ${unit.uLabel.toUpperCase()}',
      initialText: unit.fmtWt(set.weightKg),
      allowDecimal: true,
      parse: (text) => parseNumberInput(text,
          min: 0, parseDisplay: (d) => UnitService.toKg(d, unit.unit)),
    );
    if (v == null || v == set.weightKg) return;
    set.weightKg = v;
    onChanged();
  }

  Future<void> _typeReps(BuildContext context, AppLocalizations l) async {
    final v = await showNumberEntrySheet(
      context,
      title: l.sessionColReps,
      initialText: '${set.reps}',
      allowDecimal: false,
      parse: (text) => parseNumberInput(text, min: 0),
    );
    if (v == null || v.toInt() == set.reps) return;
    set.reps = v.toInt();
    onChanged();
  }
}
