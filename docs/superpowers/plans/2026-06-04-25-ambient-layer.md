# Ambient Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An always-on ambient visual layer — two drifting accent auras + static film grain over every route, intensifying during a workout, with a one-shot PR bloom wash — per `docs/superpowers/specs/2026-06-04-ambient-layer-design.md`. Ships as v0.8.0.

**Architecture:** One module `app/lib/widgets/ambient_layer.dart` holds `AmbientController` (bloom event bus), the pure `auraPosition` path math, and `AmbientLayer` (Stack: child + IgnorePointer(RepaintBoundary(painting))), wired via `MaterialApp.builder`. A single `Ticker` accumulates a virtual clock (`t += dt × speed`) so workout speed-up glides. Grain is a runtime-generated 128×128 noise tile. Kill switch in SettingsService + Profile Appearance.

**Tech Stack:** Flutter 3.44 (fvm), provider, `dart:ui` image generation, existing tokens/Motion system. NO new dependencies, NO blur filters (gradients only).

**Conventions:**
- Branch: create `ambient-layer` off `main` first.
- Makefile only, from repo root: `make -C app analyze`, `make -C app test`, `make -C app build`. NEVER run `flutter` directly.
- Baseline: 185 tests green, analyze clean.
- Commit style: Conventional Commits, subject line only, no body.
- Test import prefix `package:workout_tracker/...`.

