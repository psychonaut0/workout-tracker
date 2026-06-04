import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/pr_badge.dart';
import '../widgets/rir_picker.dart';
import '../widgets/stepper.dart';
import '../widgets/tag.dart';
import 'active_session_controller.dart';

/// A single row representing one set in an exercise block.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `SetRow`.
///
/// Not-done: index cell + [WStepper] (weight) + [WStepper] (reps) +
///   [RirPicker] (or empty spacer for warm-ups) + check button.
/// Done: static "{weight}{unit} × {reps}  RIR {rir}" + [PRBadge] or TOP [Tag]
///   + check button (toggles back to not-done).
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.exercise,
    required this.workIndex,
    required this.unit,
    required this.isLiveTop,
    required this.isLivePr,
    required this.onChanged,
    required this.onToggleDone,
  });

  final SetState set;
  final Exercise exercise;

  /// For working sets: 1-based index (1, 2, 3…). -1 for warm-ups.
  final int workIndex;

  final UnitService unit;

  /// Whether this set is the live top-set (done, not warm-up, highest weight
  /// among done working sets). Computed by the parent block.
  final bool isLiveTop;

  /// Whether this set beats the all-time best (isLiveTop && weight > bestKg).
  final bool isLivePr;

  final void Function(SetState updated) onChanged;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final done = set.done;

    return Opacity(
      opacity: set.isWarmup && !done ? 0.7 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            // ── Index cell ───────────────────────────────────────────────
            SizedBox(
              width: 26,
              child: set.isWarmup
                  ? Text(
                      'W',
                      textAlign: TextAlign.center,
                      style: WorkoutType.mono(
                        size: 11,
                        color: tokens.faint,
                      ),
                    )
                  : Text(
                      '$workIndex',
                      textAlign: TextAlign.center,
                      style: WorkoutType.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: done ? tokens.accent : tokens.dim,
                      ),
                    ),
            ),
            const SizedBox(width: 6),

            // ── Main content ─────────────────────────────────────────────
            // The two states' subtrees fully diverge (steppers row vs static
            // value + badges). Cross-fade + rise between them; AnimatedSize
            // absorbs any height delta.
            Expanded(
              child: AnimatedSize(
                duration: Motion.of(context, Motion.base),
                curve: Motion.curve,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.base),
                  switchInCurve: Motion.curve,
                  switchOutCurve: Motion.curve,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(done),
                    child: done
                        ? _DoneContent(
                            set: set,
                            unit: unit,
                            isLivePr: isLivePr,
                            isLiveTop: isLiveTop,
                            tokens: tokens,
                          )
                        : _EditContent(
                            set: set,
                            exercise: exercise,
                            unit: unit,
                            tokens: tokens,
                            onChanged: onChanged,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // ── Check button ─────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!done) {
                  // Toggling TO done: PR landing gets the heaviest impact.
                  if (isLivePr) {
                    HapticFeedback.heavyImpact();
                    context.read<AmbientController>().bloom();
                  } else {
                    HapticFeedback.mediumImpact();
                  }
                } else {
                  HapticFeedback.selectionClick();
                }
                onToggleDone();
              },
              child: _Pop(
                trigger: done,
                child: Container(
                  width: 32,
                  height: 34,
                  decoration: BoxDecoration(
                    color: done ? tokens.accent : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppRadius.radius * 0.45),
                    border: done
                        ? null
                        : Border.all(
                            color: tokens.lineStrong, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    WIcons.check,
                    size: 16,
                    color: done ? tokens.accentInk : tokens.faint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit-mode content (steppers + RIR picker) ─────────────────────────────────

class _EditContent extends StatelessWidget {
  const _EditContent({
    required this.set,
    required this.exercise,
    required this.unit,
    required this.tokens,
    required this.onChanged,
  });

  final SetState set;
  final Exercise exercise;
  final UnitService unit;
  final WorkoutTokens tokens;
  final void Function(SetState) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Weight stepper (flex 100, matching the WEIGHT column header)
        Expanded(
          flex: 100,
          child: WStepper(
            value: set.weightKg,
            step: exercise.plateStepKg,
            format: (v) => unit.fmtWt(v),
            editable: true,
            parseDisplay: (v) => UnitService.toKg(v, unit.unit),
            onChanged: (v) {
              set.weightKg = v;
              onChanged(set);
            },
          ),
        ),
        const SizedBox(width: 8),

        // Reps stepper (flex 76)
        Expanded(
          flex: 76,
          child: WStepper(
            value: set.reps.toDouble(),
            step: 1,
            format: (v) => v.toInt().toString(),
            onChanged: (v) {
              set.reps = v.toInt();
              onChanged(set);
            },
          ),
        ),
        const SizedBox(width: 8),

        // RIR picker (flex 77) or empty spacer for warm-ups
        Expanded(
          flex: 77,
          child: set.isWarmup
              ? const SizedBox.shrink()
              : RirPicker(
                  value: set.rir,
                  onChanged: (v) {
                    set.rir = v;
                    onChanged(set);
                  },
                ),
        ),
      ],
    );
  }
}

// ── Done-mode content (static summary + badge) ────────────────────────────────

class _DoneContent extends StatelessWidget {
  const _DoneContent({
    required this.set,
    required this.unit,
    required this.isLivePr,
    required this.isLiveTop,
    required this.tokens,
  });

  final SetState set;
  final UnitService unit;
  final bool isLivePr;
  final bool isLiveTop;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Weight
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: unit.fmtWt(set.weightKg),
                style: WorkoutType.mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              TextSpan(
                text: unit.uLabel,
                style: WorkoutType.mono(size: 11, color: tokens.faint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // × separator
        Text('×', style: TextStyle(color: tokens.faint, fontSize: 12)),
        const SizedBox(width: 8),

        // Reps
        Text(
          '${set.reps}',
          style: WorkoutType.mono(
            size: 15,
            weight: FontWeight.w700,
            color: tokens.text,
          ),
        ),

        // RIR (only for working sets)
        if (!set.isWarmup) ...[
          const SizedBox(width: 8),
          Text(
            'RIR ${set.rir ?? 0}',
            style: WorkoutType.mono(size: 10.5, color: tokens.faint),
          ),
        ],

        const Spacer(),

        // PR badge or TOP tag
        if (isLivePr)
          const PRBadge(small: true)
        else if (isLiveTop)
          const Tag(label: 'TOP', tone: TagTone.solid),
      ],
    );
  }
}

// ── One-shot pop on done ──────────────────────────────────────────────────────

/// Scales its child up to 1.15 and back when [trigger] flips false → true.
class _Pop extends StatefulWidget {
  const _Pop({required this.trigger, required this.child});
  final bool trigger; // pops when this flips false -> true
  final Widget child;
  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.fast, value: 1.0);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _c, curve: Motion.curve));

  @override
  void didUpdateWidget(_Pop old) {
    super.didUpdateWidget(old);
    if (!old.trigger && widget.trigger &&
        !MediaQuery.of(context).disableAnimations) {
      _c.forward(from: 0.0);
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
