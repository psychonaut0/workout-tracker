import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/ambient_layer.dart';

void main() {
  test('grain pixels are valid PREMULTIPLIED rgba8888 (channels <= alpha)',
      () {
    // dart:ui PixelFormat.rgba8888 uses premultiplied alpha. Straight-alpha
    // pixels (color up to 255 with alpha 8) composite as massively over-bright
    // noise — the v0.8.0 full-screen static bug. Every color channel must be
    // <= its alpha channel.
    final pixels = grainPixels(size: 128, seed: 7, alpha: 8);
    expect(pixels.length, 128 * 128 * 4);

    var maxChannel = 0;
    for (var i = 0; i < 128 * 128; i++) {
      final r = pixels[i * 4];
      final g = pixels[i * 4 + 1];
      final b = pixels[i * 4 + 2];
      final a = pixels[i * 4 + 3];
      expect(a, 8);
      expect(r, lessThanOrEqualTo(a),
          reason: 'premultiplied red must be <= alpha at pixel $i');
      expect(g, lessThanOrEqualTo(a));
      expect(b, lessThanOrEqualTo(a));
      if (r > maxChannel) maxChannel = r;
    }
    // Still actual noise, not a blank tile.
    expect(maxChannel, greaterThan(0));
  });
}
