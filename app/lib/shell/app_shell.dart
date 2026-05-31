import 'package:flutter/material.dart';

import '../data/day_template_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../sync/db.dart';
import '../ui/history_screen.dart';
import '../ui/plan_screen.dart';
import '../ui/progress_screen.dart';
import '../ui/today_screen.dart';
import 'placeholder_screen.dart';
import 'session_launcher.dart' as launcher;
import 'w_tab_bar.dart';

/// The top-level 5-tab shell of the app.
///
/// Layout:
///   - [Scaffold] with `extendBody: true` so the tab bar is overlaid by the
///     body content via a [Stack].
///   - [IndexedStack] (index 0..3) for Today / Progress / History / Plan.
///   - [WTabBar] pinned at the bottom centre of the stack.
///
/// Tab index mapping is identity (no FAB offset):
///   Today=0, Progress=1, History=2, Plan=3.
///
/// The FAB calls [launcher.startSession] with the next-in-rotation template
/// (null → custom session) and resets to the Today tab on return.
///
/// [onLogout] is stored for future use (e.g. Profile overlay button). No logout
/// button is wired in this increment.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onLogout});

  /// Called when the user logs out. Retained for future Profile overlay wiring.
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  String? _progressTarget;

  late final DayTemplateRepository _dayRepo;
  late final SessionRepository _sessionRepo;

  @override
  void initState() {
    super.initState();
    _dayRepo = DayTemplateRepository(db);
    _sessionRepo = SessionRepository(db);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// FAB: resolve next-in-rotation and start a session; return to Today.
  Future<void> _fabStart() async {
    final t = await launcher.nextInRotation(_dayRepo, _sessionRepo);
    if (!mounted) return;
    await launcher.startSession(context, template: t);
    if (mounted) setState(() => _index = 0);
  }

  /// Today hero Start button: start the given (or custom) session; return to Today.
  Future<void> _start(DayTemplate? day) async {
    await launcher.startSession(context, template: day);
    if (mounted) setState(() => _index = 0);
  }

  /// Switches to the Progress tab with the given exercise or bodyweight target.
  void _openExercise(String exId) {
    setState(() {
      _progressTarget = exId;
      _index = 1;
    });
  }

  /// Opens a root-navigator overlay for the Profile placeholder.
  Future<void> _openProfile() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PlaceholderTab(title: 'Profile'),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              TodayScreen(
                onStart: _start,
                onOpenExercise: _openExercise,
                onOpenProfile: _openProfile,
              ),
              ProgressScreen(
                key: ValueKey(_progressTarget),
                initialTarget: _progressTarget,
              ),
              const HistoryScreen(),
              const PlanScreen(),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: WTabBar(
              currentIndex: _index,
              onTab: (i) => setState(() => _index = i),
              onStart: _fabStart,
            ),
          ),
        ],
      ),
    );
  }
}
