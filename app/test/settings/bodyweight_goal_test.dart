import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/settings/bodyweight_goal.dart';
import 'package:workout_tracker/settings/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('bodyweightDeltaTone', () {
    test('a loss is good only on cut', () {
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.cut), DeltaTone.good);
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.bulk), DeltaTone.neutral);
      expect(bodyweightDeltaTone(-0.5, BodyweightGoal.maintain), DeltaTone.neutral);
    });
    test('a gain is good only on bulk', () {
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.bulk), DeltaTone.good);
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.cut), DeltaTone.neutral);
      expect(bodyweightDeltaTone(0.4, BodyweightGoal.maintain), DeltaTone.neutral);
    });
    test('no change is always neutral', () {
      for (final g in BodyweightGoal.values) {
        expect(bodyweightDeltaTone(0, g), DeltaTone.neutral);
      }
    });
  });

  group('SettingsService goal', () {
    test('defaults to maintain', () async {
      final s = SettingsService();
      await s.load();
      expect(s.bodyweightGoal, BodyweightGoal.maintain);
    });
    test('persists and notifies', () async {
      final s = SettingsService();
      await s.load();
      var notified = 0;
      s.addListener(() => notified++);
      await s.setBodyweightGoal(BodyweightGoal.cut);
      expect(notified, 1);
      final s2 = SettingsService();
      await s2.load();
      expect(s2.bodyweightGoal, BodyweightGoal.cut);
    });
    test('an unknown stored value reads as maintain', () async {
      SharedPreferences.setMockInitialValues({'settings.bodyweight_goal': 'shred'});
      final s = SettingsService();
      await s.load();
      expect(s.bodyweightGoal, BodyweightGoal.maintain);
    });
  });
}
