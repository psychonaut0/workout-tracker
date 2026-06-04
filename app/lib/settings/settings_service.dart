import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tokens.dart';

const String _kMode = 'mode';
const String _kAccent = 'accent';
const String _kProfileName = 'profile_name';
const String _kServerUrl = 'server_url';

/// Client-local settings: appearance (mode + accent), profile name, and
/// backend server URL. Persisted via shared_preferences; loaded once at
/// startup before the widget tree is built.
class SettingsService extends ChangeNotifier {
  String _mode = 'dark';
  Color _accent = accents[0];
  String _profileName = 'Athlete';
  String _serverUrl = 'http://localhost:8080';
  bool _syncEnabled = false;
  bool _ambientEnabled = true;

  String get mode => _mode;
  Color get accent => _accent;
  String get profileName => _profileName;
  String get serverUrl => _serverUrl;
  bool get syncEnabled => _syncEnabled;
  bool get ambientEnabled => _ambientEnabled;

  /// Derived brightness from the stored mode string.
  Brightness get brightness =>
      _mode == 'light' ? Brightness.light : Brightness.dark;

  /// The current accent colour (alias for direct use in buildTheme).
  Color get accentColor => _accent;

  /// Load all preferences from shared_preferences. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _mode = prefs.getString(_kMode) ?? 'dark';
    _profileName = prefs.getString(_kProfileName) ?? 'Athlete';
    _serverUrl = prefs.getString(_kServerUrl) ?? 'http://localhost:8080';
    _syncEnabled = prefs.getBool('settings.sync_enabled') ?? false;
    _ambientEnabled = prefs.getBool('settings.ambient_enabled') ?? true;

    // Accent: stored as ARGB int via toARGB32(). Reconstruct via Color.fromARGB
    // (not Color(int) — deprecated in Flutter 3.44). Fall back to accents[0]
    // if the stored value is not one of the 4 canonical accents.
    final storedAccent = prefs.getInt(_kAccent);
    if (storedAccent != null) {
      final a = (storedAccent >> 24) & 0xFF;
      final r = (storedAccent >> 16) & 0xFF;
      final g = (storedAccent >> 8) & 0xFF;
      final b = storedAccent & 0xFF;
      final candidate = Color.fromARGB(a, r, g, b);
      _accent = accents.contains(candidate) ? candidate : accents[0];
    } else {
      _accent = accents[0];
    }

    notifyListeners();
  }

  /// Set the theme mode ('dark' or 'light') and persist.
  Future<void> setMode(String mode) async {
    if (mode == _mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode);
    notifyListeners();
  }

  /// Set the accent colour and persist.
  Future<void> setAccent(Color accent) async {
    if (accent == _accent) return;
    _accent = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAccent, accent.toARGB32());
    notifyListeners();
  }

  /// Set the profile display name and persist.
  Future<void> setProfileName(String name) async {
    if (name == _profileName) return;
    _profileName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileName, name);
    notifyListeners();
  }

  /// Set the backend server URL and persist.
  Future<void> setServerUrl(String url) async {
    if (url == _serverUrl) return;
    _serverUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, url);
    notifyListeners();
  }

  /// Enable or disable background sync and persist.
  Future<void> setSyncEnabled(bool value) async {
    _syncEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings.sync_enabled', value);
    notifyListeners();
  }

  /// Enable or disable the ambient visual layer and persist.
  Future<void> setAmbientEnabled(bool value) async {
    _ambientEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings.ambient_enabled', value);
    notifyListeners();
  }
}
