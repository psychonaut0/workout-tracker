import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/bodyweight_repository.dart';
import '../data/day_template_repository.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/muscle_target_repository.dart';
import '../data/session_repository.dart';
import '../data/stats_repository.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../theme/icons.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../widgets/card.dart';
import '../widgets/section_label.dart';
import '../widgets/sparkline.dart';
import '../widgets/split_card.dart';
import '../widgets/stat_tile.dart';
import '../widgets/volume_bars.dart';
import '../widgets/week_strip.dart';

/// The Today dashboard — the landing screen of the app.
///
/// Composes 6 sections:
///   1. Greeting header (avatar, date, 'Ready to train')
///   2. SplitCard hero pager (split picker + Start button)
///   3. This week (WeekStrip)
///   4. Stat tiles (bodyweight / sets·wk / PRs·wk)
///   5. Recent PRs (up to 4 rows)
///   6. Weekly volume (VolumeBars vs targets)
///
/// All repos are instantiated from the global [db]. Stream-fed sections are
/// wrapped in [StreamBuilder] and degrade gracefully when data is absent.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.onStart,
    required this.onOpenExercise,
    required this.onOpenProfile,
  });

  /// Called when the user taps Start on a SplitCard slide.
  /// Receives the chosen [DayTemplate], or null for a custom session.
  final void Function(DayTemplate?) onStart;

  /// Called when the user taps a Recent PR row or the bodyweight tile.
  final void Function(String exId) onOpenExercise;

  /// Called when the user taps the avatar.
  final VoidCallback onOpenProfile;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  // ── Repositories ─────────────────────────────────────────────────────────────
  late final StatsRepository _stats;
  late final BodyweightRepository _bw;
  late final MuscleTargetRepository _targets;
  late final DayTemplateRepository _days;
  late final SessionRepository _sessions;
  late final ExerciseRepository _exercises;

  // ── nextInRotation resolved once; refreshed reactively via stream ─────────────
  DayTemplate? _nextDay;
  bool _rotationLoaded = false;

  // ── Session map: templateId → most-recent session date ───────────────────────
  // Populated from watchRecentSessions to provide per-day "last trained" labels.
  List<SessionSummaryRow> _recentSessions = [];

  // ── Stream subscriptions ──────────────────────────────────────────────────────
  StreamSubscription<List<SessionSummaryRow>>? _sessionsSub;
  StreamSubscription<List<DayTemplate>>? _daysSub;

  // ── Current days list (for SplitCard + WeekStrip) ────────────────────────────
  List<DayTemplate> _dayList = [];

  @override
  void initState() {
    super.initState();
    _stats = StatsRepository(db);
    _bw = BodyweightRepository(db);
    _targets = MuscleTargetRepository(db);
    _days = DayTemplateRepository(db);
    _sessions = SessionRepository(db);
    _exercises = ExerciseRepository(db);

    // Subscribe to sessions so we can derive per-day "lastAgo".
    _sessionsSub = _sessions.watchRecentSessions(limit: 100).listen((rows) {
      if (mounted) setState(() => _recentSessions = rows);
    });

    // Subscribe to day templates so we can recompute nextInRotation on change.
    _daysSub = _days.watchDays().listen((days) async {
      if (!mounted) return;
      // Find next-in-rotation from current session history.
      final lastId = _recentSessions.isEmpty
          ? null
          : _recentSessions
              .firstWhere(
                (s) => s.dayTemplateId != null,
                orElse: () => _recentSessions.first,
              )
              .dayTemplateId;
      final next = selectNextDay(days, lastId);
      if (mounted) {
        setState(() {
          _dayList = days;
          _nextDay = next;
          _rotationLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _daysSub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Returns the most-recent session date (ISO string) for a given
  /// [dayTemplateId], or null if that day has never been trained.
  String? _lastDateForDay(String dayId) {
    for (final s in _recentSessions) {
      if (s.dayTemplateId == dayId) return s.date;
    }
    return null;
  }

  /// Returns the 0-based weekday index (Mon=0 … Sun=6) for today.
  int get _todayMon0 => DateTime.now().weekday - 1;

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reactive unit service — rebuild whenever unit changes.
    final units = context.watch<UnitService>();
    final tokens = context.tokens;
    final now = DateTime.now();
    final ws = weekStart(now);

    // Derive a "train day" label: the first scheduled day that matches today,
    // if any, otherwise 'Rest day'.
    final todayMon0 = _todayMon0;
    final trainDay = _dayList.firstWhere(
      (d) => d.scheduledWeekday == todayMon0,
      orElse: () => DayTemplate(
        id: '',
        name: '',
        focus: null,
        scheduledWeekday: null,
        position: 0,
        slots: const [],
      ),
    );
    final restOrTrain = trainDay.id.isEmpty
        ? 'Rest day'
        : trainDay.name;

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8 + MediaQuery.paddingOf(context).top,
        bottom: 96,
      ),
      children: [
        // ── 1. Greeting header ────────────────────────────────────────────────
        _GreetingHeader(
          dateLabel: '${fmtDate(isoDate(now), weekday: true)} · $restOrTrain',
          onTapProfile: widget.onOpenProfile,
        ),
        const SizedBox(height: 18),

        // ── 2. SplitCard hero ─────────────────────────────────────────────────
        if (_rotationLoaded) ...[
          _buildSplitCard(),
          const SizedBox(height: 22),
        ] else ...[
          // Loading placeholder — avoids layout jump when data arrives.
          const SizedBox(height: 290),
          const SizedBox(height: 22),
        ],

        // ── 3. This week ──────────────────────────────────────────────────────
        SectionLabel(label: 'This week'),
        const SizedBox(height: 10),
        _buildWeekStrip(ws),
        const SizedBox(height: 22),

        // ── 4. Stat tiles ──────────────────────────────────────────────────────
        _buildStatTiles(units, tokens, ws),
        const SizedBox(height: 22),

        // ── 5. Recent PRs ──────────────────────────────────────────────────────
        _buildRecentPrs(units, tokens),
        const SizedBox(height: 22),

        // ── 6. Weekly volume ───────────────────────────────────────────────────
        _buildWeeklyVolume(ws, tokens),
      ],
    );
  }

  // ── Section builders ──────────────────────────────────────────────────────────

  Widget _buildSplitCard() {
    // Build SplitCard entries: exerciseCount from slots, lastAgo from sessions.
    final entries = _dayList.map((day) {
      final lastDate = _lastDateForDay(day.id);
      final lastAgo = lastDate != null ? daysAgo(lastDate) : '—';
      return (
        day: day,
        exerciseCount: day.slots.length,
        lastAgo: lastAgo,
      );
    }).toList();

    // nextIndex: find _nextDay in entries, default 0.
    int nextIndex = 0;
    if (_nextDay != null) {
      final idx = entries.indexWhere((e) => e.day.id == _nextDay!.id);
      if (idx >= 0) nextIndex = idx;
    }

    return SplitCard(
      days: entries,
      nextIndex: nextIndex,
      onStart: widget.onStart,
    );
  }

  Widget _buildWeekStrip(DateTime ws) {
    // Compute which days were trained this week.
    final wsIso = isoDate(ws);
    final trainedIds = <String>{};
    for (final s in _recentSessions) {
      if (s.dayTemplateId != null && s.date.compareTo(wsIso) >= 0) {
        trainedIds.add(s.dayTemplateId!);
      }
    }

    final chips = _dayList.map((day) {
      return (
        name: day.name,
        weekday: day.scheduledWeekday,
        isNext: _nextDay?.id == day.id,
        done: trainedIds.contains(day.id),
      );
    }).toList();

    return WeekStrip(days: chips);
  }

  Widget _buildStatTiles(
    UnitService units,
    WorkoutTokens tokens,
    DateTime ws,
  ) {
    return StreamBuilder<List<BodyweightEntry>>(
      stream: _bw.watchSeriesAsc(),
      builder: (context, bwSnap) {
        final bwEntries = bwSnap.data ?? [];
        final lastUpTo18 = bwEntries.length > 18
            ? bwEntries.sublist(bwEntries.length - 18)
            : bwEntries;
        final hasBw = bwEntries.isNotEmpty;
        final bwValue = hasBw ? units.fmtWt(bwEntries.last.weightKg) : '—';
        final bwUnit = hasBw ? units.uLabel : null;
        final sparkValues = lastUpTo18.map((e) => e.weightKg).toList();

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, // was .start
            children: [
            // Bodyweight tile
            Expanded(
              child: StatTile(
                label: 'Bodyweight',
                value: bwValue,
                unit: bwUnit,
                spark: sparkValues.length >= 2
                    ? Sparkline(
                        values: sparkValues,
                        stroke: tokens.dim,
                      )
                    : null,
                onTap: () => widget.onOpenExercise('__bodyweight__'),
              ),
            ),
            const SizedBox(width: 10),
            // Sets/wk tile — nested streams
            Expanded(
              child: StreamBuilder<int>(
                stream: _stats.watchSetsThisWeek(weekStart: ws),
                builder: (context, setsSnap) {
                  return StreamBuilder<int>(
                    stream: _stats.watchDistinctMusclesThisWeek(weekStart: ws),
                    builder: (context, musclesSnap) {
                      final sets = setsSnap.data ?? 0;
                      final muscles = musclesSnap.data ?? 0;
                      return StatTile(
                        label: 'Sets / wk',
                        value: '$sets',
                        sub: 'across $muscles muscles',
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            // PRs/wk tile
            Expanded(
              child: StreamBuilder<int>(
                stream: _stats.watchPrsThisWeek(weekStart: ws),
                builder: (context, prsSnap) {
                  final prs = prsSnap.data ?? 0;
                  return StatTile(
                    label: 'PRs / wk',
                    value: '$prs',
                    sub: 'new top sets',
                  );
                },
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildRecentPrs(UnitService units, WorkoutTokens tokens) {
    return StreamBuilder<
        List<({String exerciseId, double weight, int reps, String date})>>(
      stream: _stats.watchRecentPrs(limit: 6),
      builder: (context, prsSnap) {
        final allPrs = prsSnap.data ?? [];
        final displayPrs = allPrs.take(4).toList();
        final count = allPrs.length;

        return StreamBuilder<List<Exercise>>(
          stream: _exercises.watchCatalog(),
          builder: (context, exSnap) {
            final exMap = {
              for (final ex in (exSnap.data ?? [])) ex.id: ex,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(
                  label: 'Recent PRs',
                  action: Text(
                    '$count',
                    style: WorkoutType.mono(
                      size: 11,
                      color: tokens.dim,
                    ),
                  ),
                ),
                if (displayPrs.isEmpty) ...[
                  const SizedBox(height: 10),
                  _EmptyState(tokens: tokens, message: 'No PRs yet this cycle'),
                ] else ...[
                  const SizedBox(height: 10),
                  Column(
                    children: [
                      for (final pr in displayPrs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PrRow(
                            pr: pr,
                            exercise: exMap[pr.exerciseId],
                            units: units,
                            tokens: tokens,
                            onTap: () =>
                                widget.onOpenExercise(pr.exerciseId),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWeeklyVolume(DateTime ws, WorkoutTokens tokens) {
    return StreamBuilder<List<({String muscle, int sets})>>(
      stream: _stats.watchWeeklyVolumeByMuscle(weekStart: ws),
      builder: (context, volSnap) {
        return StreamBuilder<List<MuscleTarget>>(
          stream: _targets.watchTargets(),
          builder: (context, targetSnap) {
            final volRows = volSnap.data ?? [];
            final targetList = targetSnap.data ?? [];

            // Build a lookup: muscle → targetSets
            final targetMap = {
              for (final t in targetList) t.muscle: t.targetSets,
            };

            // LEFT-merge volume with targets; coalesce missing target to sets
            // so VolumeBars never sees null and goalless muscles show on-target.
            final rows = volRows.map((v) {
              final target = targetMap[v.muscle] ?? v.sets;
              return (muscle: v.muscle, sets: v.sets, target: target);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(label: 'Weekly volume'),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  _EmptyState(
                    tokens: tokens,
                    message: 'No sets logged this week',
                  )
                else
                  VolumeBars(rows: rows),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Greeting header ───────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.dateLabel,
    required this.onTapProfile,
  });

  final String dateLabel;
  final VoidCallback onTapProfile;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar — 46px accent circle with initials placeholder
        GestureDetector(
          onTap: onTapProfile,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.accent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'A',
                style: WorkoutType.display(
                  size: 18,
                  weight: FontWeight.w700,
                  color: tokens.accentInk,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 13),
        // Date + greeting text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateLabel.toUpperCase(),
                style: WorkoutType.mono(
                  size: 11.5,
                  color: tokens.faint,
                  letterSpacing: 11.5 * 0.06,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Ready to train',
                style: WorkoutType.display(
                  size: 25,
                  weight: FontWeight.w700,
                  color: tokens.text,
                  letterSpacing: 25 * -0.02,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── PR row ────────────────────────────────────────────────────────────────────

class _PrRow extends StatelessWidget {
  const _PrRow({
    required this.pr,
    required this.exercise,
    required this.units,
    required this.tokens,
    required this.onTap,
  });

  final ({String exerciseId, double weight, int reps, String date}) pr;
  final Exercise? exercise;
  final UnitService units;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = exercise?.name ?? pr.exerciseId;

    return WCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: onTap,
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.surface3,
              borderRadius: BorderRadius.circular(AppRadius.radius * 0.55),
            ),
            child: Icon(
              WIcons.bolt,
              size: 18,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 12),
          // Exercise name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: WorkoutType.body(
                    size: 14,
                    weight: FontWeight.w600,
                    color: tokens.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  fmtDate(pr.date, weekday: true),
                  style: WorkoutType.mono(
                    size: 11,
                    color: tokens.faint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Weight + reps
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: units.fmtWt(pr.weight),
                      style: WorkoutType.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                    TextSpan(
                      text: units.uLabel,
                      style: WorkoutType.mono(
                        size: 11,
                        color: tokens.dim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '×${pr.reps}',
                style: WorkoutType.mono(
                  size: 10.5,
                  color: tokens.faint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

/// A small muted placeholder shown when a section has no data yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens, required this.message});

  final WorkoutTokens tokens;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          message,
          style: WorkoutType.mono(size: 11, color: tokens.faint),
        ),
      ),
    );
  }
}
