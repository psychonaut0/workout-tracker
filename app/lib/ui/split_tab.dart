import 'package:flutter/material.dart';

import '../data/day_template_repository.dart';
import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../util/dates.dart';
import '../widgets/dashed_border.dart';

/// The Split sub-tab: a list of training days in rotation.
///
/// [onOpenEditor] is called with the day id to edit (null = new day).
class SplitTab extends StatelessWidget {
  const SplitTab({
    super.key,
    required this.onOpenEditor,
  });

  /// Called with the day id to edit (null = new day).
  final void Function(String? id) onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.tokens;
    final repo = DayTemplateRepository(db);

    return StreamBuilder<List<DayTemplate>>(
      stream: repo.watchDays(),
      builder: (context, snap) {
        final days = snap.data ?? [];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kBottomNavInset),
          children: [
            // Header count
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                l.splitDaysInRotation(days.length),
                style: WorkoutType.mono(size: 11.5, color: tokens.faint),
              ),
            ),

            // Day cards
            ...days.map((day) => _DayCard(
                  day: day,
                  tokens: tokens,
                  onTap: () => onOpenEditor(day.id),
                )),

            if (days.isNotEmpty) const SizedBox(height: 14),

            // "New training day" dashed button
            _NewDayButton(
              tokens: tokens,
              onTap: () => onOpenEditor(null),
            ),
          ],
        );
      },
    );
  }
}

// ── Day card ──────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.tokens,
    required this.onTap,
  });

  final DayTemplate day;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Guard nullable scheduledWeekday — weekdayShort is non-nullable and
    // indexes an unguarded array.
    final weekBadge = (day.scheduledWeekday != null &&
            day.scheduledWeekday! >= 0 &&
            day.scheduledWeekday! <= 6)
        ? weekdayShort(day.scheduledWeekday!,
            Localizations.localeOf(context).toLanguageTag())
        : '–';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(AppRadius.radius),
          ),
          child: Row(
            children: [
              // Weekday badge + slot count
              SizedBox(
                width: 42,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekBadge.toUpperCase(),
                      style: WorkoutType.mono(
                        size: 10,
                        color: tokens.faint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.slots.length}',
                      style: WorkoutType.display(
                        size: 15,
                        weight: FontWeight.w700,
                        color: tokens.accent,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                height: 36,
                color: tokens.line,
                margin: const EdgeInsets.symmetric(horizontal: 13),
              ),

              // Name + focus
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      day.name,
                      style: WorkoutType.body(
                        size: 15.5,
                        weight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    if (day.focus != null && day.focus!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        day.focus!,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.mono(
                          size: 11,
                          color: tokens.faint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(WIcons.chevron, size: 16, color: tokens.faint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── New training day button ───────────────────────────────────────────────────

class _NewDayButton extends StatelessWidget {
  const _NewDayButton({required this.tokens, required this.onTap});

  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(
            color: tokens.lineStrong,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(AppRadius.radius),
          color: Colors.transparent,
        ),
        child: CustomPaint(
          painter: DashedBorderPainter(
              color: tokens.lineStrong, radius: AppRadius.radius),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(WIcons.plus, size: 16, color: tokens.dim),
              const SizedBox(width: 7),
              Text(
                l.planNewDay,
                style: WorkoutType.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: tokens.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

