import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography helpers for the workout tracker design system.
///
/// Three type scales, each wrapping a Google Font:
///   • display  — Space Grotesk  (headings, big numbers)
///   • body     — Hanken Grotesk (UI text, labels)
///   • mono     — JetBrains Mono (stats, metadata, units)
///
/// The faces are bundled in `assets/google_fonts/` (google_fonts' naming,
/// `Family-Weight.ttf`), so they load from the app bundle with no network —
/// the first offline run and the tests included. Runtime fetching stays on
/// as the fallback for a weight that isn't bundled. GoogleFonts.xxx() returns
/// a TextStyle synchronously; the face swaps in once its file has loaded.
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

  /// Material's text theme in Hanken Grotesk, for every widget that styles
  /// its text from the theme (onboarding, login, SnackBars, the date-range
  /// picker).
  ///
  /// google_fonts registers one family per weight (`HankenGrotesk_600`) and
  /// nothing registers the plain name, so the styles must come from
  /// [GoogleFonts.hankenGroteskTextTheme]. Always pass [_hankenSizes]: with
  /// no argument it starts from `ThemeData.light().textTheme`, which brings
  /// a dark text colour onto the dark theme and drops these weights. Colours
  /// stay null, so they come from `colorScheme.onSurface`.
  ///
  /// Because each family is one weight, `copyWith(fontWeight: …)` on these
  /// styles keeps the old face and synthesises the new weight; use [body]
  /// for another weight.
  static TextTheme get hankenTextTheme =>
      GoogleFonts.hankenGroteskTextTheme(_hankenSizes);

  static const _hankenSizes = TextTheme(
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
  );
}
