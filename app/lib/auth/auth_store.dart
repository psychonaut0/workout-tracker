import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Base URL of the Go API server. On Linux desktop (the foundations validation
/// target) the host can reach the container directly on localhost.
const String apiBaseUrl = 'http://localhost:8080';

/// Holds and persists the auth tokens, and knows how to login / refresh /
/// logout against the Go API. The PowerSync connector reads from this:
/// - the ACCESS token is used for /sync/upload and /auth/powersync-token
/// - the PowerSync token (minted via /auth/powersync-token) is what
///   fetchCredentials() returns to the sync service.
class AuthStore {
  AuthStore({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _http = client ?? http.Client();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  final FlutterSecureStorage _storage;
  final http.Client _http;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;

  /// Load any persisted tokens at startup. Returns true if we have a refresh
  /// token (i.e. the user was previously logged in).
  Future<bool> load() async {
    _accessToken = await _storage.read(key: _kAccess);
    _refreshToken = await _storage.read(key: _kRefresh);
    return _refreshToken != null;
  }

  /// POST /auth/login. Throws on bad credentials.
  Future<void> login(String email, String password) async {
    final res = await _http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw Exception('login failed (${res.statusCode}): ${res.body}');
    }
    await _persistTokens(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /auth/refresh — rotates both tokens. Returns the fresh access token,
  /// or null if the refresh token is invalid/expired (caller should log out).
  Future<String?> refresh() async {
    final rt = _refreshToken;
    if (rt == null) return null;
    final res = await _http.post(
      Uri.parse('$apiBaseUrl/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refresh_token': rt}),
    );
    if (res.statusCode != 200) return null;
    await _persistTokens(jsonDecode(res.body) as Map<String, dynamic>);
    return _accessToken;
  }

  /// A valid access token, refreshing once if we have none. Returns null if we
  /// cannot obtain one (caller treats this as logged-out).
  Future<String?> ensureAccessToken() async {
    if (_accessToken != null) return _accessToken;
    return refresh();
  }

  /// POST /auth/logout to revoke the refresh-token family, then clear storage.
  Future<void> logout() async {
    final rt = _refreshToken;
    if (rt != null) {
      try {
        await _http.post(
          Uri.parse('$apiBaseUrl/auth/logout'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'refresh_token': rt}),
        );
      } catch (_) {
        // best-effort; we clear locally regardless
      }
    }
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<void> _persistTokens(Map<String, dynamic> body) async {
    _accessToken = body['access_token'] as String;
    _refreshToken = body['refresh_token'] as String;
    await _storage.write(key: _kAccess, value: _accessToken);
    await _storage.write(key: _kRefresh, value: _refreshToken);
  }
}
