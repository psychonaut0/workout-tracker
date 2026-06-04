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
