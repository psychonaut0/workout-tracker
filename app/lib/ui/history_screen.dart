import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/pressable.dart';
import '../data/finished_session_store.dart';
import '../session/resume.dart';
import '../session/session_manager.dart';
import '../shell/session_launcher.dart';
import 'exercise_sheet.dart';
import '../util/dates.dart';
import '../util/group_by_week.dart';
import '../widgets/card.dart';
import '../widgets/pr_badge.dart';
import '../widgets/rir_picker.dart';
import '../widgets/stepper.dart';
import '../widgets/w_dialog.dart';

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
  // Catalog loaded once per screen mount (not re-queried on every stats
  // emission — it changes far less often than the session stream).
  late final Future<List<Exercise>> _catalog;
  late final Stream<List<HistorySessionRow>> _statsStream =
      _sessionRepo.watchSessionStats();

  @override
  void initState() {
    super.initState();
    _sessionRepo = SessionRepository(db);
    _exerciseRepo = ExerciseRepository(db);
    _catalog = _exerciseRepo.all();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the unit changes.
    final units = context.watch<UnitService>();
    final tokens = context.tokens;

    // Only what the cards need: the manager also notifies on every set tick
    // and rest change of a running workout.
    final (activeSessionId, lastFinished) =
        context.select<SessionManager, (String?, FinishedSession?)>(
            (m) => (m.active?.draftOrNull?.sessionId, m.lastFinished));

    return StreamBuilder<List<HistorySessionRow>>(
      stream: _statsStream,
      builder: (context, sessionSnap) {
        final sessions = sessionSnap.data ?? [];

        // Build catalog map once (one-shot; catalog rarely changes).
        return FutureBuilder<List<Exercise>>(
          future: _catalog,
          builder: (context, catalogSnap) {
            final catalog = catalogSnap.data ?? [];
            final catalogMap = {for (final e in catalog) e.id: e};

            return _buildBody(context, tokens, units, sessions, catalogMap,
                activeSessionId, lastFinished);
          },
        );
      },
    );
  }

  /// The card's Resume action. The state is re-derived at tap time: the card
  /// may have been built before the resume window closed.
  Future<void> _onResume(String sessionId) async {
    final manager = context.read<SessionManager>();
    final state = resumeStateFor(
      activeSessionId: manager.active?.draftOrNull?.sessionId,
      lastFinished: manager.lastFinished,
      sessionId: sessionId,
      now: DateTime.now(),
    );
    switch (resumeTapAction(state, hasActive: manager.hasActive)) {
      case ResumeTapAction.openRunning:
        await openActiveSession(context, manager);
      case ResumeTapAction.forgetExpired:
        // Expired since the card was built: forgetting it notifies, and this
        // screen rebuilds without the button.
        manager.forgetFinished(sessionId);
      case ResumeTapAction.blockedByActive:
        final l = AppLocalizations.of(context);
        await showWDialog<void>(
          context,
          title: l.historyResumeBlockedTitle,
          message: l.historyResumeBlockedMessage,
          actions: [WDialogAction(label: l.commonOk, value: null)],
        );
      case ResumeTapAction.resume:
        await resumeFinishedSession(context, sessionId);
    }
  }

  Widget _buildBody(
    BuildContext context,
    WorkoutTokens tokens,
    UnitService units,
    List<HistorySessionRow> sessions,
    Map<String, Exercise> catalogMap,
    String? activeSessionId,
    FinishedSession? lastFinished,
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
      padding: EdgeInsets.fromLTRB(16, 8 + MediaQuery.paddingOf(context).top, 16, kBottomNavInset),
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
              AppLocalizations.of(context).historyEmpty,
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
              key: ValueKey(session.id),
              padding: const EdgeInsets.only(bottom: 9),
              child: SessionCard(
                session: session,
                catalogMap: catalogMap,
                sessionRepo: _sessionRepo,
                units: units,
                resumeState: resumeStateFor(
                  activeSessionId: activeSessionId,
                  lastFinished: lastFinished,
                  sessionId: session.id,
                  now: now,
                ),
                onResume: () => _onResume(session.id),
                onDeleted: () =>
                    context.read<SessionManager>().forgetFinished(session.id),
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
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.historySessionsLogged(sessionCount),
          style: WorkoutType.mono(
            size: 11.5,
            color: tokens.faint,
            letterSpacing: 0.06 * 11.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          l.historyTitle,
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
    final l = AppLocalizations.of(context);
    // (label, displayValue, intValue?) — intValue animates via CountUp when set.
    final cards = <(String, String, int?)>[
      (l.historySummarySessions, '$sessionCount', sessionCount),
      (l.historySummaryPrs, '$prCount', prCount),
      (l.historySummaryVolume, volumeDisplay, null),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              label: cards[i].$1,
              value: cards[i].$2,
              intValue: cards[i].$3,
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
    this.intValue,
  });

  final String label;
  final String value;
  final int? intValue;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    final intValue = this.intValue;
    if (intValue != null) {
      return CountUp(
        value: intValue,
        builder: (v) => _build(context, '$v'),
      );
    }
    return _build(context, value);
  }

  Widget _build(BuildContext context, String value) {
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
            AppLocalizations.of(context).historySummarySuffix(label),
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
    final l = AppLocalizations.of(context);
    final prs = sessions.fold<int>(0, (sum, s) => sum + s.prCount);
    final countLabel = l.historyWeekSessions(sessions.length) +
        (prs > 0 ? l.sessionPrCount(prs) : '');

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l.historyWeekOf(fmtDate(
              weekKey,
              Localizations.localeOf(context).toLanguageTag(),
            ).toUpperCase()),
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
    this.resumeState = SessionResumeState.none,
    this.onResume,
    this.onDeleted,
  });

  final HistorySessionRow session;
  final Map<String, Exercise> catalogMap;
  final SessionRepository sessionRepo;
  final UnitService units;

  /// What the expanded footer offers (see [SessionResumeState]).
  final SessionResumeState resumeState;
  final VoidCallback? onResume;

  /// Called after the session was deleted from this card.
  final VoidCallback? onDeleted;

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final session = widget.session;
    final date = DateTime.parse('${session.date}T00:00:00');
    final monthLabel = DateFormat.MMM(localeName).format(date);

    // Parse split_label into name + focus parts.
    final label = session.splitLabel ?? '';
    final dotIdx = label.indexOf(' · ');
    final labelName = dotIdx >= 0 ? label.substring(0, dotIdx) : label;
    final labelFocus = dotIdx >= 0 ? label.substring(dotIdx + 3) : null;

    return PressableScale(
      child: WCard(
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
                            monthLabel.toUpperCase(),
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
                                AppLocalizations.of(context)
                                    .historyExerciseCountShort(
                                        session.exerciseCount),
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
                                localizedDaysAgo(l, session.date),
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
                      duration: Motion.of(context, const Duration(milliseconds: 150)),
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
            AnimatedSize(
              duration: Motion.of(context, Motion.base),
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? _ExerciseBlocks(
                      session: widget.session,
                      catalogMap: widget.catalogMap,
                      sessionRepo: widget.sessionRepo,
                      units: widget.units,
                      resumeState: widget.resumeState,
                      onResume: widget.onResume,
                      onDeleted: widget.onDeleted,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Expanded exercise blocks ──────────────────────────────────────────────────

class _ExerciseBlocks extends StatefulWidget {
  const _ExerciseBlocks({
    required this.session,
    required this.catalogMap,
    required this.sessionRepo,
    required this.units,
    required this.resumeState,
    this.onResume,
    this.onDeleted,
  });

  final HistorySessionRow session;
  final Map<String, Exercise> catalogMap;
  final SessionRepository sessionRepo;
  final UnitService units;
  final SessionResumeState resumeState;
  final VoidCallback? onResume;
  final VoidCallback? onDeleted;

  @override
  State<_ExerciseBlocks> createState() => _ExerciseBlocksState();
}

class _ExerciseBlocksState extends State<_ExerciseBlocks> {
  late Future<List<ExerciseBlockData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ExerciseBlocks oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every watchSessionStats emission follows a commit on sessions/sets and
    // builds NEW row objects (reListenable does not dedupe), so a new object
    // means this session's sets may have changed — including RIR or warm-up
    // changes no aggregate reflects, like a resumed workout finished again.
    if (!identical(oldWidget.session, widget.session)) _future = _load();
  }

  Future<List<ExerciseBlockData>> _load() => widget.sessionRepo
      .setsForSession(widget.session.id)
      .then(groupSetsIntoBlocks);

  /// Quiet reload: the FutureBuilder keeps showing the previous blocks until
  /// the new ones arrive, so the card never blanks to a spinner or replays
  /// its Reveal rows.
  void _reload() => setState(() => _future = _load());

  /// Opens the per-exercise set editor, then reloads.
  Future<void> _editExercise(ExerciseBlockData block) async {
    final exercise = widget.catalogMap[block.exerciseId];
    if (exercise == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SetEditorSheet(
        block: block,
        exercise: exercise,
        sessionId: widget.session.id,
        sessionRepo: widget.sessionRepo,
        units: widget.units,
      ),
    );
    if (mounted) _reload();
  }

  /// Picks an exercise and seeds one working set so it appears in the session.
  /// The user then taps the new block to edit/add more sets.
  Future<void> _addExercise() async {
    final exId = await showExerciseSheet(
      context,
      exercises: widget.catalogMap.values.toList(),
      current: null,
      showBodyweight: false,
    );
    if (exId == null || exId == kBodyweightSentinel) return;
    final ex = widget.catalogMap[exId];
    await widget.sessionRepo.addSet(
      widget.session.id,
      exId,
      weightKg: '0.00',
      reps: ex?.defaultRepLow ?? 8,
      rir: null,
      isWarmup: false,
    );
    if (mounted) _reload();
  }

  Future<void> _deleteSession() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.historyDeleteSessionTitle,
      message: l.historyDeleteSessionMessage,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    // The watchSessionStats stream updates the list automatically afterwards.
    await widget.sessionRepo.deleteSession(widget.session.id);
    widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FutureBuilder<List<ExerciseBlockData>>(
      future: _future,
      builder: (context, snap) {
        final blocks = snap.data;
        // Spinner only for the very first load; a reload keeps the old data.
        if (blocks == null && snap.connectionState == ConnectionState.waiting) {
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
        final inProgress = widget.resumeState == SessionResumeState.inProgress;
        return SessionCardBody(
          blocks: blocks ?? const [],
          catalogMap: widget.catalogMap,
          units: widget.units,
          resumeState: widget.resumeState,
          onResume: widget.onResume,
          // The running workout is where an in-progress session is edited; a
          // History edit here would be overwritten by its next finish.
          onEditExercise: inProgress ? null : _editExercise,
          onAddExercise: _addExercise,
          onDeleteSession: _deleteSession,
        );
      },
    );
  }
}

/// The expanded body of a [SessionCard]: the per-exercise rows plus the
/// footer actions. Stateless and database-free. The footer renders even for a
/// session with no sets, so it can still be resumed or deleted.
class SessionCardBody extends StatelessWidget {
  const SessionCardBody({
    super.key,
    required this.blocks,
    required this.catalogMap,
    required this.units,
    this.resumeState = SessionResumeState.none,
    this.onResume,
    this.onEditExercise,
    this.onAddExercise,
    this.onDeleteSession,
  });

  final List<ExerciseBlockData> blocks;
  final Map<String, Exercise> catalogMap;
  final UnitService units;
  final SessionResumeState resumeState;
  final VoidCallback? onResume;

  /// Null makes the exercise rows read-only.
  final ValueChanged<ExerciseBlockData>? onEditExercise;
  final VoidCallback? onAddExercise;
  final VoidCallback? onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final edit = onEditExercise;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        children: [
          Divider(color: tokens.line, height: 1, thickness: 1),
          const SizedBox(height: 8),
          for (final block in blocks)
            Reveal(
              key: ValueKey(block.exerciseId),
              child: _BlockRow(
                block: block,
                catalogMap: catalogMap,
                units: units,
                onTap: edit == null ? null : () => edit(block),
              ),
            ),
          const SizedBox(height: 6),
          if (resumeState != SessionResumeState.none)
            _InlineAction(
              key: const ValueKey('history-resume'),
              icon: WIcons.resume,
              label: l.historyResumeWorkout,
              color: tokens.accent,
              onTap: onResume,
            ),
          if (resumeState != SessionResumeState.inProgress) ...[
            _InlineAction(
              key: const ValueKey('history-add-exercise'),
              icon: WIcons.plus,
              label: l.sessionAddExercise,
              color: tokens.accent,
              onTap: onAddExercise,
            ),
            const SizedBox(height: 8),
            Divider(color: tokens.line, height: 1, thickness: 1),
            const SizedBox(height: 8),
            _InlineAction(
              key: const ValueKey('history-delete-session'),
              icon: WIcons.trash,
              label: l.historyDeleteSession,
              color: tokens.danger,
              onTap: onDeleteSession,
              verticalPadding: 0,
            ),
          ],
        ],
      ),
    );
  }
}

