import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/settings/settings_service.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/ambient_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({
    required SettingsService settings,
    AmbientController? ambient,
    SessionManager? manager,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: manager ?? SessionManager()),
        ChangeNotifierProvider.value(value: ambient ?? AmbientController()),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, accents[0]),
        builder: (ctx, child) => AmbientLayer(child: child!),
        home: const Scaffold(body: Center(child: Text('content'))),
      ),
    );
  }

  Future<SettingsService> loadedSettings({bool ambientOn = true}) async {
    SharedPreferences.setMockInitialValues(
        {'settings.ambient_enabled': ambientOn});
    final s = SettingsService();
    await s.load();
    return s;
  }

  testWidgets('renders child and ambient ignores pointer events',
      (tester) async {
    final settings = await loadedSettings();
    await tester.pumpWidget(host(settings: settings));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    // The overlay is an IgnorePointer keyed with AmbientLayer.overlayKey
    // (MaterialApp/Navigator add their own IgnorePointers — match the key).
    final overlay = find.byKey(AmbientLayer.overlayKey);
    expect(overlay, findsOneWidget);
    expect(tester.widget<IgnorePointer>(overlay).ignoring, isTrue);
    // Cleanly stop the ambient ticker for test teardown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled setting → pure passthrough (no overlay painting)',
      (tester) async {
    final settings = await loadedSettings(ambientOn: false);
    await tester.pumpWidget(host(settings: settings));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    // Passthrough adds no overlay. (MaterialApp inserts framework
    // RepaintBoundaries/IgnorePointers inside the builder's child regardless,
    // so the overlay is identified by AmbientLayer.overlayKey — absent here.)
    expect(find.byKey(AmbientLayer.overlayKey), findsNothing);
    await tester.pumpAndSettle(); // proves no perpetual ticker
  });

  testWidgets('reduced motion → static (settles, no perpetual frames)',
      (tester) async {
    final settings = await loadedSettings();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn; // sets disableAnimations
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host(settings: settings));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    await tester.pumpAndSettle(); // would time out if a ticker ran forever
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bloom shows a transient overlay then settles away',
      (tester) async {
    final settings = await loadedSettings();
    final ambient = AmbientController();
    await tester.pumpWidget(host(settings: settings, ambient: ambient));
    await tester.pump();

    ambient.bloom();
    await tester.pump(const Duration(milliseconds: 100));
    final layerState =
        tester.state<AmbientLayerState>(find.byType(AmbientLayer));
    expect(layerState.bloomActiveForTest, isTrue);

    await tester.pump(const Duration(milliseconds: 900));
    expect(layerState.bloomActiveForTest, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
