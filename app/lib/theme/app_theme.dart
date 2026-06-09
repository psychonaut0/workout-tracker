import 'package:flutter/material.dart';
import 'tokens.dart';
import 'typography.dart';

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
    textTheme: WorkoutType.hankenTextTheme,
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
///
/// Falls back to [WorkoutTokens.dark] with the default lime accent when the
/// theme extension is not present (e.g. in widget tests that use plain
/// [MaterialApp] without [buildTheme]).
extension ThemeTokens on BuildContext {
  WorkoutTokens get tokens =>
      Theme.of(this).extension<WorkoutTokens>() ??
      WorkoutTokens.dark(const Color(0xFFc2f53a));
}
