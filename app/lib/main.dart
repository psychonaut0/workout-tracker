import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_store.dart';
import 'data/day_template_repository.dart';
import 'data/exercise_repository.dart';
import 'data/models.dart';
import 'data/session_repository.dart';
import 'session/active_session_controller.dart';
import 'session/active_session_screen.dart';
import 'sync/db.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/login_screen.dart';
import 'units/unit_service.dart';

// NOTE: The LauncherScreen below is a minimal validation entry for the
// active-session flow. The full Today/nav shell is a later plan.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthStore();
  await openDatabase();
  final loggedIn = await auth.load();
  if (loggedIn) {
    await connectSync(auth); // resume sync on a remembered session
  }
  runApp(App(auth: auth, startLoggedIn: loggedIn));
}

class App extends StatefulWidget {
  const App({super.key, required this.auth, required this.startLoggedIn});

  final AuthStore auth;
  final bool startLoggedIn;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late bool _loggedIn = widget.startLoggedIn;

  Future<void> _onLoggedIn() async {
    await connectSync(widget.auth);
    setState(() => _loggedIn = true);
  }

  Future<void> _onLogout() async {
    await disconnectAndClear();
    await widget.auth.logout();
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UnitService>(create: (_) => UnitService()),
      ],
      child: MaterialApp(
        title: 'workout-tracker',
        theme: buildTheme(Brightness.dark, accents[0]),
        home: _loggedIn
            ? LauncherScreen(onLogout: _onLogout)
            : LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
      ),
    );
  }
}

// ── LauncherScreen ────────────────────────────────────────────────────────────

/// Minimal training-day launcher for the active-session validation flow.
///
/// Lists day templates from [DayTemplateRepository.watchDays] with a "Start"
/// button per day, plus a "Start empty" fallback. Each tap builds an
/// [ActiveSessionController] from the chosen template and pushes
/// [ActiveSessionScreen], which reads the controller via Provider.
///
/// NOTE: The full Today dashboard + 5-tab nav shell is a later plan; this
/// launcher is the validation entry point for the active-session logging flow.
class LauncherScreen extends StatelessWidget {
  const LauncherScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  Future<void> _startSession(
    BuildContext context,
    DayTemplate? template,
  ) async {
    final controller = ActiveSessionController();

    if (template != null) {
      await controller.buildFromTemplate(
        template,
        exerciseRepo: ExerciseRepository(db),
        dayTemplateRepo: DayTemplateRepository(db),
        sessionRepo: SessionRepository(db),
      );
    } else {
      // Empty / custom session — no template, no blocks.
      controller.seedEmpty(name: 'Custom', focus: '');
    }

    if (!context.mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<ActiveSessionController>.value(
          value: controller,
          child: const ActiveSessionScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a workout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: onLogout,
          ),
        ],
      ),
      body: StreamBuilder<List<DayTemplate>>(
        stream: DayTemplateRepository(db).watchDays(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final days = snapshot.data ?? [];

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // One row per training day
              for (final day in days)
                _DayTile(
                  day: day,
                  onStart: () => _startSession(context, day),
                ),

              const SizedBox(height: 8),

              // Always-visible "Start empty" option
              _DayTile(
                day: null,
                onStart: () => _startSession(context, null),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.onStart});

  final DayTemplate? day;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final name = day?.name ?? 'Custom';
    final focus = day?.focus;
    final slotCount = day?.slots.length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(name),
        subtitle: day != null
            ? Text([
                if (focus != null && focus.isNotEmpty) focus,
                '$slotCount exercise${slotCount == 1 ? '' : 's'}',
              ].join(' · '))
            : const Text('No template — add exercises freely'),
        trailing: FilledButton(
          onPressed: onStart,
          child: const Text('Start'),
        ),
      ),
    );
  }
}
