import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_store.dart';
import 'shell/app_shell.dart';
import 'sync/db.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/login_screen.dart';
import 'units/unit_service.dart';

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
            ? AppShell(onLogout: _onLogout)
            : LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
      ),
    );
  }
}
