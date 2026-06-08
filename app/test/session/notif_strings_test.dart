import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/session/workout_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('notifString resolves persisted locale, falls back to en', () async {
    SharedPreferences.setMockInitialValues({'settings.locale': 'it'});
    final p = await SharedPreferences.getInstance();
    expect(notifString(p, 'rest'), 'Recupero');
    expect(notifString(p, 'inProgress'), 'Allenamento in corso');

    SharedPreferences.setMockInitialValues({'settings.locale': 'zz'}); // unknown → en
    final p2 = await SharedPreferences.getInstance();
    await p2.reload();
    expect(notifString(p2, 'rest'), 'Rest');
    expect(notifString(p2, 'inProgress'), 'Workout in progress');
  });
}
