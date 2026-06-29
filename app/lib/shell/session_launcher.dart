import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/active_session_draft.dart';
import '../data/day_template_repository.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../l10n/app_localizations.dart';
import '../session/active_session_controller.dart';
import '../session/active_session_screen.dart';
import '../session/session_manager.dart';
import '../sync/db.dart';
import '../theme/motion.dart';

/// Starts an active session, optionally pre-loaded from a [DayTemplate].
///
/// Builds an [ActiveSessionController], seeds it from [template] (or empty for
/// a custom session), guards [BuildContext.mounted], and pushes
/// [ActiveSessionScreen] on the **root** navigator wrapped in a
/// [ChangeNotifierProvider].
Future<void> startSession(
  BuildContext context, {
  DayTemplate? template,
}) async {
  final manager = context.read<SessionManager>();
  // Read before any await so the context is still valid (used for the
  // localized custom-session name below).
  final customName = AppLocalizations.of(context).todayCustomSession;

  // A workout is already running → resume it instead of starting a new one.
  if (manager.hasActive) {
    await openActiveSession(context, manager);
    return;
  }

  final controller = ActiveSessionController(draftStore: DraftStore());

  if (template != null) {
    await controller.buildFromTemplate(
      template,
      exerciseRepo: ExerciseRepository(db),
      sessionRepo: SessionRepository(db),
    );
  } else {
    controller.seedEmpty(name: customName, focus: '');
  }

  manager.register(controller);

  if (!context.mounted) return;
  await openActiveSession(context, manager);
}

/// Pushes the session route for the manager's active controller (no-op if
/// none or already open). Shared by start, mini-bar tap and notification tap.
Future<void> openActiveSession(
    BuildContext context, SessionManager manager) async {
  final controller = manager.active;
  if (controller == null || manager.screenOpen) return;

  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) =>
          ChangeNotifierProvider<ActiveSessionController>.value(
        value: controller,
        child: const ActiveSessionScreen(),
      ),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Motion.curve);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Returns the next [DayTemplate] in position-based rotation, or null if there
/// are no day templates.
///
/// Delegates to [DayTemplateRepository.nextInRotation].
Future<DayTemplate?> nextInRotation(
  DayTemplateRepository dayRepo,
  SessionRepository sessionRepo,
) {
  return dayRepo.nextInRotation(sessionRepo);
}
