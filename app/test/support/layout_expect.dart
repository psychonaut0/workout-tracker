import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Fails if a laid-out paragraph starts a line between two letters or digits
/// — a word split across lines ("BODYWEI/GHT", "1/200"). A break at a space
/// or a hyphen passes; so does a line cut short by an ellipsis.
///
/// [within] limits the check to paragraphs under the matched widgets (and
/// must match something); [where] prefixes the failure message. Offstage
/// paragraphs (hidden IndexedStack tabs) are laid out, so they count.
void expectNoSplitWords(WidgetTester tester, {Finder? within, String? where}) {
  final prefix = where == null ? '' : '$where: ';
  if (within != null && within.evaluate().isEmpty) {
    fail('${prefix}nothing matched $within');
  }
  final texts = within == null
      ? find.byType(RichText, skipOffstage: false)
      : find.descendant(
          of: within,
          matching: find.byType(RichText, skipOffstage: false),
          matchRoot: true,
          skipOffstage: false,
        );
  final seen = <RenderParagraph>{};
  final offenders = <String>[];
  for (final element in texts.evaluate()) {
    final p = element.renderObject;
    if (p is! RenderParagraph || !seen.add(p)) continue;
    if (!p.attached || !p.hasSize || p.debugNeedsLayout) continue;
    final split = _firstSplit(p);
    if (split != null) offenders.add(split);
  }
  if (offenders.isNotEmpty) {
    fail('${prefix}words split across lines:\n  ${offenders.join('\n  ')}');
  }
}

String? _firstSplit(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  Rect? previous;
  for (var i = 0; i < text.length; i++) {
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    final rect = boxes.isEmpty ? null : boxes.first.toRect();
    if (i > 0 &&
        rect != null &&
        previous != null &&
        _wordChar.hasMatch(text[i - 1]) &&
        _wordChar.hasMatch(text[i]) &&
        rect.top >= previous.bottom - 0.5) {
      return '"$text" breaks inside a word: '
          '"${text.substring(0, i)}|${text.substring(i)}"';
    }
    previous = rect;
  }
  return null;
}

/// Fails unless the paragraph of [text] sits on a single line.
void expectOneLine(WidgetTester tester, Finder text) {
  final p = tester.renderObject<RenderParagraph>(text);
  final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
  expect(
    p.size.height,
    lessThan(line * 1.5),
    reason: '"${p.text.toPlainText()}" should sit on one line',
  );
}
