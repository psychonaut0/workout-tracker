import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Weight unit the user has selected. Everything is stored internally in kg;
/// this service converts at the view layer only.
enum Unit { kg, lb }

/// Reactive unit service backed by shared_preferences.
class UnitService extends ChangeNotifier {
  Unit _unit = Unit.kg;

  Unit get unit => _unit;

  /// lb conversion factor: 1 kg = 2.2046226 lb.
  static const double lbFactor = 2.2046226;

  /// Read the persisted unit preference. Defaults to kg.
  /// Call once at startup before providing the service.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('unit');
    _unit = stored == Unit.lb.name ? Unit.lb : Unit.kg;
    notifyListeners();
  }

  /// Switch the active unit and persist. Notifies listeners only when changed.
  void setUnit(Unit u) {
    if (u == _unit) return;
    _unit = u;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('unit', u.name))
        .ignore(); // best-effort; callers should await load() for the next read
    notifyListeners();
  }

  /// Convert a kg value to the given [unit].
  static double fromKg(double kg, Unit unit) =>
      unit == Unit.lb ? kg * lbFactor : kg;

  /// Convert a value in the given [unit] back to kg.
  static double toKg(double v, Unit unit) =>
      unit == Unit.lb ? v / lbFactor : v;

  /// Format a weight in kg for display in the current unit.
  ///
  /// kg:  integer values shown bare ("80"), non-integer to 1 dp ("72.5").
  /// lb:  converted and rounded to whole number ("220").
  String fmtWt(double kg) {
    final v = fromKg(kg, _unit);
    if (_unit == Unit.lb) {
      return v.round().toString();
    }
    // kg: drop trailing ".0"
    if (v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  }

  /// The current unit label ("kg" or "lb").
  String get uLabel => _unit == Unit.lb ? 'lb' : 'kg';
}
