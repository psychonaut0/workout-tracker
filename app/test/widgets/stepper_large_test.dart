import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';
import 'package:workout_tracker/widgets/stepper.dart';

import '../support/l10n_harness.dart';

void main() {
  Widget host(Widget child) => wrapL10n(SizedBox(width: 232, child: child));

  testWidgets('large stepper has 56dp buttons and still steps', (tester) async {
    double? got;
    await tester.pumpWidget(host(WStepper(
      value: 140, step: 2.5, format: (v) => v.toStringAsFixed(1),
      large: true, editable: true, onChanged: (v) => got = v,
    )));
    final inc = tester.getSize(find.byKey(const Key('stepper-inc')));
    expect(inc.width, greaterThanOrEqualTo(56));
    expect(inc.height, greaterThanOrEqualTo(56));
    await tester.tap(find.byKey(const Key('stepper-inc')));
    expect(got, 142.5);
  });

  testWidgets('large editable stepper shows an edit cue under the value', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 140, step: 2.5, format: (v) => '$v', large: true, editable: true, onChanged: (_) {},
    )));
    expect(find.byKey(const Key('stepper-edit-cue')), findsOneWidget);
  });

  testWidgets('default stepper keeps its compact size and has no cue', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 8, step: 1, format: (v) => '$v', editable: true, onChanged: (_) {},
    )));
    expect(tester.getSize(find.byKey(const Key('stepper-inc'))), const Size(25, 34));
    expect(find.byKey(const Key('stepper-edit-cue')), findsNothing);
  });

  testWidgets('large value scales down instead of ellipsising', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: host(WStepper(value: 142.5, step: 2.5, format: (v) => v.toStringAsFixed(1),
          large: true, onChanged: (_) {})),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('RirPicker honours its height', (tester) async {
    await tester.pumpWidget(host(RirPicker(value: 1, height: 48, onChanged: (_) {})));
    expect(tester.getSize(find.byKey(const Key('rir-2'))).height, 48);
  });
}
