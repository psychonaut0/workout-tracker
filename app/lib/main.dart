import 'package:flutter/material.dart';

import 'auth/auth_store.dart';
import 'sync/db.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

// NOTE: UI here is intentionally minimal/throwaway. UX is deferred to a later
// design phase; this exists only to prove the sync round-trip.

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
    return MaterialApp(
      title: 'workout-tracker (foundations)',
      home: _loggedIn
          ? HomeScreen(onLogout: _onLogout)
          : LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
    );
  }
}
