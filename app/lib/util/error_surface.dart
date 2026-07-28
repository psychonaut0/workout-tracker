import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Replaces Flutter's default release ErrorWidget — a featureless gray box —
/// with a card that says what actually went wrong and copies the full details
/// on tap.
void installErrorSurface() {
  ErrorWidget.builder = _buildErrorCard;
}

/// Builds the replacement error card.
///
/// The card is deliberately dependency-free. An ErrorWidget can be inflated
/// ABOVE MaterialApp, so there may be no Theme, Directionality, MediaQuery or
/// localizations in scope: it supplies its own Directionality, hardcodes its
/// colours, and uses no design tokens, no AppLocalizations and no Scaffold. Its
/// text wraps and scrolls so it cannot overflow inside a tightly constrained
/// sliver child. If this widget threw, the user would see nothing at all —
/// which is worse than the gray box it replaces.
Widget _buildErrorCard(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  final stack = details.stack?.toString() ?? '';
  final copyText = stack.isEmpty ? message : '$message\n\n$stack';
  return Directionality(
    textDirection: TextDirection.ltr,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Clipboard.setData(ClipboardData(text: copyText)),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF2A1416),
        child: SingleChildScrollView(
          child: Text(
            message,
            softWrap: true,
            style: const TextStyle(
              color: Color(0xFFFFB4AB),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ),
    ),
  );
}
