import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../data/progress_repository.dart';
import '../data/stats_repository.dart';
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
import 'progress_change.dart';

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
  late final StatsRepository _statsRepo;
  late final Stream<List<Exercise>> _catalogStream;

  /// The exercise of the most recent working set, fetched once on open (a
  /// one-shot read, not a watch). Null until it resolves, or if there's no
  /// history.
  String? _lastTrained;

  String? _seriesKey;
  Stream<List<ProgressPoint>>? _seriesStream;

  /// One-entry memo: re-create the series stream only when the selected
  /// exercise actually changes, instead of on every rebuild.
  Stream<List<ProgressPoint>> _seriesFor(String exerciseId) {
    if (_seriesKey != exerciseId || _seriesStream == null) {
      _seriesKey = exerciseId;
      _seriesStream = _progressRepo.watchSeriesFor(exerciseId);
    }
    return _seriesStream!;
  }

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _exerciseRepo = ExerciseRepository(db);
    _progressRepo = ProgressRepository(db);
    _statsRepo = StatsRepository(db);
    _catalogStream = _exerciseRepo.watchCatalog();
    if (widget.initialTarget == null) {
      _statsRepo.lastTrainedExerciseId().then((id) {
        if (!mounted) return;
        setState(() => _lastTrained = id);
      });
    }
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
      stream: _catalogStream,
      builder: (context, snap) {
        final catalog = snap.data ?? const <Exercise>[];

        // Determine the effective target. A user pick (_target) always wins;
        // otherwise default to the last-trained exercise, falling back to the
        // first catalog entry when there's no history or it was deleted.
        String? target = _target ?? defaultProgressExercise(_lastTrained, catalog);

        if (target == bwId) {
          return BodyweightView(onOpenPicker: () => _openPicker(catalog));
        }

        if (target == null) {
          return _EmptyState(onOpenPicker: () => _openPicker(catalog));
        }

        // The catalog stream's first emission is asynchronous, so a screen
        // mounted with a target already set (tapping a PR row on Home remounts
        // this screen with a new key) renders one frame with an EMPTY catalog.
        // Never index into it — that threw "Bad state: No element" on frame one.
        if (catalog.isEmpty) {
          // Distinguish "the catalog stream has not emitted yet" from "the
          // catalog is genuinely empty": the first is a transient frame, the
          // second must stay recoverable via the picker instead of a dead
          // blank screen.
          if (!snap.hasData) return const SizedBox.shrink();
          return _EmptyState(onOpenPicker: () => _openPicker(catalog));
        }

        final exId = target;
        Exercise? found;
        for (final e in catalog) {
          if (e.id == exId) {
            found = e;
            break;
          }
        }
        // Target no longer in the catalog (deleted): fall back to the first
        // alphabetical entry, which is safe now that the list is non-empty.
        final ex = found ?? catalog.first;

        return StreamBuilder<List<ProgressPoint>>(
          stream: _seriesFor(exId),
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
      padding: EdgeInsets.fromLTRB(16, 8 + MediaQuery.paddingOf(context).top, 16, bottomNavInset(context)),
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

        // (4) Chart. Exactly 1 point can't draw a trend, so it gets an
        // explanatory message instead; 0 points keeps LineChart's own
        // existing blank-frame behaviour, and 2+ draws the real chart.
        WCard(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
          child: rawSeries.length == 1
              ? SizedBox(
                  height: 210,
                  child: Center(
                    child: Text(
                      l.progressTrendNeedsMore,
                      textAlign: TextAlign.center,
                      style: WorkoutType.mono(size: 12, color: tokens.faint),
                    ),
                  ),
                )
              : LineChart(
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
          firstTopReps: rawSeries.isNotEmpty ? rawSeries.first.topReps : 0,
          fmtVal: _fmtVal,
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
    required this.firstTopReps,
    required this.fmtVal,
  });

  final List<double> series;
  final Metric metric;
  final String unit;
  final int topReps;
  final int firstTopReps;
  final String Function(double) fmtVal;

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

    // 12wk delta: for Top set, fall back to the rep change when the weight
    // itself didn't move. A WeightChange keeps the unit in the tile's own
    // slot, styled the same as Current/Best; only a RepChange nulls it,
    // since a rep count has no weight unit to show there.
    String delta12wkValue = '—';
    String? delta12wkUnit = unit.isNotEmpty ? unit : null;
    if (series.length >= 2) {
      if (metric.reps) {
        final c = topSetChange(
          prevWeight: first,
          prevReps: firstTopReps,
          curWeight: last,
          curReps: topReps,
        );
        delta12wkValue = changeLabel(l, c, fmtVal: fmtVal);
        if (c is RepChange) delta12wkUnit = null;
      } else {
        delta12wkValue = signedChange(delta, fmtVal, l);
      }
    }

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
                value: delta12wkValue,
                unit: delta12wkUnit,
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
    final l = AppLocalizations.of(context);
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
          final prevEntry = i < reversed.length - 1 ? reversed[i + 1] : null;
          final prevValue = prevEntry?.value;
          final diff = prevValue != null ? v - prevValue : 0.0;
          final isLast = i == reversed.length - 1;

          // Delta label: for Top set, fall back to the rep change when the
          // weight equals the previous session's; otherwise a plain signed
          // value. "same" replaces "=" everywhere, including no-prior-session.
          final String deltaLabel;
          final Color deltaColor;
          if (metric.reps) {
            final c = prevEntry != null
                ? topSetChange(
                    prevWeight: prevEntry.value,
                    prevReps: prevEntry.point.topReps,
                    curWeight: v,
                    curReps: p.topReps,
                  )
                : const NoChange();
            deltaLabel = changeLabel(l, c, fmtVal: fmtVal);
            deltaColor = (c is WeightChange && c.delta > 0) ||
                    (c is RepChange && c.delta > 0)
                ? tokens.accent
                : tokens.faint;
          } else {
            deltaLabel = signedChange(diff, fmtVal, l);
            deltaColor = diff > 0 ? tokens.accent : tokens.faint;
          }

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
                Expanded(
                  child: _ValueLabel(
                    value: fmtVal(v),
                    unit: unit,
                    reps: metric.reps ? p.topReps : null,
                    tokens: tokens,
                  ),
                ),
                const SizedBox(width: 8),
                // PR badge or delta, fixed width so it doesn't move the
                // column when switching metric.
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: metric.pr && p.isPr
                        ? const PRBadge(small: true)
                        : Text(
                            deltaLabel,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WorkoutType.mono(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: deltaColor,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
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
