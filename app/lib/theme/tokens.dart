import 'package:flutter/material.dart';

// ── accent options (Profile) ─────────────────────────────────────────────────
const List<Color> accents = [
  Color(0xFFc2f53a), // lime (default)
  Color(0xFF5ce6a4), // mint
  Color(0xFFffc24b), // amber
  Color(0xFF5cc8ff), // sky
  Color(0xFFc084fc), // purple
];

// ── radius / spacing constants ───────────────────────────────────────────────
abstract final class AppRadius {
  static const double radius = 15;
  static const double pill = 99;
}

abstract final class AppSpacing {
  static const double pad = 16;
}

/// Bottom inset for scrollable pages so trailing content (e.g. delete buttons)
/// clears the straddling center FAB (~99px reach) + tab bar with a gap.
const double kBottomNavInset = 112;

// ── color tokens (ThemeExtension) ────────────────────────────────────────────
class WorkoutTokens extends ThemeExtension<WorkoutTokens> {
  const WorkoutTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.dim,
    required this.faint,
    required this.accent,
    required this.accentInk,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color dim;
  final Color faint;
  final Color accent;
  final Color accentInk;
  final Color danger;

  // accentInk is the same constant in both dark and light modes.
  static const Color _accentInk = Color(0xFF0b0c08);

  // ── dark palette ────────────────────────────────────────────────────────────
  factory WorkoutTokens.dark(Color accent) => WorkoutTokens(
        bg: const Color(0xFF0b0b0c),
        surface: const Color(0xFF131316),
        surface2: const Color(0xFF191920),
        surface3: const Color(0xFF262630),
        line: const Color(0x12ffffff), // rgba(255,255,255,0.07) ≈ 0x12 (18/255)
        lineStrong: const Color(0x24ffffff), // rgba(255,255,255,0.14) ≈ 0x24 (36/255)
        text: const Color(0xFFf3f3f1),
        dim: const Color(0x9Effffff), // rgba(255,255,255,0.62) ≈ 0x9E (158/255)
        faint: const Color(0x61ffffff), // rgba(255,255,255,0.38) ≈ 0x61 (97/255)
        accent: accent,
        accentInk: _accentInk,
        danger: const Color(0xFFff6b5e),
      );

  // ── light palette ───────────────────────────────────────────────────────────
  factory WorkoutTokens.light(Color accent) => WorkoutTokens(
        bg: const Color(0xFFf3f2ec),
        surface: const Color(0xFFffffff),
        surface2: const Color(0xFFf6f5ef),
        surface3: const Color(0xFFe9e8e0),
        line: const Color(0x14000000), // rgba(0,0,0,0.08) ≈ 0x14 (20/255)
        lineStrong: const Color(0x26000000), // rgba(0,0,0,0.15) ≈ 0x26 (38/255)
        text: const Color(0xFF15150f),
        dim: const Color(0x99000000), // rgba(0,0,0,0.6) ≈ 0x99 (153/255)
        faint: const Color(0x66000000), // rgba(0,0,0,0.4) ≈ 0x66 (102/255)
        accent: accent,
        accentInk: _accentInk,
        danger: const Color(0xFFff6b5e),
      );

  @override
  WorkoutTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? line,
    Color? lineStrong,
    Color? text,
    Color? dim,
    Color? faint,
    Color? accent,
    Color? accentInk,
    Color? danger,
  }) {
    return WorkoutTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      danger: danger ?? this.danger,
    );
  }

  @override
  WorkoutTokens lerp(WorkoutTokens? other, double t) {
    if (other == null) return this;
    return WorkoutTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