/// A centred inline text action (icon + mono label) in the card footer.
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.verticalPadding = 6,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: WorkoutType.mono(size: 11, weight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.catalogMap,
    required this.units,
    this.onTap,
  });

  final ExerciseBlockData block;
  final Map<String, Exercise> catalogMap;
  final UnitService units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final exercise = catalogMap[block.exerciseId];
    final isCompound = exercise?.compound ?? false;
    final name = exercise?.name ?? block.exerciseId;
    final dotColor = isCompound ? tokens.accent : tokens.lineStrong;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
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

            // Edit chevron affordance
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(WIcons.chevron, size: 13, color: tokens.faint),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Set editor sheet ──────────────────────────────────────────────────────────

/// A bottom sheet listing every set of one exercise within a session, with
/// inline editing (weight/reps via [WStepper], rir via [RirPicker]) and a
/// per-set delete. Edits persist immediately via [SessionRepository.updateSet];
/// the weight (stored as a 2dp TEXT string) is written on change.
///
/// Re-derives is_top_set locally on every write (see SessionRepository.updateSet); is_pr is left to the server.
class _SetEditorSheet extends StatefulWidget {
  const _SetEditorSheet({
    required this.block,
    required this.exercise,
    required this.sessionId,
    required this.sessionRepo,
    required this.units,
  });

