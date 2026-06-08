import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../data/progress_repository.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../util/format.dart';
import '../widgets/card.dart';
import '../widgets/line_chart.dart';
import '../widgets/pr_badge.dart';
import '../widgets/progress_widgets.dart';
import '../widgets/section_label.dart';
import 'bodyweight_view.dart';
import 'exercise_sheet.dart';

/// The sentinel value used to represent the Bodyweight target.
const String bwId = '__bodyweight__';

/// Progress tab — shows per-exercise lift progression or [BodyweightView].
///
/// If [initialTarget] is [bwId], opens directly on the Bodyweight view.
/// Otherwise defaults to the first catalog exercise with a logged series,
/// or the first alphabetical exercise if none has history.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.initialTarget});

  final String? initialTarget;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String? _target;
  String _metricId = 'top';

  late final ExerciseRepository _exerciseRepo;
  late final ProgressRepository _progressRepo;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _exerciseRepo = ExerciseRepository(db);
    _progressRepo = ProgressRepository(db);
  }

  Future<void> _openPicker(List<Exercise> catalog) async {
    final r = await showExerciseSheet(
      context,
      exercises: catalog,
      current: _target,
    );
    if (r != null) setState(() => _target = r);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on unit changes.
    context.watch<UnitService>();

    return StreamBuilder<List<Exercise>>(
      stream: _exerciseRepo.watchCatalog(),
      builder: (context, snap) {
        final catalog = snap.data ?? [];

        // Determine the effective target.
        String? target = _target;
        if (target == null && catalog.isNotEmpty) {
          // Default: first exercise that has history; else first alphabetical.
          // Since we can't await inside build, we use the first alphabetical
          // as the default and rely on the stream update for a better pick.
          target = catalog.first.id;
        }

        if (target == bwId) {
          return BodyweightView(onOpenPicker: () => _openPicker(catalog));
        }

        if (target == null) {
          return _EmptyState(onOpenPicker: () => _openPicker(catalog));
        }

        final exId = target;
        final ex = catalog.firstWhere(
          (e) => e.id == exId,
          orElse: () => catalog.first,
        );

        return StreamBuilder<List<ProgressPoint>>(
          stream: _progressRepo.watchSeriesFor(exId),
          builder: (context, seriesSnap) {
            final rawSeries = seriesSnap.data ?? [];
            final unit = context.read<UnitService>();
            final metric =
                kMetrics.firstWhere((m) => m.id == _metricId);

            return _LiftView(
              catalog: catalog,
              exercise: ex,
              metricId: _metricId,
              metric: metric,
              rawSeries: rawSeries,
              unitService: unit,
              onPickerTap: () => _openPicker(catalog),
              onMetricChanged: (id) => setState(() => _metricId = id),
            );
          },
        );
      },
    );
  }
}

// ── LiftView ─────────────────────────────────────────────────────────────────

class _LiftView extends StatelessWidget {
  const _LiftView({
    required this.catalog,
    required this.exercise,
    required this.metricId,
    required this.metric,
    required this.rawSeries,
    required this.unitService,
    required this.onPickerTap,
    required this.onMetricChanged,
  });

  final List<Exercise> catalog;
  final Exercise exercise;
  final String metricId;
  final Metric metric;
  final List<ProgressPoint> rawSeries;
  final UnitService unitService;
  final VoidCallback onPickerTap;
  final ValueChanged<String> onMetricChanged;

  // Build display-unit value for a point under the active metric.
  double _displayValue(ProgressPoint p) {
    if (metricId == 'top') {
      return UnitService.fromKg(p.topWeightKg, unitService.unit);
    } else if (metricId == 'e1rm') {
      return UnitService.fromKg(
          est1rm(p.topWeightKg, p.topReps).toDouble(), unitService.unit);
    } else if (metricId == 'volume') {
      return UnitService.fromKg(p.volumeKg, unitService.unit);
    } else {
      // reps
      return p.topReps.toDouble();
    }
  }

  String _fmtVal(double v) =>
      metricId == 'volume' ? fmtThousands(v) : fmtPlain(v);

