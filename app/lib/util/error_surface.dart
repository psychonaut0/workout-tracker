import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The most recent build error's full details, kept so the on-screen card's
/// copy action can hand over the stack trace.
String _lastDetails = '';

/// Replaces Flutter's default release ErrorWidget — a featureless gray box —
/// with a card that says what actually went wrong and copies the full details
/// on tap, and records each error's details for that copy action.
void installErrorSurface() {
  // Chain to whatever handler is already installed (Flutter's own
  // FlutterError.presentError by default) instead of replacing it outright.
  // Under flutter_test, TestWidgetsFlutterBinding installs its own per-test
  // handler to back tester.takeException(); silently overwriting it would
  // strand that bookkeeping and turn an expected error into a framework
  // assertion failure.
  final reportToPreviousHandler = FlutterError.onError ?? FlutterError.presentError;
  FlutterError.onError = (details) {
    _lastDetails = '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
    reportToPreviousHandler(details);
  };

  ErrorWidget.builder = buildErrorCard;
}

/// Builds the replacement error card.
///
/// Exposed separately from [installErrorSurface] so a test can install ONLY the
/// widget builder: overriding [FlutterError.onError] inside a test steals the
/// error capture the test binding owns, which breaks `takeException()` and
/// wedges the test. Production installs both.
///
/// The card is deliberately dependency-free. An ErrorWidget can be inflated
/// ABOVE MaterialApp, so there may be no Theme, Directionality, MediaQuery or
/// localizations in scope: it supplies its own Directionality, hardcodes its
/// colours, and uses no design tokens, no AppLocalizations and no Scaffold. Its
/// text wraps and scrolls so it cannot overflow inside a tightly constrained
/// sliver child. If this widget threw, the user would see nothing at all —
/// which is worse than the gray box it replaces.
Widget buildErrorCard(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  final ownStack = details.stack?.toString() ?? '';
  // Prefer THIS error's own details, and fall back to the recorded ones only
  // when they belong to the same error. An earlier version always reused the
  // last recorded details, so a card could hand over a previous, unrelated
  // error's text — the opposite of useful when the point is diagnosing what
  // just broke.
  final copyText = ownStack.isNotEmpty
      ? '$message\n\n$ownStack'
      : (_lastDetails.startsWith(message) ? _lastDetails : message);
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
