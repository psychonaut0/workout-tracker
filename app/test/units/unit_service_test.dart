import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/units/unit_service.dart';

void main() {
  test('kg formatting strips trailing .0; lb converts + rounds whole', () {
    final u = UnitService()..setUnit(Unit.kg);
    expect(u.fmtWt(72.5), '72.5');
    expect(u.fmtWt(80.0), '80');
    expect(u.uLabel, 'kg');
    u.setUnit(Unit.lb);
    expect(u.uLabel, 'lb');
    expect(u.fmtWt(100.0), '220'); // 100 * 2.2046226 -> 220 (whole)
  });
  test('toKg/fromKg round-trip via factor 2.2046226', () {
    expect(UnitService.fromKg(10, Unit.lb), closeTo(22.046226, 1e-6));
    expect(UnitService.toKg(22.046226, Unit.lb), closeTo(10, 1e-6));
  });
}
