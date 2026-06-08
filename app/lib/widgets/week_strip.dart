import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../theme/icons.dart';
import '../util/dates.dart';

/// A horizontal row of day chips showing the weekly rotation state.
///
/// Each chip shows the weekday label, the day name, and a status indicator:
///   • `isNext` → accent background + 'NEXT' label
///   • `done`   → surface-3 pill with a check icon
///   • else     → a 5px dot in `lineStrong`
///
/// Visual spec: `screen-today.jsx` → `WeekStrip`.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
  });

  /// Each entry describes one chip in the strip.
  ///
  /// - [name]    — day template name (spaces stripped for display)
  /// - [weekday] — 0-based Monday-origin weekday (0=Mon…6=Sun); used via
  ///               [weekdayShort]. `null` → shows an empty string.
  /// - [isNext]  — highlights this chip in accent as the next scheduled day
  /// - [done]    — shows a check icon (this day was trained this week)
  final List<({String name, int? weekday, bool isNext, bool done})> days;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final chipRadius = AppRadius.radius * 0.7;

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: _DayChip(
              day: days[i],
              tokens: tokens,
              chipRadius: chipRadius,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.tokens,
    required this.chipRadius,
  });

  final ({String name, int? weekday, bool isNext, bool done}) day;
  final WorkoutTokens tokens;
  final double chipRadius;

  @override
  Widget build(BuildContext context) {
    final isNext = day.isNext;
    final isDone = day.done;

    final bgColor = isNext ? tokens.accent : tokens.surface;
    final borderColor = isNext ? Colors.transparent : tokens.line;
    final weekdayLabel =
        day.weekday != null ? weekdayShort(day.weekday!) : '';

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Weekday label
          Text(
            weekdayLabel,
            style: WorkoutType.mono(
              size: 9.5,
              color: isNext
                  ? tokens.accentInk.withValues(alpha: 0.7)
                  : tokens.faint,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Day name (spaces stripped)
          Text(
            day.name.replaceAll(' ', ''),
            style: WorkoutType.display(
              size: 13,
              weight: FontWeight.w700,
              color: isNext ? tokens.accentInk : tokens.text,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Status slot — fixed height 14
          SizedBox(
            height: 14,
            child: Center(
              child: _StatusIndicator(
                isNext: isNext,
                isDone: isDone,
                tokens: tokens,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.isNext,
    required this.isDone,
    required this.tokens,
  });

  final bool isNext;
  final bool isDone;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (isNext) {
      return Text(
        AppLocalizations.of(context).weekStripNext,
        style: WorkoutType.mono(
          size: 9,
          weight: FontWeight.w700,
          color: tokens.accentInk,
          letterSpacing: 0.06 * 9,
        ),
      );
    }
    if (isDone) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: tokens.surface3,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Icon(
          WIcons.check,
          size: 11,
          color: tokens.accent,
        ),
      );
    }
    // Idle dot
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: tokens.lineStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}
