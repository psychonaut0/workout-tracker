import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';

import '../support/l10n_harness.dart';

void main() {
  testWidgets('RirPicker honours its height', (tester) async {
    await tester.pumpWidget(wrapL10n(
        SizedBox(width: 232, child: RirPicker(value: 1, height: 48, onChanged: (_) {}))));
    expect(tester.getSize(find.byKey(const Key('rir-2'))).height, 48);
  });
}
