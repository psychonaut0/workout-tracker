import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ambientEnabled defaults true, persists false', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.load();
    expect(s.ambientEnabled, isTrue);

    await s.setAmbientEnabled(false);
    expect(s.ambientEnabled, isFalse);

    final s2 = SettingsService();
    await s2.load();
    expect(s2.ambientEnabled, isFalse);
  });
}
