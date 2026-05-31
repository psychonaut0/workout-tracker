import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_store.dart';
import 'settings/settings_service.dart';
import 'shell/app_shell.dart';
import 'sync/db.dart';
import 'theme/app_theme.dart';
import 'ui/login_screen.dart';
import 'units/unit_service.dart';

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
  final loggedIn = await auth.load();
  if (loggedIn) {
    await connectSync(auth); // resume sync on a remembered session
  }
  runApp(App(
    auth: auth,
    startLoggedIn: loggedIn,
    settingsService: settingsService,
    unitService: unitService,
  ));
}

class App extends StatefulWidget {
  const App({
    super.key,
    required this.auth,
    required this.startLoggedIn,
    required this.settingsService,
    required this.unitService,
  });

  final AuthStore auth;
  final bool startLoggedIn;
  final SettingsService settingsService;
  final UnitService unitService;

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
        ChangeNotifierProvider.value(value: widget.unitService),
        ChangeNotifierProvider.value(value: widget.settingsService),
      ],
      // Builder is required so that ctx.watch<SettingsService>() is a
      // descendant of the MultiProvider (calling watch in _AppState.build()
      // would throw ProviderNotFoundException — _AppState is the provider's
      // parent, not a descendant).
      child: Builder(
        builder: (ctx) {
          final s = ctx.watch<SettingsService>();
          return MaterialApp(
            title: 'workout-tracker',
            theme: buildTheme(s.brightness, s.accentColor),
            home: _loggedIn
                ? AppShell(onLogout: _onLogout)
                : LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
          );
        },
      ),
    );
  }
}
