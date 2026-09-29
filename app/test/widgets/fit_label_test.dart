import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/typography.dart';
import 'package:workout_tracker/widgets/fit_label.dart';

import '../support/app_fonts.dart';
import '../support/layout_expect.dart';

const _style = TextStyle(fontSize: 20);

/// Plain host: no theme, so every width comes from the test font alone.
Widget _host(
  Widget child, {
  required double width,
  TextScaler scaler = TextScaler.noScaling,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: scaler),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: _style,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Width of [text] on one line at [scale] × the style.
double _natural(String text, {double scale = 1}) {
  final p = TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

RenderFitLabel _fit(WidgetTester tester) =>
    tester.renderObject<RenderFitLabel>(find.byType(FitLabel));

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

void main() {
  setUpAll(preloadAppFonts);

  testWidgets('keeps the full size when the label fits', (tester) async {
    await tester.pumpWidget(
      _host(
        const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') + 10,
      ),
    );
    expect(_fit(tester).appliedScale, 1.0);
    expect(_fit(tester).ellipsized, isFalse);
    expect(_paragraph(tester, 'BODYWEIGHT').textScaler, TextScaler.noScaling);
  });

  testWidgets('shrinks before it ellipsizes', (tester) async {
    await tester.pumpWidget(
      _host(
        const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.97,
      ),
    );
    final p = _paragraph(tester, 'BODYWEIGHT');
    expect(_fit(tester).appliedScale, 0.95);
    expect(_fit(tester).ellipsized, isFalse);
    expect(p.didExceedMaxLines, isFalse);
    expect(p.textScaler.scale(20), closeTo(19, 1e-9));
  });

  testWidgets('ellipsizes on one line at minScale rather than splitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.5,
      ),
    );
    final p = _paragraph(tester, 'BODYWEIGHT');
    expect(_fit(tester).appliedScale, 0.8);
    expect(_fit(tester).ellipsized, isTrue);
    expect(p.maxLines, 1);
    expect(p.didExceedMaxLines, isTrue);
    expect(p.textScaler.scale(20), closeTo(16, 1e-9));
    expectNoSplitWords(tester);
  });

  testWidgets('wraps between words when maxLines allows it', (tester) async {
    await tester.pumpWidget(
      _host(
        const FitLabel('LOWER BODY', style: _style, maxLines: 2),
        width: _natural('LOWER') + 4,
      ),
    );
    final p = _paragraph(tester, 'LOWER BODY');
    expect(_fit(tester).appliedScale, 1.0);
    expect(_fit(tester).ellipsized, isFalse);
    final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(p.size.height, greaterThan(line * 1.5)); // two lines
    expectNoSplitWords(tester);
  });

  testWidgets(
    'shrinks a word too wide for the line even when two lines would do',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const FitLabel('BODYWEIGHT', style: _style, maxLines: 2),
          width: _natural('BODYWEIGHT') * 0.97,
        ),
      );
      expect(_fit(tester).appliedScale, 0.95);
      expectOneLine(tester, find.text('BODYWEIGHT'));
    },
  );

  testWidgets('multiplies the ambient text scale instead of replacing it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT', scale: 2) * 0.97,
        scaler: const TextScaler.linear(2),
      ),
    );
    expect(_fit(tester).appliedScale, 0.95);
    expect(
      _paragraph(tester, 'BODYWEIGHT').textScaler.scale(20),
      closeTo(38, 1e-9),
    );
  });

  testWidgets('keeps the full text in semantics when ellipsized', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.4,
      ),
    );
    expect(_fit(tester).ellipsized, isTrue);
    expect(find.bySemanticsLabel('BODYWEIGHT'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('answers intrinsic sizes, so it works under IntrinsicHeight', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FitLabel('LOWER BODY', style: _style, maxLines: 2),
              ),
              Expanded(child: ColoredBox(color: Color(0xFF000000))),
            ],
          ),
        ),
        width: (_natural('LOWER') + 2) * 2,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(Row)).height,
      tester.getSize(find.text('LOWER BODY')).height,
    );
  });

  testWidgets('re-fits when the text changes', (tester) async {
    final width = _natural('BODY') + 2;
    await tester.pumpWidget(
      _host(const FitLabel('BODY', style: _style), width: width),
    );
    expect(_fit(tester).appliedScale, 1.0);
    await tester.pumpWidget(
      _host(const FitLabel('BODYWEIGHT', style: _style), width: width),
    );
    expect(_fit(tester).ellipsized, isTrue);
  });

  testWidgets('FitLabel.rich fits a label of several styled runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const FitLabel.rich(
          TextSpan(
            children: [
              TextSpan(text: 'UPPER'),
              TextSpan(
                text: ' PUSH',
                style: TextStyle(fontSize: 20, color: Color(0xFF888888)),
              ),
            ],
          ),
          style: _style,
        ),
        width: _natural('UPPER PUSH') * 0.97,
      ),
    );
    expect(_fit(tester).appliedScale, 0.95);
    expect(find.text('UPPER PUSH'), findsOneWidget);
  });
  testWidgets('treats a hyphenated compound as one word', (tester) async {
    const name = 'KURZHANTEL-SCHRAEG';
    await tester.pumpWidget(
      _host(
        const FitLabel(name, style: _style, maxLines: 2),
        width: _natural(name) * 0.6,
      ),
    );
    expect(_fit(tester).appliedScale, 0.8);
    expect(_fit(tester).ellipsized, isTrue);
    expectOneLine(tester, find.text(name));
  });

  testWidgets('never splits a word in a bundled proportional face', (
    tester,
  ) async {
    final style = WorkoutType.body(size: 20, weight: FontWeight.w600);
    final natural = (TextPainter(
      text: TextSpan(text: 'Oberschenkelrückseite', style: style),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    for (final factor in [0.9, 0.6]) {
      await tester.pumpWidget(
        _host(
          FitLabel('Oberschenkelrückseite', style: style, maxLines: 2),
          width: natural * factor,
          scaler: const TextScaler.linear(1),
        ),
      );
      expect(_fit(tester).ellipsized, factor < 0.8, reason: 'width x$factor');
      expectOneLine(tester, find.text('Oberschenkelrückseite'));
      expectNoSplitWords(tester, where: 'width x$factor');
    }
  });
}
