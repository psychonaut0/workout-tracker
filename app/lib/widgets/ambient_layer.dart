import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../session/session_manager.dart';
import '../settings/settings_service.dart';
import '../theme/app_theme.dart';

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

/// Grain tile pixel data in PREMULTIPLIED rgba8888 (the contract of
/// `ui.PixelFormat.rgba8888` / `ImageDescriptor.raw`). Each pixel is a gray
/// speckle of straight-alpha brightness v∈0..255 at [alpha], stored
/// premultiplied: channels = round(v·alpha/255) ≤ alpha. Writing straight
/// values here composites as massively over-bright noise (the v0.8.0
/// full-screen static bug).
Uint8List grainPixels({
  required int size,
  required int seed,
  required int alpha,
}) {
  final rng = math.Random(seed);
  final pixels = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    final v = rng.nextInt(256);
    final premul = (v * alpha) ~/ 255;
    pixels[i * 4] = premul;
    pixels[i * 4 + 1] = premul;
    pixels[i * 4 + 2] = premul;
    pixels[i * 4 + 3] = alpha;
  }
  return pixels;
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

/// Whole-app ambient overlay: two drifting accent auras + static film grain,
/// intensified while a workout is active, plus the one-shot PR bloom. Wraps
/// the app content via MaterialApp.builder; paints ABOVE routes inside an
/// IgnorePointer (screens have opaque backgrounds, so behind-content would be
/// invisible). All gradients — no blur filters.
class AmbientLayer extends StatefulWidget {
  const AmbientLayer({super.key, required this.child});
  final Widget child;

  /// Identifies the ambient overlay subtree (absent in passthrough). The
  /// MaterialApp/Navigator add their own RepaintBoundary/IgnorePointer widgets,
  /// so this key is the unambiguous handle for the overlay.
  static const Key overlayKey = Key('ambient-overlay');

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
  // Created eagerly in initState so dispose() never lazily builds a Ticker on
  // a deactivated element (TickerMode ancestor lookup would assert).
  late final AnimationController _bloom;
  AmbientController? _ambient;
  int _seenBloom = 0;

  ui.Image? _grain;

  @visibleForTesting
  bool get bloomActiveForTest => _bloom.isAnimating;

  @override
  void initState() {
    super.initState();
    _bloom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
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
    final dt = (elapsed - _lastElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
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
    final pixels = grainPixels(size: size, seed: 7, alpha: 8);
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
    _grain?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<SettingsService>().ambientEnabled;
    // Intensity targets are read fresh inside _onTick each frame — no need to
    // watch SessionManager here (it would just force redundant rebuilds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker();
    });
    if (!enabled) return widget.child;

    final tokens = context.tokens;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        IgnorePointer(
          key: AmbientLayer.overlayKey,
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

    // Static film grain, tiled. Alpha is baked into the tile (subtle).
    final g = grain;
    if (g != null) {
      final paint = Paint()
        ..shader = ui.ImageShader(
          g,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        );
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
