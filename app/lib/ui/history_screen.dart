import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../util/group_by_week.dart';
import '../widgets/card.dart';
import '../widgets/pr_badge.dart';

/// The History tab — sessions grouped by ISO week, expandable to per-exercise
/// top sets.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final SessionRepository _sessionRepo;
  late final ExerciseRepository _exerciseRepo;

  @override
  void initState() {
    super.initState();
    _sessionRepo = SessionRepository(db);
    _exerciseRepo = ExerciseRepository(db);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the unit changes.
    final units = context.watch<UnitService>();
    final tokens = context.tokens;

    return StreamBuilder<List<HistorySessionRow>>(
      stream: _sessionRepo.watchSessionStats(),
      builder: (context, sessionSnap) {
        final sessions = sessionSnap.data ?? [];

        // Build catalog map once (one-shot; catalog rarely changes).
        return FutureBuilder<List<Exercise>>(
          future: _exerciseRepo.all(),
          builder: (context, catalogSnap) {
            final catalog = catalogSnap.data ?? [];
            final catalogMap = {for (final e in catalog) e.id: e};

            return _buildBody(context, tokens, units, sessions, catalogMap);
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    WorkoutTokens tokens,
    UnitService units,
    List<HistorySessionRow> sessions,
    Map<String, Exercise> catalogMap,
  ) {
    // ── Header data ─────────────────────────────────────────────────────────
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 28));
    final recent = sessions
        .where(
          (s) => DateTime.parse('${s.date}T00:00:00').isAfter(
            cutoff.subtract(const Duration(seconds: 1)),
          ),
        )
        .toList();

    final monthPrs = recent.fold<int>(0, (sum, s) => sum + s.prCount);
    final monthTonnageKg =
        recent.fold<double>(0, (sum, s) => sum + s.tonnageKg);
    final monthVolDisplay = () {
      final converted = UnitService.fromKg(monthTonnageKg, units.unit) / 1000;
      final suffix = units.uLabel == 'kg' ? 't' : 'k';
      return '${converted.toStringAsFixed(1)}$suffix';
    }();

    // ── Week grouping ────────────────────────────────────────────────────────
    final groups = groupByWeek<HistorySessionRow>(sessions, (r) => r.date);
    final weekKeys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

    // ── Build ────────────────────────────────────────────────────────────────
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // Header
        _Header(sessionCount: sessions.length, tokens: tokens),
        const SizedBox(height: 18),

        // 4-week summary
        _SummaryRow(
          sessionCount: recent.length,
          prCount: monthPrs,
          volumeDisplay: monthVolDisplay,
          tokens: tokens,
        ),
        const SizedBox(height: 24),

        // Empty state
        if (sessions.isEmpty)
          Center(
            child: Text(
              'No sessions yet',
              style: WorkoutType.mono(size: 13, color: tokens.faint),
            ),
          ),

        // Week sections
        for (final wk in weekKeys) ...[
          _WeekHeader(
            weekKey: wk,
            sessions: groups[wk]!,
            tokens: tokens,
          ),
          const SizedBox(height: 10),
          for (final session in groups[wk]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: SessionCard(
                session: session,
                catalogMap: catalogMap,
                sessionRepo: _sessionRepo,
                units: units,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.sessionCount, required this.tokens});

  final int sessionCount;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$sessionCount sessions logged',
          style: WorkoutType.mono(
            size: 11.5,
            color: tokens.faint,
            letterSpacing: 0.06 * 11.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'History',
          style: WorkoutType.display(
            size: 28,
            weight: FontWeight.w700,
            color: tokens.text,
            letterSpacing: 28 * -0.02,
          ),
        ),
      ],
    );
  }
}

// ── 4-week summary ────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.sessionCount,
    required this.prCount,
    required this.volumeDisplay,
    required this.tokens,
  });

  final int sessionCount;
  final int prCount;
  final String volumeDisplay;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Sessions', '$sessionCount'),
      ('PRs', '$prCount'),
      ('Volume', volumeDisplay),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              label: cards[i].$1,
              value: cards[i].$2,
              tokens: tokens,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.tokens,
  });

  final String label;
  final String value;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        border: Border.all(color: tokens.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: WorkoutType.display(
              size: 23,
              weight: FontWeight.w700,
              color: tokens.text,
              letterSpacing: 23 * -0.025,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$label · 4wk',
            style: WorkoutType.mono(
              size: 9.5,
              color: tokens.faint,
              letterSpacing: 0.07 * 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Week header ───────────────────────────────────────────────────────────────

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weekKey,
    required this.sessions,
    required this.tokens,
  });

  final String weekKey;
  final List<HistorySessionRow> sessions;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    final prs = sessions.fold<int>(0, (sum, s) => sum + s.prCount);
    final countLabel =
        '${sessions.length} session${sessions.length == 1 ? '' : 's'}${prs > 0 ? ' · $prs PR' : ''}';

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'WEEK OF ${fmtDate(weekKey).toUpperCase()}',
            style: WorkoutType.mono(
              size: 11,
              weight: FontWeight.w600,
              color: tokens.faint,
              letterSpacing: 0.08 * 11,
            ),
          ),
          Text(
            countLabel,
            style: WorkoutType.mono(size: 10.5, color: tokens.dim),
          ),
        ],
      ),
    );
  }
}

