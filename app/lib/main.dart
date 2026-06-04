import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_store.dart';
import 'data/catalog_seed.dart';
import 'data/muscle_target_repository.dart';
import 'data/session_repository.dart';
import 'data/session_writer.dart';
import 'data/top_set_backfill.dart';
import 'identity/identity_service.dart';
import 'session/session_manager.dart';
import 'session/workout_notification.dart';
import 'settings/settings_service.dart';
import 'shell/app_shell.dart';
import 'shell/session_launcher.dart';
import 'sync/db.dart';
import 'theme/app_theme.dart';
import 'ui/onboarding_screen.dart';
import 'units/unit_service.dart';
import 'widgets/ambient_layer.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

enum HomeRoute { onboarding, shell }

HomeRoute homeRouteFor({required bool onboardingComplete}) =>
    onboardingComplete ? HomeRoute.shell : HomeRoute.onboarding;

bool shouldConnectSync({required bool syncEnabled, required bool loggedIn}) =>
    syncEnabled && loggedIn;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load client-local settings first so apiBaseUrl is set before
  // openDatabase/connectSync (PowerSync and the connector read it at startup).
  final settingsService = SettingsService();
  await settingsService.load();
  final unitService = UnitService();
  await unitService.load();

  apiBaseUrl = settingsService.serverUrl;

  final auth = AuthStore();
  await openDatabase();

  final identity = IdentityService();
  await identity.init(
    probeExistingUserId: () => SessionRepository(db).anyUserId(),
  );

  await backfillTopSets(db);

  final sessionManager = SessionManager();
  final workoutNotification = WorkoutNotification();
  await workoutNotification.init(onTap: () {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) openActiveSession(ctx, sessionManager);
  });
  sessionManager.notifier = workoutNotification;
  await sessionManager.resumeFromDraft();

  final loggedIn = await auth.load();
  if (shouldConnectSync(
      syncEnabled: settingsService.syncEnabled, loggedIn: loggedIn)) {
    await connectSync(auth); // resume sync only for an opted-in remembered session
  }

  runApp(App(
    auth: auth,
    settingsService: settingsService,
    unitService: unitService,
    identity: identity,
    sessionManager: sessionManager,
  ));
}

class App extends StatefulWidget {
  const App({
    super.key,
    required this.auth,
    required this.settingsService,
    required this.unitService,
    required this.identity,
    required this.sessionManager,
  });

  final AuthStore auth;
  final SettingsService settingsService;
  final UnitService unitService;
  final IdentityService identity;
  final SessionManager sessionManager;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Future<void> _onLogout() async {
    await disconnectAndClear();
    await widget.auth.logout();
    await widget.settingsService.setSyncEnabled(false);
    setState(() {}); // returns to the local app shell, not a login wall
  }

  Future<void> _onOnboardingChosen(
      BuildContext ctx, OnboardingChoice choice) async {
    if (choice == OnboardingChoice.starter) {
      await db.writeTransaction(
        (tx) => seedStarterCatalog(
            PowerSyncTxExecutor(tx), widget.identity.currentUserId),
      );
      await MuscleTargetRepository(db)
          .seedDefaultsIfEmpty(widget.identity.currentUserId);
    }
    await widget.identity.completeOnboarding(); // notifies → re-route to shell
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.unitService),
        ChangeNotifierProvider.value(value: widget.settingsService),
        ChangeNotifierProvider.value(value: widget.identity),
        ChangeNotifierProvider.value(value: widget.sessionManager),
        ChangeNotifierProvider(create: (_) => AmbientController()),
      ],
      // Builder is required so that ctx.watch<SettingsService>() is a
      // descendant of the MultiProvider (calling watch in _AppState.build()
      // would throw ProviderNotFoundException — _AppState is the provider's
      // parent, not a descendant).
      child: Builder(
        builder: (ctx) {
          final s = ctx.watch<SettingsService>();
          final identity = ctx.watch<IdentityService>();
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'workout-tracker',
            theme: buildTheme(s.brightness, s.accentColor),
            builder: (ctx, child) => AmbientLayer(child: child!),
            home: homeRouteFor(
                        onboardingComplete: identity.onboardingComplete) ==
                    HomeRoute.onboarding
                ? OnboardingScreen(
                    onChosen: (choice) => _onOnboardingChosen(ctx, choice))
                : AppShell(onLogout: _onLogout, auth: widget.auth),
          );
        },
      ),
    );
  }
}
