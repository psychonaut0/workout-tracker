import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:workout_tracker/auth/auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // In-memory secure storage so tests never touch a real OS keyring.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('register posts to /auth/register and stores tokens + email on 200',
      () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/register');
      expect(req.method, 'POST');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['email'], 'new@example.com');
      expect(body['password'], 'password123');
      return http.Response('{"access_token":"a","refresh_token":"r"}', 200);
    });
    final store = AuthStore(client: client);

    await store.register('new@example.com', 'password123');

    expect(store.accessToken, 'a');
    expect(store.email, 'new@example.com');
    // A fresh load() reads the persisted refresh token back -> "remembered".
    expect(await store.load(), isTrue);
  });

  test('register throws on non-200 (e.g. 409 email taken)', () async {
    final client = MockClient(
      (req) async => http.Response('{"error":"email already registered"}', 409),
    );
    final store = AuthStore(client: client);

    expect(
      () => store.register('a@b.com', 'password123'),
      throwsA(isA<Exception>()),
    );
  });
}
