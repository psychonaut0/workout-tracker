import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/sparkline.dart';

Widget _host(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('light theme: the sparkline stroke is accentText, not the raw accent',
      (tester) async {
    final theme = buildTheme(Brightness.light, accents[3]);
    final t = theme.extension<WorkoutTokens>()!;
    await tester.pumpWidget(
        _host(theme, const Sparkline(values: [1, 3, 2, 4])));
    await tester.pumpAndSettle();
    final paint = tester.widget<CustomPaint>(find
        .descendant(of: find.byType(Sparkline), matching: find.byType(CustomPaint))
        .first);
    // The painter is private; a dynamic read reaches its stroke field.
    expect((paint.painter as dynamic).stroke, t.accentText);
    expect(t.accentText, isNot(t.accent));
  });

  testWidgets('light theme: a focused text field draws its floating label in accentText',
      (tester) async {
    final theme = buildTheme(Brightness.light, accents[3]);
    final t = theme.extension<WorkoutTokens>()!;
    await tester.pumpWidget(_host(
        theme, const TextField(decoration: InputDecoration(labelText: 'Email'))));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final style = tester.widget<AnimatedDefaultTextStyle>(find
        .ancestor(of: find.text('Email'), matching: find.byType(AnimatedDefaultTextStyle))
        .first).style;
    expect(style.color, t.accentText);
    expect(t.accentText, isNot(t.accent));
  });
}
