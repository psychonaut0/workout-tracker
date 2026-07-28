/// Shared semantics for interpreting typed numeric text.
///
/// Lives apart from any widget so the stepper and the bodyweight sheet cannot
/// drift apart, and so the rules are testable without pumping a widget.
library;

/// Clamps [v] into `[min, max]` and rounds to two decimals.
///
/// Two decimals kills floating-point drift from repeated stepping; [max] of
/// null means unbounded.
double clampRound2(double v, {double min = 0, double? max}) {
  var out = v < min ? min : v;
  if (max != null && out > max) out = max;
  // A tiny nudge away from zero before rounding compensates for decimal
  // literals that have no exact binary double representation — e.g. 1.005 is
  // actually stored as 1.00499999999999989..., which would otherwise round
  // down to 1.00 instead of the mathematically intended 1.01.
  final nudge = out.isNegative ? -1e-9 : 1e-9;
  return (out * 100 + nudge).round() / 100;
}

/// Interprets [raw] typed text as a value in the caller's space.
///
/// Returns null to mean "leave the current value alone" — either the text was
/// not a number, or it was empty and no [emptyValue] sentinel was supplied.
/// Callers must NOT treat null as zero.
///
/// A comma is accepted as the decimal separator, since Italian, German and
/// Spanish keyboards produce one. [parseDisplay] converts from display space to
/// the caller's space (e.g. lb to kg) and is applied BEFORE clamping, so the
/// bounds are always expressed in the caller's space.
double? parseNumberInput(
  String raw, {
  double min = 0,
  double? max,
  double? emptyValue,
  double Function(double display)? parseDisplay,
}) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return emptyValue;
  final typed = double.tryParse(text);
  if (typed == null) return null;
  final mapped = parseDisplay?.call(typed) ?? typed;
  return clampRound2(mapped, min: min, max: max);
}