  String _signedDelta(double delta) {
    final abs = _fmtVal(delta.abs());
    if (delta > 0) return '+$abs';
    if (delta < 0) return '-$abs';
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final metricName = metricLabel(l, metricId);
    final unit = metric.wt ? unitService.uLabel : '';
    final seriesValues = rawSeries.map(_displayValue).toList();

    // Chart series — values already in display units.
    final chartSeries = List.generate(rawSeries.length, (i) {
      final p = rawSeries[i];
      return (
        date: p.date,
        value: seriesValues[i],
        reps: p.topReps,
        isPr: metric.pr && p.isPr,
      );
    });

    // Subtitle for selector row.
    final muscleStr = localizedMuscle(context, exercise.muscleGroup);
    final equipStr = exercise.equip ?? '';
    final subtitle =
        equipStr.isNotEmpty ? '$muscleStr · $equipStr' : muscleStr;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8 + MediaQuery.paddingOf(context).top, 16, kBottomNavInset),
      children: [
        // (1) Title block
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.progressProgression,
                style: WorkoutType.mono(
                  size: 11.5,
                  color: tokens.faint,
                  letterSpacing: 0.06 * 11.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                l.progressTrend(metricName),
                style: WorkoutType.display(size: 28, weight: FontWeight.w700),
              ),
            ],
          ),
        ),

        // (2) Exercise selector
        ProgressSelectorRow(
          icon: WIcons.dumbbell,
          title: exercise.name,
          subtitle: subtitle,
          onTap: onPickerTap,
        ),
        const SizedBox(height: 14),

        // (3) Metric tabs
        MetricTabs(
          selected: metricId,
          onSelect: onMetricChanged,
        ),
        const SizedBox(height: 14),

        // (4) Chart
        WCard(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
          child: LineChart(
            key: ValueKey('$metricId-$unit'),
            series: chartSeries,
            height: 210,
            unit: unit,
            showReps: metric.reps,
          ),
        ),
        const SizedBox(height: 14),

        // (5) BigStat cards
        _BigStatRow(
          series: seriesValues,
          metric: metric,
          unit: unit,
          topReps: rawSeries.isNotEmpty ? rawSeries.last.topReps : 0,
          fmtVal: _fmtVal,
          signedDelta: _signedDelta,
        ),
        const SizedBox(height: 22),

        // (6) Session log
        SectionLabel(
          label: l.progressBySession(metricName),
          action: Text(
            l.progressSessionsCount(rawSeries.length),
            style: WorkoutType.mono(size: 11, color: tokens.dim),
          ),
        ),
        const SizedBox(height: 8),
        if (rawSeries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l.progressNoSessions,
                style: WorkoutType.mono(size: 13, color: tokens.faint),
              ),
            ),
          )
        else
          _SessionLogCard(
            rawSeries: rawSeries,
            seriesValues: seriesValues,
            metric: metric,
            unit: unit,
            tokens: tokens,
            fmtVal: _fmtVal,
          ),
      ],
    );
  }
}

// ── BigStatRow ────────────────────────────────────────────────────────────────

class _BigStatRow extends StatelessWidget {
  const _BigStatRow({
    required this.series,
    required this.metric,
    required this.unit,
    required this.topReps,
    required this.fmtVal,
    required this.signedDelta,
  });

  final List<double> series;
  final Metric metric;
  final String unit;
  final int topReps;
  final String Function(double) fmtVal;
  final String Function(double) signedDelta;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (series.isEmpty) {
      return Row(
        children: [
          Expanded(child: WCard(child: BigStat(label: l.progressStatCurrent, value: '—', unit: unit))),
          const SizedBox(width: 8),
          Expanded(child: WCard(child: BigStat(label: l.progressStatBest, value: '—', unit: unit, accent: true))),
          const SizedBox(width: 8),
          Expanded(child: WCard(child: BigStat(label: l.progressStat12wkDelta, value: '—', unit: unit))),
        ],
      );
    }

    final last = series.last;
    final first = series.first;
    final best = series.reduce((a, b) => a > b ? a : b);
    final delta = series.length >= 2 ? last - first : 0.0;

