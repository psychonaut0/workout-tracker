import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/active_session_draft.dart';
import '../data/exercise_repository.dart';
import '../data/session_repository.dart';
import '../data/session_writer.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_service.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/w_dialog.dart';
import 'active_session_controller.dart';
import 'exercise_block.dart';
import 'exercise_picker_sheet.dart';
import 'rest_timer.dart';
import 'session_manager.dart';
import 'session_summary_screen.dart';

/// Full-bleed overlay for an active workout session.
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `ActiveSession`.
///
/// - Sticky header: back btn (confirm-close if sets done), title
///   `"{name} · {focus}"`, mono `"{doneWork}/{totalWork} sets[· N PR]"`,
///   right-side elapsed `m:ss` accent, 3px progress bar.
/// - Body: ExerciseBlock list + dashed "Add exercise" + "Finish workout" (h52).
/// - Finish wires through `db.writeTransaction(PowerSyncTxExecutor)`.
/// - Rest timer floats above the finish button when active.
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  Timer? _ticker;

  // Captured references so the ticker/dispose can reach the manager and
  // controller without a BuildContext.
  SessionManager? _manager;
  ActiveSessionController? _controller;

  // Haptic guards: fire once per countdown. Re-armed (cleared) when +30s pushes
  // remaining back above the respective threshold.
  bool _tickHapticFired = false; // 3s remaining → selectionClick
  bool _buzzHapticFired = false; // 0s remaining → vibrate

  @override
  void initState() {
    super.initState();
    // 1-second ticker that forces a rebuild for the elapsed counter and rest timer.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _handleRestHaptics();
      // Screen-open rest revert: when remaining hits 0 while the screen is
      // open, stop the rest here (the OS alarm covers the backgrounded case;
      // the deleted SessionManager Dart timer used to cover this one).
      // stopRest is a guarded no-op if already stopped.
      final c = _controller;
      final start = c?.restStart;
      if (c != null && start != null) {
        final remaining =
            c.restTotal - DateTime.now().difference(start).inSeconds;
        if (remaining <= 0) c.stopRest();
      }
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionManager>().screenOpen = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager = context.read<SessionManager>();
    _controller = context.read<ActiveSessionController>();
  }

  /// Fires countdown haptics at the 3s and 0s thresholds, once each, and
  /// re-arms the guards if +30s lifts remaining back above a threshold.
  void _handleRestHaptics() {
    final c = _controller;
    final start = c?.restStart;
    if (c == null || start == null) return;
    final elapsed = DateTime.now().difference(start).inSeconds;
    final remaining = c.restTotal - elapsed;

    // Re-arm guards when +30s pushes remaining back above the thresholds.
    if (remaining > 3) _tickHapticFired = false;
    if (remaining > 0) _buzzHapticFired = false;

    if (remaining <= 3 && remaining > 0 && !_tickHapticFired) {
      _tickHapticFired = true;
      HapticFeedback.selectionClick();
    }
    if (remaining <= 0 && !_buzzHapticFired) {
      _buzzHapticFired = true;
      HapticFeedback.vibrate();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _manager?.screenOpen = false;
    super.dispose();
  }

  // ── Back / close handling ─────────────────────────────────────────────────

  Future<void> _handleClose(
      BuildContext context, ActiveSessionController controller) async {
    final hasDone = controller.draft.blocks
        .any((b) => b.allSets.any((s) => s.done));

    if (!hasDone) {
      controller.discard();
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.sessionDiscardTitle,
      message: l.sessionDiscardMessage,
      cancelLabel: l.sessionKeepGoing,
      confirmLabel: l.commonDiscard,
      destructive: true,
    );

    if (confirmed == true) {
      controller.discard();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  // ── Finish handling ───────────────────────────────────────────────────────

  Future<void> _handleFinish(
      BuildContext context, ActiveSessionController controller) async {
    final draftStore = DraftStore();
    try {
      final sessionId = await db.writeTransaction(
        (tx) => controller.finish(
          PowerSyncTxExecutor(tx),
          draftStore: draftStore,
        ),
      );
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SessionSummaryScreen(sessionId: sessionId),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).sessionSaveFailed('$e')),
            backgroundColor: context.tokens.danger,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ActiveSessionController>();
    final tokens = context.tokens;
    final unit = context.watch<UnitService>();
    final l = AppLocalizations.of(context);

    if (!controller.hasSession) {
      // Should not normally be seen; the screen is only pushed when a session
      // is already built.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final draft = controller.draft;
    final elapsed = controller.elapsed;
    final mm = elapsed.inMinutes;
    final ss = elapsed.inSeconds % 60;
    final doneWork = controller.doneWork;
    final totalWork = controller.totalWork;
    final prCount = controller.prCount;
    final progress = totalWork > 0 ? doneWork / totalWork : 0.0;

    // Compute rest timer remaining
    int restRemaining = 0;
    if (controller.restStart != null) {
      final elapsed2 =
          DateTime.now().difference(controller.restStart!).inSeconds;
      restRemaining = controller.restTotal - elapsed2;
      if (restRemaining <= 0) {
        // Auto-dismiss on next frame
        WidgetsBinding.instance.addPostFrameCallback((_) => controller.stopRest());
        restRemaining = 0;
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // ── Sticky header ────────────────────────────────────────────
              _Header(
                draft: draft,
                mm: mm,
                ss: ss,
                doneWork: doneWork,
                totalWork: totalWork,
                prCount: prCount,
                progress: progress,
                tokens: tokens,
                l: l,
                onMinimize: () => Navigator.of(context).pop(),
                onDiscard: () => _handleClose(context, controller),
              ),

              // ── Scrollable body ──────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
                  children: [
                    // Empty-session placeholder
                    if (draft.blocks.isEmpty) ...[
                      const SizedBox(height: 40),
                      _EmptySessionPlaceholder(tokens: tokens, l: l),
                      const SizedBox(height: 20),
                    ],

                    // Exercise blocks
                    for (final block in draft.blocks)
                      Reveal(
                        key: ValueKey(block.exercise.id),
                        child: ExerciseBlock(
                          block: block,
                          unit: unit,
                          onToggleDone: (b, s) {
                            final wasDone = s.done;
                            controller.toggleDone(b, s);
                            // Start rest timer when a working set is completed.
                            // Resolve duration: per-exercise override, else the
                            // global compound/isolation default from Settings.
                            if (!wasDone && !s.isWarmup) {
                              final settings = context.read<SettingsService>();
                              controller.startRest(
                                b.exercise.defaultRestSeconds ??
                                    (b.exercise.compound
                                        ? settings.restCompoundSeconds
                                        : settings.restIsolationSeconds),
                              );
                            }
                          },
                          onSetChanged: (b, s) => controller.markChanged(),
                          onAddSet: (b) => controller.addSet(b),
                          onRemoveBlock: (b) async {
                            final hasDone = b.allSets.any((s) => s.done);
                            if (hasDone) {
                              final confirmed = await showWConfirm(
                                context,
                                title: l.sessionRemoveExerciseTitle,
                                message: l.sessionRemoveExerciseMessage,
                                confirmLabel: l.commonRemove,
                                destructive: true,
                              );
                              if (confirmed == true) controller.removeBlock(b);
                            } else {
                              controller.removeBlock(b);
                            }
                          },
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Dashed "Add exercise" button
                    _DashedButton(
                      height: 46,
                      icon: WIcons.plus,
                      label: l.sessionAddExercise,
                      tokens: tokens,
                      onTap: () async {
                        final repo = ExerciseRepository(db);
                        final all = await repo.all();
                        if (!context.mounted) return;
                        final picked = await showExercisePicker(
                          context,
                          exercises: all,
                        );
                        if (picked != null) {
                          await controller.addBlock(
                            picked,
                            sessionRepo: SessionRepository(db),
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    // "Finish workout" button
                    _FinishButton(
                      canFinish: controller.canFinish,
                      label: l.sessionFinishWorkout,
                      tokens: tokens,
                      onTap: () => _handleFinish(context, controller),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Floating rest timer ──────────────────────────────────────────
          if (controller.restStart != null && restRemaining > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: 44,
              child: RestTimerCard(
                totalSeconds: controller.restTotal,
                startTime: controller.restStart!,
                onAdd30s: () => controller.addRestTime(30),
                onDismiss: controller.stopRest,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.draft,
    required this.mm,
    required this.ss,
    required this.doneWork,
    required this.totalWork,
    required this.prCount,
    required this.progress,
    required this.tokens,
    required this.l,
    required this.onMinimize,
    required this.onDiscard,
  });

  final SessionDraft draft;
  final int mm;
  final int ss;
  final int doneWork;
  final int totalWork;
  final int prCount;
  final double progress;
  final WorkoutTokens tokens;
  final AppLocalizations l;
  final VoidCallback onMinimize;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final prText = prCount > 0 ? l.sessionPrCount(prCount) : '';
    final setsText = '${l.sessionSetsProgress(doneWork, totalWork)}$prText';

    return Container(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status-bar padding
          SizedBox(height: MediaQuery.of(context).padding.top + 8),

          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                // Minimize button (chevron down)
                GestureDetector(
                  onTap: onMinimize,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.surface,
                      border: Border.all(color: tokens.line),
                    ),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: 1.5708,
                      child: Icon(WIcons.chevron,
                          size: 18, color: tokens.dim),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Title + sets counter
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: WorkoutType.display(
                              size: 18,
                              weight: FontWeight.w700,
                              color: tokens.text),
                          children: [
                            TextSpan(text: draft.name),
                            if (draft.focus.isNotEmpty) ...[
                              TextSpan(
                                text: ' · ${draft.focus}',
                                style: WorkoutType.display(
                                    size: 18,
                                    weight: FontWeight.w600,
                                    color: tokens.faint),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        setsText,
                        style: WorkoutType.mono(
                            size: 11, color: tokens.faint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDiscard,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.surface,
                      border: Border.all(color: tokens.line),
                    ),
                    alignment: Alignment.center,
                    child: Icon(WIcons.trash, size: 16, color: tokens.dim),
                  ),
                ),
                const SizedBox(width: 12),

                // Elapsed timer
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$mm:${ss.toString().padLeft(2, '0')}',
                      style: WorkoutType.mono(
                        size: 18,
                        weight: FontWeight.w700,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.sessionElapsed,
                      style: WorkoutType.mono(
                        size: 9,
                        color: tokens.faint,
                        letterSpacing: 0.06 * 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3px progress bar
          Container(
            height: 3,
            color: tokens.surface3,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: tokens.accent),
            ),
          ),

          // Bottom border
          Container(height: 1, color: tokens.line),
        ],
      ),
    );
  }
}

class _EmptySessionPlaceholder extends StatelessWidget {
  const _EmptySessionPlaceholder({required this.tokens, required this.l});

  final WorkoutTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
            border: Border.all(color: tokens.line),
          ),
          alignment: Alignment.center,
          child: Icon(WIcons.dumbbell, size: 26, color: tokens.faint),
        ),
        const SizedBox(height: 16),
        Text(
          l.sessionEmptyTitle,
          style: WorkoutType.display(
              size: 18, weight: FontWeight.w700, color: tokens.text),
        ),
        const SizedBox(height: 6),
        Text(
          l.sessionEmptySubtitle,
          style: WorkoutType.mono(size: 12, color: tokens.faint),
        ),
      ],
    );
  }
}

class _DashedButton extends StatelessWidget {
  const _DashedButton({
    required this.height,
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  final double height;
  final IconData icon;
  final String label;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border.all(
            color: tokens.lineStrong,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(AppRadius.radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: tokens.dim),
            const SizedBox(width: 7),
            Text(
              label,
              style: WorkoutType.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: tokens.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({
    required this.canFinish,
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  final bool canFinish;
  final String label;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canFinish ? onTap : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: canFinish ? tokens.accent : tokens.surface3,
          borderRadius: BorderRadius.circular(AppRadius.radius),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: WorkoutType.display(
            size: 16,
            weight: FontWeight.w700,
            color: canFinish ? tokens.accentInk : tokens.faint,
          ),
        ),
      ),
    );
  }
}
