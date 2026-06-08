import 'package:flutter/material.dart';

import '../auth/auth_store.dart';
import '../l10n/app_localizations.dart';

/// Sign-in / registration against the configured sync server.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onLoggedIn});

  final AuthStore auth;
  final Future<void> Function() onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _registering = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (_registering) {
        await widget.auth.register(email, _password.text);
      } else {
        await widget.auth.login(email, _password.text);
      }
      await widget.onLoggedIn();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.loginTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _email,
              decoration: InputDecoration(labelText: l.loginEmailLabel),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _password,
              decoration: InputDecoration(labelText: l.loginPasswordLabel),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? l.loginBusy
                    : (_registering ? l.loginCreateAccount : l.loginLogIn),
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _registering = !_registering;
                        _error = null;
                      }),
              child: Text(
                _registering ? l.loginHaveAccount : l.loginCreateAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
