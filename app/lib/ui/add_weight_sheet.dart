import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../data/bodyweight_repository.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';

/// Shows the "Log bodyweight" modal bottom sheet.
///
/// Seeds the initial value from the last logged entry converted to display
/// units (defaults to 70 kg-equivalent if no entries exist).
///
/// Unit-aware step: 0.1 in kg mode, 0.2 in lb mode.
///
/// Saves via [BodyweightRepository.logBodyweight] and pops the sheet.
/// Captures [Navigator.of] BEFORE the async save to avoid BuildContext-across-
/// async-gap lint issues.
Future<void> showAddWeightSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _AddWeightSheet(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _AddWeightSheet extends StatefulWidget {
  const _AddWeightSheet();

  @override
  State<_AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends State<_AddWeightSheet> {
  late double _val;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Start with a 70 kg default until we read the last entry.
    _val = double.parse(UnitService.fromKg(70.0, Unit.kg).toStringAsFixed(1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      _seeded = true;
      _seedFromLastEntry();
    }
  }

  Future<void> _seedFromLastEntry() async {
    try {
      final rows = await db.getAll(
        'SELECT CAST(weight_kg AS REAL) AS weight '
        'FROM bodyweight_logs ORDER BY date DESC LIMIT 1',
      );
      if (!mounted) return;
      final unitService = context.read<UnitService>();
      // Seed from the last entry, else a unit-aware 70 kg-equivalent default
      // (a lb user should see ~154, not a raw 70 in the kg slot).
      final kg =
          rows.isNotEmpty ? (rows.first['weight'] as num).toDouble() : 70.0;
      final display = UnitService.fromKg(kg, unitService.unit);
      setState(() {
        _val = double.parse(display.toStringAsFixed(1));
      });
    } catch (_) {
      // Keep the initState default on error.
    }
  }

  void _bump(int dir) {
    final unitService = context.read<UnitService>();
    final step = unitService.unit == Unit.lb ? 0.2 : 0.1;
    setState(() {
      final next = _val + dir * step;
      _val = double.parse(next.clamp(0, double.infinity).toStringAsFixed(2));
    });
  }

  Future<void> _save() async {
    // Capture navigator BEFORE the await (BuildContext-across-async-gap lint).
    final nav = Navigator.of(context);
    final unitService = context.read<UnitService>();
    final kg = UnitService.toKg(_val, unitService.unit);
    await BodyweightRepository(db).logBodyweight(
      dateIso: isoDate(DateTime.now()),
      kg: kg,
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final unitService = context.watch<UnitService>();
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final unit = unitService.uLabel;
    final today = isoDate(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.radius * 1.5),
        ),
        border: Border(
          top: BorderSide(color: tokens.lineStrong, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        34 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: tokens.lineStrong,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),

          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.bodyweightLogTitle,
                style: WorkoutType.display(
                  size: 19,
                  weight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              Text(
                fmtDate(
                  today,
                  Localizations.localeOf(context).toLanguageTag(),
                  weekday: true,
                ),
                style: WorkoutType.mono(size: 11.5, color: tokens.faint),
              ),
            ],
          ),

          // Stepper + value row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Minus button
                _RoundButton(
                  icon: WIcons.minus,
                  onTap: () => _bump(-1),
                ),
                const SizedBox(width: 22),

                // Value display
                SizedBox(
                  width: 150,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _val.toStringAsFixed(1),
                        style: WorkoutType.display(
                          size: 52,
                          weight: FontWeight.w700,
                          color: tokens.text,
                          letterSpacing: 52 * -0.03,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: WorkoutType.mono(size: 16, color: tokens.dim),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 22),
                // Plus button
                _RoundButton(
                  icon: WIcons.plus,
                  onTap: () => _bump(1),
                ),
              ],
            ),
          ),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: tokens.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                padding: EdgeInsets.zero,
              ),
              onPressed: _save,
              child: Text(
                l.bodyweightSaveEntry,
                style: WorkoutType.display(
                  size: 16,
                  weight: FontWeight.w700,
                  color: tokens.accentInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── RoundButton ───────────────────────────────────────────────────────────────

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.surface3,
          border: Border.all(color: t.lineStrong),
        ),
        child: Icon(icon, size: 22, color: t.text),
      ),
    );
  }
}