  final ExerciseBlockData block;
  final Exercise exercise;
  final String sessionId;
  final SessionRepository sessionRepo;
  final UnitService units;

  @override
  State<_SetEditorSheet> createState() => _SetEditorSheetState();
}

class _SetEditorSheetState extends State<_SetEditorSheet> {
  // Local mutable copies, keyed by set id, so the sheet reflects edits/deletes
  // without a refetch while open.
  late List<_EditableSet> _sets;

  @override
  void initState() {
    super.initState();
    _sets = widget.block.sets
        .map((s) => _EditableSet(
              id: s.id,
              weightKg: s.weightKg,
              reps: s.reps,
              rir: s.rir,
              isWarmup: s.isWarmup,
            ))
        .toList();
  }

  Future<void> _persist(_EditableSet s) => widget.sessionRepo.updateSet(
        s.id,
        weightKg: s.weightKg.toStringAsFixed(2),
        reps: s.reps,
        rir: s.rir,
      );

  Future<void> _deleteSet(_EditableSet s) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.historyDeleteSetTitle,
      message: l.historyDeleteSetMessage,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    await widget.sessionRepo.deleteSet(s.id);
    if (!mounted) return;
    setState(() => _sets.removeWhere((e) => e.id == s.id));
  }

  /// Appends a new working set, seeded from the last working set (or the
  /// heaviest existing set) so the user usually only needs minor tweaks.
  Future<void> _addSet() async {
    // This sheet does not own any row's stepper, so nothing else unfocuses an
    // open one on Android (tap-outside only unfocuses for touch on web, and
    // this button's own tap handler never requests focus). Flush focus
    // BEFORE `_sets`/`working` are read below — the stepper's focus-loss
    // listener commits synchronously, so an in-flight edit on the last row
    // lands before it gets read as the seed for the new row.
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    final working = _sets.where((s) => !s.isWarmup).toList();
    final last = working.isNotEmpty
        ? working.last
        : (_sets.isNotEmpty ? _sets.last : null);

    final double w = last?.weightKg ??
        (_sets.isEmpty
            ? 0.0
            : _sets
                .map((s) => s.weightKg)
                .reduce((a, b) => a >= b ? a : b));
    final int r = last?.reps ?? (widget.exercise.defaultRepLow ?? 8);
    final int? rir = working.isNotEmpty ? working.last.rir : null;

    final newId = await widget.sessionRepo.addSet(
      widget.sessionId,
      widget.exercise.id,
      weightKg: w.toStringAsFixed(2),
      reps: r,
      rir: rir,
      isWarmup: false,
    );
    if (!mounted) return;
    setState(() => _sets.add(_EditableSet(
          id: newId,
          weightKg: w,
          reps: r,
          rir: rir,
          isWarmup: false,
        )));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.bg,
          border: Border(top: BorderSide(color: tokens.line)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.lineStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              widget.exercise.name,
              style: WorkoutType.display(
                size: 18,
                weight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.historyEditSets,
              style: WorkoutType.mono(size: 11, color: tokens.faint),
            ),
            const SizedBox(height: 14),

            // Column headers
            Row(
              children: [
                const SizedBox(width: 26),
                const SizedBox(width: 6),
                Expanded(flex: 100, child: _ColLabel(l.sessionColWeight)),
                const SizedBox(width: 8),
                Expanded(flex: 76, child: _ColLabel(l.sessionColReps)),
                const SizedBox(width: 8),
                Expanded(flex: 77, child: _ColLabel(l.sessionColRir)),
                const SizedBox(width: 6),
                const SizedBox(width: 32),
              ],
            ),
            const SizedBox(height: 4),

            // Editable rows (scrollable in case of many sets)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    AnimatedSize(
                      duration: Motion.of(context, Motion.base),
                      curve: Motion.curve,
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          for (var i = 0; i < _sets.length; i++)
                            Reveal(
                              key: ValueKey(_sets[i].id),
                              child: _EditRow(
                                set: _sets[i],
                                // 1-based index across working sets; W for warm-ups.
                                workIndex: _workIndexOf(i),
                                exercise: widget.exercise,
                                units: widget.units,
                                onChanged: () => _persist(_sets[i]),
                                onDelete: () => _deleteSet(_sets[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Add-set affordance.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _addSet,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(WIcons.plus, size: 14, color: tokens.accent),
                            const SizedBox(width: 6),
                            Text(
                              l.sessionAddSet,
                              style: WorkoutType.mono(
                                size: 11,
                                weight: FontWeight.w600,
                                color: tokens.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The 1-based working-set index for the set at [i], or -1 for warm-ups.
  int _workIndexOf(int i) {
    if (_sets[i].isWarmup) return -1;
    var n = 0;
    for (var j = 0; j <= i; j++) {
      if (!_sets[j].isWarmup) n++;
    }
    return n;
  }
}

class _ColLabel extends StatelessWidget {
  const _ColLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: WorkoutType.mono(
        size: 9,
        weight: FontWeight.w600,
        color: tokens.faint,
        letterSpacing: 0.08 * 9,
      ),
    );
  }
}

/// Mutable per-set editing state for the sheet.
class _EditableSet {
  _EditableSet({
    required this.id,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.isWarmup,
  });

  final String id;
  double weightKg;
  int reps;
  int? rir;
  final bool isWarmup;
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    required this.set,
    required this.workIndex,
    required this.exercise,
    required this.units,
    required this.onChanged,
    required this.onDelete,
  });

  final _EditableSet set;
  final int workIndex;
  final Exercise exercise;
  final UnitService units;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          // Index cell
          SizedBox(
            width: 26,
            child: set.isWarmup
                ? Text(
                    AppLocalizations.of(context).sessionWarmupShort,
                    textAlign: TextAlign.center,
                    style: WorkoutType.mono(size: 11, color: tokens.faint),
                  )
                : Text(
                    '$workIndex',
                    textAlign: TextAlign.center,
                    style: WorkoutType.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: tokens.dim,
                    ),
                  ),
          ),
          const SizedBox(width: 6),

          // Weight stepper (kg; formatted for the active unit)
          Expanded(
            flex: 100,
            child: WStepper(
              value: set.weightKg,
              step: exercise.plateStepKg,
              format: (v) => units.fmtWt(v),
              editable: true,
              parseDisplay: (v) => UnitService.toKg(v, units.unit),
              min: 0,
              onChanged: (v) {
                set.weightKg = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),

          // Reps stepper
          Expanded(
            flex: 76,
            child: WStepper(
              value: set.reps.toDouble(),
              step: 1,
              format: (v) => v.toInt().toString(),
              editable: true,
              allowDecimal: false,
              min: 0,
              onChanged: (v) {
                set.reps = v.toInt();
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),

          // RIR picker (empty for warm-ups)
          Expanded(
            flex: 77,
            child: set.isWarmup
                ? const SizedBox.shrink()
                : RirPicker(
                    value: set.rir,
                    onChanged: (v) {
                      set.rir = v;
                      onChanged();
                    },
                  ),
          ),
          const SizedBox(width: 6),

          // Per-set delete
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: SizedBox(
              width: 32,
              height: 34,
              child: Icon(WIcons.trash, size: 17, color: tokens.danger),
            ),
          ),
        ],
      ),
    );
  }
}
