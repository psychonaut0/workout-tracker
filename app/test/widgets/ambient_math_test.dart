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
