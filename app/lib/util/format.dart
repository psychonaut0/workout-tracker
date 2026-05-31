// Formatting helpers for numeric values in the Progress views.

/// Formats a weight/value as a bare integer if whole, or 1 decimal place
/// (trailing `.0` stripped — mirrors `fmtKg` in ui.jsx).
///
/// Examples: `fmtPlain(80)` → `'80'`, `fmtPlain(72.5)` → `'72.5'`.
String fmtPlain(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  final s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) return s.substring(0, s.length - 2);
  return s;
}

/// Formats a value as a comma-grouped integer string (no `intl` dependency),
/// matching `toLocaleString('en-US')`.
///
/// Examples: `fmtThousands(12500)` → `'12,500'`, `fmtThousands(900)` → `'900'`.
String fmtThousands(double v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '-${buf.toString()}' : buf.toString();
}