    // Current card unit: for the `top` metric, append ' ×{topReps}'
    final currentUnit = metric.reps ? '$unit ×$topReps' : unit;

    return Row(
      children: [
        Expanded(
          child: WCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: UnitSwap(
              unitKey: currentUnit,
              child: BigStat(
                label: l.progressStatCurrent,
                value: fmtVal(last),
                unit: currentUnit.isNotEmpty ? currentUnit : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: WCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: UnitSwap(
              unitKey: unit,
              child: BigStat(
                label: l.progressStatBest,
                value: fmtVal(best),
                unit: unit.isNotEmpty ? unit : null,
                accent: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: WCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: UnitSwap(
              unitKey: unit,
              child: BigStat(
                label: l.progressStat12wkDelta,
                value: series.length >= 2 ? signedDelta(delta) : '—',
                unit: unit.isNotEmpty ? unit : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── SessionLogCard ────────────────────────────────────────────────────────────

class _SessionLogCard extends StatelessWidget {
  const _SessionLogCard({
    required this.rawSeries,
    required this.seriesValues,
    required this.metric,
    required this.unit,
    required this.tokens,
    required this.fmtVal,
  });

  final List<ProgressPoint> rawSeries;
  final List<double> seriesValues;
  final Metric metric;
  final String unit;
  final WorkoutTokens tokens;
  final String Function(double) fmtVal;

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toLanguageTag();
    // Newest first.
    final reversed = List.generate(rawSeries.length, (i) {
      final origIdx = rawSeries.length - 1 - i;
      return (point: rawSeries[origIdx], value: seriesValues[origIdx]);
    });

    return WCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(reversed.length, (i) {
          final entry = reversed[i];
          final p = entry.point;
          final v = entry.value;
          // Previous in the reversed list = older session.
          final prevValue = i < reversed.length - 1 ? reversed[i + 1].value : null;
          final diff = prevValue != null ? v - prevValue : 0.0;
          final isLast = i == reversed.length - 1;

          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: tokens.line, width: 1),
                    ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                // Date
                SizedBox(
                  width: 58,
                  child: Text(
                    fmtDate(p.date, localeName),
                    style: WorkoutType.mono(size: 12, color: tokens.dim),
                  ),
                ),
                const SizedBox(width: 12),
                // Value + reps for top metric
                Flexible(
                  child: _ValueLabel(
                    value: fmtVal(v),
                    unit: unit,
                    reps: metric.reps ? p.topReps : null,
                    tokens: tokens,
                  ),
                ),
                const Spacer(),
                // PR badge or delta
                if (metric.pr && p.isPr)
                  const PRBadge(small: true)
                else if (diff != 0)
                  Text(
                    _signedFmt(diff, fmtVal),
                    style: WorkoutType.mono(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: diff > 0 ? tokens.accent : tokens.faint,
                    ),
                  )
                else
                  Text(
                    '=',
                    style: WorkoutType.mono(size: 11.5, color: tokens.faint),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

String _signedFmt(double delta, String Function(double) fmtVal) {
  final abs = fmtVal(delta.abs());
  return delta > 0 ? '+$abs' : '-$abs';
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({
    required this.value,
    required this.unit,
    required this.reps,
    required this.tokens,
  });

  final String value;
  final String unit;
  final int? reps;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: WorkoutType.mono(
              size: 14,
              weight: FontWeight.w700,
              color: tokens.text,
            ),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: WorkoutType.mono(size: 10, color: tokens.faint),
            ),
          if (reps != null)
            TextSpan(
              text: ' × ${reps!}',
              style: WorkoutType.mono(size: 12, color: tokens.faint),
            ),
        ],
      ),
    );
  }
}

// ── EmptyState ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpenPicker});

  final VoidCallback onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.progressEmpty,
            style: WorkoutType.mono(size: 14, color: tokens.faint),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onOpenPicker,
            child: Text(
              l.progressChooseExercise,
              style: WorkoutType.mono(
                size: 13,
                weight: FontWeight.w600,
                color: tokens.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
