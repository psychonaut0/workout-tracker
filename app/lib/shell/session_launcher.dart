import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/day_template_repository.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../session/active_session_controller.dart';
import '../session/active_session_screen.dart';
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
  final controller = ActiveSessionController();

  if (template != null) {
    await controller.buildFromTemplate(
      template,
      exerciseRepo: ExerciseRepository(db),
      dayTemplateRepo: DayTemplateRepository(db),
      sessionRepo: SessionRepository(db),
    );
  } else {
    controller.seedEmpty(name: 'Custom', focus: '');
  }

  if (!context.mounted) return;

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
