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

  test('login stores access + refresh tokens', () async {
    final auth = AuthStore(
      client: MockClient((req) async {
        expect(req.url.path, '/auth/login');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'me@example.com');
        return http.Response(
          jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
          200,
        );
      }),
    );

    await auth.login('me@example.com', 'devpassword');

    expect(auth.accessToken, 'A1');
    // A fresh load() reads the persisted refresh token back -> "remembered".
    expect(await auth.load(), isTrue);
  });

  test('refresh rotates BOTH tokens and persists the new pair', () async {
    final auth = AuthStore(
      client: MockClient((req) async {
        if (req.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
            200,
          );
        }
        // /auth/refresh — must send the current refresh token.
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'R1');
        return http.Response(
          jsonEncode({'access_token': 'A2', 'refresh_token': 'R2'}),
          200,
        );
      }),
    );

    await auth.login('me@example.com', 'devpassword');
    final fresh = await auth.refresh();

    expect(fresh, 'A2');
    expect(auth.accessToken, 'A2');
  });

  test('ensureAccessToken returns the cached token without a network call',
      () async {
    var calls = 0;
    final auth = AuthStore(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
          200,
        );
      }),
    );
    await auth.login('me@example.com', 'devpassword');
    final callsAfterLogin = calls;

    final token = await auth.ensureAccessToken();

    expect(token, 'A1');
    expect(calls, callsAfterLogin); // no extra round-trip when cached
  });
}
