import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/error_surface.dart';

void main() {
  // Install ONLY the widget builder, never the full surface: overriding
  // FlutterError.onError here would steal the error capture the test binding
  // owns, breaking takeException() and wedging the test.
  late ErrorWidgetBuilder original;
  setUp(() {
    original = ErrorWidget.builder;
    ErrorWidget.builder = buildErrorCard;
  });
  tearDown(() => ErrorWidget.builder = original);

  testWidgets('a build exception renders a readable card, not a blank box',
      (tester) async {
    await tester.pumpWidget(Builder(
      builder: (_) => throw StateError('kaboom-marker'),
    ));

    // The framework still reports the error...
    expect(tester.takeException(), isStateError);
    // ...but the user now sees what it was, with no MaterialApp ancestor.
    expect(find.textContaining('kaboom-marker'), findsOneWidget);
  });

  testWidgets('tapping the card copies the details to the clipboard',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(Builder(
      builder: (_) => throw StateError('copy-me-marker'),
    ));
    expect(tester.takeException(), isStateError);

    await tester.tap(find.textContaining('copy-me-marker'));
    await tester.pump();

    final copied = calls.where((c) => c.method == 'Clipboard.setData');
    expect(copied, isNotEmpty);
    expect(
      (copied.first.arguments as Map)['text'] as String,
      contains('copy-me-marker'),
    );
  });
}
