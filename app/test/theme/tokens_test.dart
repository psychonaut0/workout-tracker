import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';

void main() {
  test('dark + light tokens resolve; accent applies', () {
    final dark = buildTheme(Brightness.dark, const Color(0xFFc2f53a));
    final light = buildTheme(Brightness.light, const Color(0xFF5ce6a4));
    final d = dark.extension<WorkoutTokens>()!;
    final l = light.extension<WorkoutTokens>()!;
    expect(d.bg, const Color(0xFF0b0b0c));
    expect(l.bg, const Color(0xFFf3f2ec));
    expect(d.accent, const Color(0xFFc2f53a));
    expect(l.accent, const Color(0xFF5ce6a4));
    expect(d.accentInk, const Color(0xFF0b0c08)); // constant in both modes
  });
}
