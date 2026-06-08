import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rest defaults: 180/90 default, persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.load();
    expect(s.restCompoundSeconds, 180);
    expect(s.restIsolationSeconds, 90);

    await s.setRestCompoundSeconds(150);
    await s.setRestIsolationSeconds(75);
    final s2 = SettingsService();
    await s2.load();
    expect(s2.restCompoundSeconds, 150);
    expect(s2.restIsolationSeconds, 75);
  });
}
