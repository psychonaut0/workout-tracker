import 'package:flutter/material.dart';
import 'tokens.dart';

/// Build a [ThemeData] with [WorkoutTokens] wired as a [ThemeExtension].
/// Typography is applied in [WorkoutType] and wired via [_buildTextTheme].
ThemeData buildTheme(Brightness brightness, Color accent) {
  final tokens = brightness == Brightness.dark
      ? WorkoutTokens.dark(accent)
      : WorkoutTokens.light(accent);

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: tokens.bg,
    extensions: [tokens],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: tokens.accentInk,
      secondary: accent,
      onSecondary: tokens.accentInk,
      error: tokens.danger,
      onError: tokens.accentInk,
      surface: tokens.surface,
      onSurface: tokens.text,
    ),
  );
}

/// Convenience extension so any widget can write `context.tokens`.
extension ThemeTokens on BuildContext {
  WorkoutTokens get tokens => Theme.of(this).extension<WorkoutTokens>()!;
}
