import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/line_chart.dart';

import '../support/l10n_harness.dart';

void main() {
  testWidgets("the last point's value chip reads through the caller's formatter",
      (tester) async {
    final formatted = <double>[];
    await tester.pumpWidget(wrapL10n(SizedBox(
      width: 320,
      child: LineChart(
        series: const [
          (date: '2026-09-01', value: 1474.0, reps: 5, isPr: false),
          (date: '2026-09-08', value: 1482.5, reps: 5, isPr: false),
        ],
        unit: 'kg',
        showReps: false,
        formatValue: (v) {
          formatted.add(v);
          return '1,483';
        },
      ),
    )));
    // The chip paints once the 450ms mount has drawn the line in.
    await tester.pump(const Duration(milliseconds: 500));
    expect(formatted, contains(1482.5));
  });
}
