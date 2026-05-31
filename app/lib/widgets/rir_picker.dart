import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A segmented RIR (Reps In Reserve) picker for values 0–3.
///
/// Selected segment = solid accent background + accentInk text.
/// Unselected = surface3 background + dim text.
///
/// Warm-up sets should render an empty [SizedBox] of the same width instead
/// of this widget (the disabled state is handled by the caller, not here).
///
/// Button keys: `rir-<n>` (e.g. `rir-0`, `rir-1`, ...).
///
/// Taps do NOT bubble to enclosing widgets (stopPropagation via
/// [GestureDetector] with [HitTestBehavior.opaque]).
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `RirPicker`.
class RirPicker extends StatelessWidget {
  const RirPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Currently selected RIR value (0–3), or null for no selection.
  final int? value;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (r) {
        final selected = value == r;
        return GestureDetector(
          key: Key('rir-$r'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(r),
          child: Container(
            width: 22,
            height: 30,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: selected ? tokens.accent : tokens.surface3,
              borderRadius:
                  BorderRadius.circular(AppRadius.radius * 0.35),
            ),
            alignment: Alignment.center,
            child: Text(
              '$r',
              style: WorkoutType.mono(
                size: 12,
                weight: FontWeight.w700,
                color: selected ? tokens.accentInk : tokens.dim,
              ),
            ),
          ),
        );
      }),
    );
  }
}
