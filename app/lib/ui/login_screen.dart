import 'package:flutter/material.dart';

import '../auth/auth_store.dart';

/// Minimal throwaway login. Dev creds: me@example.com / devpassword.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onLoggedIn});

  final AuthStore auth;
  final Future<void> Function() onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'me@example.com');
  final _password = TextEditingController(text: 'devpassword');
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(_email.text.trim(), _password.text);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '...' : 'Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
