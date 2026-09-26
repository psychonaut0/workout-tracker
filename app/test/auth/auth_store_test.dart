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

  test('concurrent refreshes share one request, so a refresh token is never sent twice',
      () async {
    var refreshCalls = 0;
    final auth = AuthStore(
      client: MockClient((req) async {
        if (req.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
            200,
          );
        }
        refreshCalls++;
        // The server revokes the whole family when a used token comes back.
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['refresh_token'] != 'R1') return http.Response('reused', 401);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode({'access_token': 'A2', 'refresh_token': 'R2'}),
          200,
        );
      }),
    );
    await auth.login('me@example.com', 'devpassword');

    // The upload loop and the sync stream both hit a 401 at once.
    final results = await Future.wait([auth.refresh(), auth.refresh()]);

    expect(refreshCalls, 1);
    expect(results, ['A2', 'A2']);
    // A later refresh sends the rotated token, not the consumed one.
    await auth.refresh();
    expect(refreshCalls, 2);
  });

  test('a rejected refresh marks the session expired and stops re-sending the dead token',
      () async {
    var refreshCalls = 0;
    final auth = AuthStore(
      client: MockClient((req) async {
        if (req.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
            200,
          );
        }
        refreshCalls++;
        return http.Response('revoked', 401);
      }),
    );
    await auth.login('me@example.com', 'devpassword');
    expect(auth.sessionExpired.value, isFalse);

    expect(await auth.refresh(), isNull);
    expect(auth.sessionExpired.value, isTrue);
    expect(await auth.refresh(), isNull);
    expect(await auth.ensureAccessToken(), isNull);
    expect(refreshCalls, 1);

    // Signing in again clears it.
    await auth.login('me@example.com', 'devpassword');
    expect(auth.sessionExpired.value, isFalse);
    expect(await auth.ensureAccessToken(), 'A1');
  });

  test('a server error on refresh is transient, not an expired session', () async {
    final auth = AuthStore(
      client: MockClient((req) async {
        if (req.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
            200,
          );
        }
        return http.Response('down', 502);
      }),
    );
    await auth.login('me@example.com', 'devpassword');
    expect(await auth.refresh(), isNull);
    expect(auth.sessionExpired.value, isFalse);
  });
}
