import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography helpers for the workout tracker design system.
///
/// Three type scales, each wrapping a Google Font:
///   • display  — Space Grotesk  (headings, big numbers)
///   • body     — Hanken Grotesk (UI text, labels)
///   • mono     — JetBrains Mono (stats, metadata, units)
///
/// google_fonts fetches font files over HTTP on first use and falls back to
/// system fonts offline. GoogleFonts.xxx() returns a TextStyle synchronously,
/// so tests and analyze work without network access.
abstract final class WorkoutType {
  // ── Display (Space Grotesk, 400–700) ───────────────────────────────────────
  // Sizes ~25–40px; negative tracking (−0.02 to −0.03 em).
  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing ?? (size * -0.025),
    );
  }

  // ── Body / UI (Hanken Grotesk, 400–800) ────────────────────────────────────
  // Sizes 13–16px.
  static TextStyle body({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.hankenGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // ── Mono (JetBrains Mono, 400–700) ─────────────────────────────────────────
  // Sizes 9–13px; uppercase labels use letter-spacing 0.06–0.12 em.
  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// A [TextTheme] with Hanken Grotesk as the declared font family.
  ///
  /// Uses the font family name directly rather than routing through
  /// [GoogleFonts.hankenGroteskTextTheme] so that no async font-file fetches
  /// are triggered when this getter is called (e.g. inside [buildTheme] during
  /// tests). The [WorkoutType.body], [display], and [mono] helpers use
  /// [GoogleFonts] at the widget level where async loading is fine.
  static TextTheme get hankenTextTheme {
    const family = 'HankenGrotesk';
    return const TextTheme(
      displayLarge: TextStyle(fontFamily: family, fontSize: 57, fontWeight: FontWeight.w400),
      displayMedium: TextStyle(fontFamily: family, fontSize: 45, fontWeight: FontWeight.w400),
      displaySmall: TextStyle(fontFamily: family, fontSize: 36, fontWeight: FontWeight.w400),
      headlineLarge: TextStyle(fontFamily: family, fontSize: 32, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontFamily: family, fontSize: 22, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontFamily: family, fontSize: 11, fontWeight: FontWeight.w500),
    );
  }
}
