import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('locale override: null=system default, set persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.load();
    expect(s.localeOverride, isNull);
    expect(s.locale, isNull);

    await s.setLocaleOverride('it');
    expect(s.locale, const Locale('it'));
    final s2 = SettingsService();
    await s2.load();
    expect(s2.localeOverride, 'it');
    expect(s2.locale, const Locale('it'));

    await s.setLocaleOverride(null);
    expect(s.locale, isNull);
  });
}
