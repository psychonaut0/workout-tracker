import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/identity/identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates and persists a fresh id when nothing exists, onboarding incomplete', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => null);
    expect(svc.currentUserId, isNotEmpty);
    expect(svc.onboardingComplete, isFalse);

    final again = IdentityService();
    await again.init(probeExistingUserId: () async => 'IGNORED-because-already-persisted');
    expect(again.currentUserId, svc.currentUserId);
  });

  test('adopts an existing identity from the probe and marks onboarding complete', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => 'server-user-123');
    expect(svc.currentUserId, 'server-user-123');
    expect(svc.onboardingComplete, isTrue);
  });

  test('completeOnboarding persists the flag', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => null);
    expect(svc.onboardingComplete, isFalse);
    await svc.completeOnboarding();
    expect(svc.onboardingComplete, isTrue);
    final reload = IdentityService();
    await reload.init(probeExistingUserId: () async => null);
    expect(reload.onboardingComplete, isTrue);
  });
}