**Verified facts:**
- `app/lib/main.dart` (:119-148): MultiProvider (unitService/settingsService/identity/sessionManager `.value` providers) > comment > `Builder` > `MaterialApp(navigatorKey: appNavigatorKey, title, theme: buildTheme(s.brightness, s.accentColor), home: ...)`. MaterialApp has NO `builder:` param yet — free for the ambient.
- `SessionManager` (`app/lib/session/session_manager.dart`): `bool get hasActive`, ChangeNotifier, provided app-wide ABOVE MaterialApp (so any route context can read it).
- `SettingsService` (`app/lib/settings/settings_service.dart`): persistence pattern = private field + getter + `Future<void> setX(v) async { _x = v; prefs = await SharedPreferences.getInstance(); await prefs.setBool(key, v); notifyListeners(); }` (see `setSyncEnabled` :98-103). Keys are `'settings.xxx'` strings (some via `_k` consts — match the file's local style). Defaults load in its `load()` method — READ it and mirror.
- Profile Appearance group: `app/lib/ui/profile_screen.dart` :562-585 — `_Group(label: 'Appearance', children: [_Row(Theme/ChipSelect), _Row(Accent/swatches)])`. `_Row` supports `{icon, title, sub, right, onTap}`.
- Existing `Toggle` widget: `app/lib/widgets/plan_form.dart:166` — `Toggle({required bool value, required ValueChanged<bool> onChanged})`. Use it for the ambient switch.
- PR trigger: `app/lib/session/set_row.dart` :143-152 — check-button `onTap`: `if (!done) { if (isLivePr) { HapticFeedback.heavyImpact(); } else ... }`. `set_row.dart` does NOT import provider yet.
- `WIcons` (`app/lib/theme/icons.dart`): has `bolt`, `flame`, `chart`... pick `WIcons.bolt` for the ambient row icon.
- `Motion.of(context, d)` → `Duration.zero` under `MediaQuery.disableAnimations` (`app/lib/theme/motion.dart`).
- `context.tokens` extension from `app/lib/theme/app_theme.dart`; `tokens.accent`, `tokens.bg`.
- Theme test harness: `buildTheme(Brightness.dark, accents[0])` (accents exported from `app/lib/theme/tokens.dart`).

---

### Task 1: Pure pieces — `auraPosition` + `AmbientController` + settings flag (TDD)

**Files:**
- Create: `app/lib/widgets/ambient_layer.dart` (math + controller only in this task; the widget comes in Task 2)
- Modify: `app/lib/settings/settings_service.dart`
- Test: `app/test/widgets/ambient_math_test.dart`, `app/test/settings/ambient_setting_test.dart`

- [ ] **Step 1: Write the failing tests**

`app/test/widgets/ambient_math_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/ambient_layer.dart';

void main() {
  group('auraPosition', () {
    test('stays within 0..1 over a long sweep', () {
      for (double t = 0; t < 200; t += 0.37) {
        final p = auraPosition(t, periodX: 26, periodY: 34, phase: 0);
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('is periodic in x with periodX', () {
      final a = auraPosition(3.0, periodX: 26, periodY: 34, phase: 0);
      final b = auraPosition(3.0 + 26, periodX: 26, periodY: 34, phase: 0);
      expect(a.x, closeTo(b.x, 1e-9));
    });

    test('different parameter sets give distinct paths', () {
      final a = auraPosition(5.0, periodX: 26, periodY: 34, phase: 0);
      final b = auraPosition(5.0, periodX: 34, periodY: 22, phase: 3.1);
      expect((a.x - b.x).abs() + (a.y - b.y).abs(), greaterThan(0.05));
    });
  });

  group('AmbientController', () {
    test('bloom increments and notifies', () {
      final c = AmbientController();
      var notifies = 0;
      c.addListener(() => notifies++);
      expect(c.bloomCount, 0);
      c.bloom();
      c.bloom();
      expect(c.bloomCount, 2);
      expect(notifies, 2);
    });
  });
}
```

`app/test/settings/ambient_setting_test.dart`:
```dart
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

    // New instance reads the persisted value.
    final s2 = SettingsService();
    await s2.load();
    expect(s2.ambientEnabled, isFalse);
  });
}
```
(CHECK how existing settings tests in `app/test/settings/` construct/load SettingsService — if `load()` has a different name or the mock pattern differs, match the existing test file's pattern; keep the assertions.)

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (no ambient_layer.dart, no `ambientEnabled`).

- [ ] **Step 3: Implement the pure pieces**

`app/lib/widgets/ambient_layer.dart` (first slice):
```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One-shot ambient events (PR bloom). The layer listens; anyone can fire.
class AmbientController extends ChangeNotifier {
  int _bloomCount = 0;
  int get bloomCount => _bloomCount;

  /// Trigger a full-screen accent bloom (a set just beat the previous best).
  void bloom() {
    _bloomCount++;
    notifyListeners();
  }
}

/// Slow Lissajous drift path for an aura. [t] is the virtual clock in
/// seconds; returns fractional screen offsets in 0..1.
({double x, double y}) auraPosition(
  double t, {
  required double periodX,
  required double periodY,
  required double phase,
}) {
  final x = 0.5 + 0.5 * math.sin(2 * math.pi * t / periodX + phase);
  final y = 0.5 + 0.5 * math.cos(2 * math.pi * t / periodY + phase * 0.7);
  return (x: x, y: y);
}
```

`settings_service.dart` — add alongside the other fields/getters (mirror the file's exact style and key naming; load the default in `load()` like the others):
```dart
  bool _ambientEnabled = true;
  bool get ambientEnabled => _ambientEnabled;

  /// Enable or disable the ambient visual layer and persist.
  Future<void> setAmbientEnabled(bool value) async {
    _ambientEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings.ambient_enabled', value);
    notifyListeners();
  }
```
and in `load()`: `_ambientEnabled = prefs.getBool('settings.ambient_enabled') ?? true;`

- [ ] **Step 4: Run `make -C app analyze` (clean) + `make -C app test` — expect 190 (185 + 5).**

- [ ] **Step 5: Commit**
```bash
git add app/lib/widgets/ambient_layer.dart app/lib/settings/settings_service.dart app/test/widgets/ambient_math_test.dart app/test/settings/ambient_setting_test.dart
git commit -m "feat(app): ambient math, bloom controller, ambient_enabled setting"
```

---

### Task 2: `AmbientLayer` widget (TDD)

**Files:**
- Modify: `app/lib/widgets/ambient_layer.dart` (add the widget)
- Test: `app/test/widgets/ambient_layer_test.dart`

- [ ] **Step 1: Write the failing widget tests**

`app/test/widgets/ambient_layer_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/settings/settings_service.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/ambient_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> host({
    required SettingsService settings,
    AmbientController? ambient,
    SessionManager? manager,
  }) async {
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
    await tester.pumpWidget(await host(settings: settings));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(AmbientLayer),
          matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    // Content still tappable through the overlay: hit test reaches the Text.
    final hit = tester.hitTestOnBinding(
        tester.getCenter(find.text('content')));
    expect(hit.path, isNotEmpty);
    // Cleanly stop the ambient ticker for the test teardown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled setting → pure passthrough (no ticker, no overlay)',
      (tester) async {
    final settings = await loadedSettings(ambientOn: false);
    await tester.pumpWidget(await host(settings: settings));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(AmbientLayer),
          matching: find.byType(CustomPaint)),
      findsNothing,
    );
    // pumpAndSettle proves no perpetual ticker is scheduling frames.
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion → static (settles, no perpetual frames)',
      (tester) async {
    final settings = await loadedSettings();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: await host(settings: settings),
    ));
    await tester.pump();
    expect(find.text('content'), findsOneWidget);
    await tester.pumpAndSettle(); // would hang/throw if a ticker ran forever
  });

  testWidgets('bloom shows a transient overlay then settles away',
      (tester) async {
    final settings = await loadedSettings();
    final ambient = AmbientController();
    // Reduced motion would skip the bloom — use normal motion and accept the
    // perpetual aura ticker by pumping fixed durations (not pumpAndSettle).
    await tester.pumpWidget(await host(settings: settings, ambient: ambient));
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
```
NOTE: the aura ticker runs perpetually in normal-motion tests — use `pump(duration)`, never `pumpAndSettle`, in those; always end by pumping a replacement widget so the ticker disposes. The test references `AmbientLayerState.bloomActiveForTest` — implement that public-for-test getter.

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (no AmbientLayer).

- [ ] **Step 3: Implement the widget** (append to `ambient_layer.dart`):

```dart
// add imports at top of file:
// import 'dart:ui' as ui;
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../session/session_manager.dart';
// import '../settings/settings_service.dart';
// import '../theme/app_theme.dart';

/// Whole-app ambient overlay: two drifting accent auras + static film grain,
/// intensified while a workout is active, plus the one-shot PR bloom. Wraps
/// the app content via MaterialApp.builder; paints ABOVE routes inside an
/// IgnorePointer (screens have opaque backgrounds, so behind-content would be
/// invisible). All gradients — no blur filters.
class AmbientLayer extends StatefulWidget {
  const AmbientLayer({super.key, required this.child});
  final Widget child;

  @override
  State<AmbientLayer> createState() => AmbientLayerState();
}

class AmbientLayerState extends State<AmbientLayer>
    with TickerProviderStateMixin {
  // Virtual clock: advanced by dt × speed each tick → smooth speed changes.
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  double _t = 0;
  double _speed = 1.0;
  double _alpha = _calmAlpha;

  static const _calmAlpha = 0.05;
  static const _activeAlpha = 0.09;
  static const _calmSpeed = 1.0;
  static const _activeSpeed = 2.2;

  // Bloom: one-shot controller restarted on each bloomCount change.
  late final AnimationController _bloom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  AmbientController? _ambient;
  int _seenBloom = 0;

  ui.Image? _grain;

  @visibleForTesting
  bool get bloomActiveForTest => _bloom.isAnimating;

  @override
  void initState() {
    super.initState();
    _makeGrain().then((img) {
      if (mounted) setState(() => _grain = img);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ambient = context.read<AmbientController>();
    if (!identical(ambient, _ambient)) {
      _ambient?.removeListener(_onAmbient);
      _ambient = ambient..addListener(_onAmbient);
      _seenBloom = ambient.bloomCount;
    }
    _syncTicker();
  }

  bool get _enabled => context.read<SettingsService>().ambientEnabled;
  bool get _reduced => MediaQuery.of(context).disableAnimations;

  void _syncTicker() {
    final shouldRun = _enabled && !_reduced;
    if (shouldRun && _ticker == null) {
      _lastElapsed = Duration.zero;
      _ticker = createTicker(_onTick)..start();
    } else if (!shouldRun && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
    _lastElapsed = elapsed;
    final active = context.read<SessionManager>().hasActive;
    final targetSpeed = active ? _activeSpeed : _calmSpeed;
    final targetAlpha = active ? _activeAlpha : _calmAlpha;
    // Ease toward targets (~1s ramp).
    final k = (dt / 1.0).clamp(0.0, 1.0);
    _speed += (targetSpeed - _speed) * k;
    _alpha += (targetAlpha - _alpha) * k;
    _t += dt * _speed;
    if (mounted) setState(() {});
  }

  void _onAmbient() {
    final c = _ambient;
    if (c == null || c.bloomCount == _seenBloom) return;
    _seenBloom = c.bloomCount;
    if (_enabled && !_reduced) _bloom.forward(from: 0);
  }

  Future<ui.Image> _makeGrain() async {
    const size = 128;
    final rng = math.Random(7);
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      final v = rng.nextInt(256);
      pixels[i * 4] = v;
      pixels[i * 4 + 1] = v;
      pixels[i * 4 + 2] = v;
      pixels[i * 4 + 3] = 18; // ~7% per-pixel alpha; layer alpha trims further
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: size,
      height: size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ambient?.removeListener(_onAmbient);
    _bloom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-render when the toggle or session state flips.
    final enabled = context.watch<SettingsService>().ambientEnabled;
    context.watch<SessionManager>(); // active-state changes re-sync targets
    if (!enabled) {
      // Pure passthrough; also tears down the ticker.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncTicker();
      });
      return widget.child;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker();
    });

    final tokens = context.tokens;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _bloom,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _AmbientPainter(
                  t: _t,
                  alpha: _alpha,
                  accent: tokens.accent,
                  grain: _grain,
                  bloom: _bloom.isAnimating ? _bloom.value : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.t,
    required this.alpha,
    required this.accent,
    required this.grain,
    required this.bloom,
  });

  final double t;
  final double alpha;
  final Color accent;
  final ui.Image? grain;
  final double? bloom; // 0..1 progress of the PR wash, null when idle

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide * 0.7;

    void aura(double px, double py, double phase, double alphaScale) {
      final p = auraPosition(t, periodX: px, periodY: py, phase: phase);
      final center = Offset(p.x * size.width, p.y * size.height);
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          d / 2,
          [
            accent.withValues(alpha: alpha * alphaScale),
            accent.withValues(alpha: 0),
          ],
        );
      canvas.drawCircle(center, d / 2, paint);
    }

    aura(26, 34, 0, 1.0);
    aura(34, 22, 3.1, 0.8);

    // PR bloom: expanding accent wash, opacity 0 → peak → 0.
    final b = bloom;
    if (b != null) {
      final fade = math.sin(b * math.pi); // 0→1→0
      final radius = size.longestSide * (0.6 + 0.4 * b);
      final center = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            accent.withValues(alpha: 0.18 * fade),
            accent.withValues(alpha: 0),
          ]),
      );
    }

    // Static film grain, tiled.
    final g = grain;
    if (g != null) {
      final paint = Paint()
        ..shader = ui.ImageShader(
          g,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..color = const Color(0x55FFFFFF); // trims tile alpha to ~0.03 effective
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.t != t ||
      old.alpha != alpha ||
      old.accent != accent ||
      old.grain != grain ||
      old.bloom != bloom;
}
```
Add the missing imports (`dart:typed_data` for Uint8List if not via foundation, `dart:ui as ui`, `flutter/material.dart`, `flutter/scheduler.dart` for Ticker if needed — TickerProviderStateMixin provides createTicker; analyze guides). NOTE on `Paint()..shader..color`: a Paint with BOTH shader and color modulates the shader by the color's opacity — verify the grain renders subtly; if the modulation doesn't behave (renders too strong), instead bake the final alpha into the tile pixels (lower the `18` to ~8) and drop the `color` line. Reduced-motion static render: when the ticker is off, `_t` stays at its last value (0 on first build) — auras paint once, static, which is the spec behavior.

- [ ] **Step 4: Run `make -C app analyze` (clean) + `make -C app test` — expect 194 (190 + 4).**

- [ ] **Step 5: Commit**
```bash
git add app/lib/widgets/ambient_layer.dart app/test/widgets/ambient_layer_test.dart
git commit -m "feat(app): AmbientLayer — drifting accent auras, film grain, PR bloom"
```

---

### Task 3: Wiring — MaterialApp.builder, provider, PR trigger, Appearance toggle

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/session/set_row.dart`
- Modify: `app/lib/ui/profile_screen.dart`

- [ ] **Step 1: main.dart.** Add import `widgets/ambient_layer.dart`. Add to the MultiProvider list:
```dart
        ChangeNotifierProvider(create: (_) => AmbientController()),
```
Add to the MaterialApp (it currently has no `builder:`):
```dart
            builder: (ctx, child) => AmbientLayer(child: child!),
```

- [ ] **Step 2: set_row.dart PR trigger.** Add imports `package:provider/provider.dart` and `../widgets/ambient_layer.dart`. In the check-button `onTap` (~:143-152):
```dart
                if (!done) {
                  // Toggling TO done: PR landing gets the heaviest impact.
                  if (isLivePr) {
                    HapticFeedback.heavyImpact();
                    context.read<AmbientController>().bloom();
                  } else {
                    HapticFeedback.mediumImpact();
                  }
                } else {
```
CHECK the enclosing build method has `context` in scope at that closure (it's a build-tree GestureDetector — it does). Existing set_row tests pump SetRow WITHOUT an AmbientController provider — `context.read` would throw ProviderNotFoundException on PR taps. Two acceptable fixes: (a) wrap the affected TESTS with `ChangeNotifierProvider(create: (_) => AmbientController())`, or (b) make the trigger tolerant: `Provider.of<AmbientController>(context, listen: false)` inside a try/catch is ugly — prefer (a); if NO existing test taps a live-PR row, nothing breaks and (a) is unnecessary. Verify by running the suite.

- [ ] **Step 3: profile_screen.dart Appearance toggle.** Add an "Ambient effects" row after the Accent row in the Appearance `_Group` (:562-585). `Toggle` comes from `../widgets/plan_form.dart` (already imported in profile_screen — verify):
```dart
                    _Row(
                      icon: WIcons.bolt,
                      title: 'Ambient effects',
                      sub: 'Drifting accent glow & grain',
                      right: Toggle(
                        value: settings.ambientEnabled,
                        onChanged: settings.setAmbientEnabled,
                      ),
                    ),
```

- [ ] **Step 4: Verify.**
- `make -C app analyze` → clean
- `make -C app test` → 194 green (fix any provider-missing test fallout per Step 2 — fix TESTS, not the implementation)
- `make -C app build` → Linux build succeeds; OPTIONAL eyeball: run the Linux binary briefly to sanity-check the ambient renders and the toggle kills it.

- [ ] **Step 5: Commit**
```bash
git add app/lib/main.dart app/lib/session/set_row.dart app/lib/ui/profile_screen.dart
git commit -m "feat(app): wire ambient layer — app root, PR bloom trigger, settings toggle"
```

---

### Task 4: Verify + ship v0.8.0 (INLINE — run by the orchestrating session, not a subagent)

- [ ] `make -C app analyze` + `make -C app test` (expect ~194) + `make -C app build-apk-release` → green.
- [ ] Final adversarial review subagent over `git diff main...ambient-layer`: ticker lifecycle (toggle on/off/reduced-motion transitions, dispose, post-frame _syncTicker races), per-frame setState cost + RepaintBoundary isolation (does the CHILD repaint each tick? — the Stack rebuilds on setState; verify the child subtree doesn't repaint, else restructure so only the painter rebuilds via ListenableBuilder/ValueNotifier instead of setState), bloom listener/dedup, grain Paint shader+color modulation correctness, provider lookups in builder context (MaterialApp.builder context is BELOW the providers? — providers wrap MaterialApp, builder ctx is under MaterialApp → fine, verify), memory of ui.Image (disposed?), set_row provider fallout.
- [ ] Merge `--no-ff` → main, push, tag `v0.8.0` → CI publishes `reps-v0.8.0.apk`. User on-device: calm drift, workout intensification, PR bloom on a heavier set, grain subtlety, accent-switch reactivity, toggle off, battery feel.

### Out of scope
Letterbox backlight; shaders/Lottie; animated grain; per-screen variations.