// ── SessionCard ───────────────────────────────────────────────────────────────

class SessionCard extends StatefulWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.catalogMap,
    required this.sessionRepo,
    required this.units,
  });

  final HistorySessionRow session;
  final Map<String, Exercise> catalogMap;
  final SessionRepository sessionRepo;
  final UnitService units;

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final session = widget.session;
    final date = DateTime.parse('${session.date}T00:00:00');

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    // Parse split_label into name + focus parts.
    final label = session.splitLabel ?? '';
    final dotIdx = label.indexOf(' · ');
    final labelName = dotIdx >= 0 ? label.substring(0, dotIdx) : label;
    final labelFocus = dotIdx >= 0 ? label.substring(dotIdx + 3) : null;

    return WCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.radius),
        child: Column(
          children: [
            // ── Tappable header ──────────────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Date block
                    SizedBox(
                      width: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${date.day}',
                            style: WorkoutType.display(
                              size: 20,
                              weight: FontWeight.w700,
                              color: tokens.text,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            months[date.month - 1].toUpperCase(),
                            style: WorkoutType.mono(
                              size: 9.5,
                              color: tokens.faint,
                              letterSpacing: 0.04 * 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Vertical divider
                    Container(
                      width: 1,
                      height: 44,
                      color: tokens.line,
                      margin: const EdgeInsets.symmetric(horizontal: 13),
                    ),

                    // Middle: split label + meta row
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Split label
                          if (label.isEmpty)
                            Text(
                              '—',
                              style: WorkoutType.body(
                                size: 14.5,
                                weight: FontWeight.w600,
                                color: tokens.text,
                              ),
                            )
                          else
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: labelName,
                                    style: WorkoutType.body(
                                      size: 14.5,
                                      weight: FontWeight.w600,
                                      color: tokens.text,
                                    ),
                                  ),
                                  if (labelFocus != null)
                                    TextSpan(
                                      text: ' · $labelFocus',
                                      style: WorkoutType.body(
                                        size: 14.5,
                                        weight: FontWeight.w500,
                                        color: tokens.faint,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          // Meta row
                          Row(
                            children: [
                              Text(
                                '${session.exerciseCount} ex',
                                style: WorkoutType.mono(
                                  size: 10.5,
                                  color: tokens.faint,
                                ),
                              ),
                              if (session.durationMin != null) ...[
                                const SizedBox(width: 12),
                                Text(
                                  '${session.durationMin}m',
                                  style: WorkoutType.mono(
                                    size: 10.5,
                                    color: tokens.faint,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 12),
                              Text(
                                daysAgo(session.date),
                                style: WorkoutType.mono(
                                  size: 10.5,
                                  color: tokens.faint,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // PR badge (if any)
                    if (session.prCount > 0) ...[
                      const SizedBox(width: 8),
                      const PRBadge(small: true),
                    ],

                    // Chevron
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        WIcons.chevron,
                        size: 16,
                        color: tokens.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded exercise blocks ──────────────────────────────────────
            if (_expanded) _ExerciseBlocks(session: widget.session, catalogMap: widget.catalogMap, sessionRepo: widget.sessionRepo, units: widget.units),
          ],
        ),
      ),
    );
  }
}

// ── Expanded exercise blocks ──────────────────────────────────────────────────

class _ExerciseBlocks extends StatelessWidget {
  const _ExerciseBlocks({
    required this.session,
    required this.catalogMap,
    required this.sessionRepo,
    required this.units,
  });

  final HistorySessionRow session;
  final Map<String, Exercise> catalogMap;
  final SessionRepository sessionRepo;
  final UnitService units;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FutureBuilder<List<ExerciseBlockData>>(
      future: sessionRepo
          .setsForSession(session.id)
          .then(sessionRepo.groupIntoBlocks),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.faint,
                ),
              ),
            ),
          );
        }

        final blocks = snap.data ?? [];
        if (blocks.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            children: [
              Divider(color: tokens.line, height: 1, thickness: 1),
              const SizedBox(height: 8),
              for (final block in blocks) _BlockRow(block: block, catalogMap: catalogMap, units: units),
            ],
          ),
        );
      },
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.catalogMap,
    required this.units,
  });

  final ExerciseBlockData block;
  final Map<String, Exercise> catalogMap;
  final UnitService units;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final exercise = catalogMap[block.exerciseId];
    final isCompound = exercise?.compound ?? false;
    final name = exercise?.name ?? block.exerciseId;
    final dotColor = isCompound ? tokens.accent : tokens.lineStrong;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Compound dot
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: dotColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),

          // Exercise name
          Expanded(
            child: Text(
              name,
              style: WorkoutType.body(size: 13, color: tokens.dim),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),

          // PR bolt
          if (block.isPr) ...[
            const SizedBox(width: 6),
            Icon(WIcons.bolt, size: 13, color: tokens.accent),
          ],

          // Weight × reps
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: units.fmtWt(block.topWeight),
                  style: WorkoutType.mono(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
                TextSpan(
                  text: units.uLabel,
                  style: WorkoutType.mono(
                    size: 9.5,
                    color: tokens.faint,
                  ),
                ),
                TextSpan(
                  text: ' ×${block.topReps}',
                  style: WorkoutType.mono(
                    size: 12.5,
                    color: tokens.faint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
