import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

import '../support/l10n_harness.dart';

void main() {
  group('RulerScale', () {
    test('an on-grid anchor starts the tape at min', () {
      final s = RulerScale(anchor: 100, step: 2.5, min: 0, max: 500);
      expect(s.valueAt(0), 0);
      expect(s.indexOf(100), 40);
      expect(s.valueAt(41), 102.5);
      expect(s.count, 201);
    });

    test('an off-grid anchor shifts the whole tape so it is exact', () {
      final s = RulerScale(anchor: 101, step: 2.5, min: 0, max: 500);
      final i = s.indexOf(101);
      expect(s.valueAt(i), 101);
      expect(s.valueAt(i + 1), 103.5);
      expect(s.valueAt(i - 1), 98.5);
      expect(s.valueAt(0), 1);
    });

    test('indexOf clamps to the ends and the tape grows to fit the anchor', () {
      final s = RulerScale(anchor: 620, step: 5, min: 0, max: 500);
      expect(s.valueAt(s.indexOf(620)), 620);
      expect(s.indexOf(-50), 0);
      expect(s.indexOf(10000), s.count - 1);
    });

    test('fractional steps do not drift', () {
      final s = RulerScale(anchor: 40, step: 1.25, min: 0, max: 500);
      expect(s.valueAt(s.indexOf(40) + 3), 43.75);
    });
  });

  group('RulerPicker', () {
    late List<double> changes;
    late int taps;
    setUp(() {
      changes = [];
      taps = 0;
    });

    Widget ruler({double value = 100, double step = 2.5}) => wrapL10n(Center(
          child: SizedBox(
            width: 320,
            child: RulerPicker(
              value: value,
              step: step,
              max: 500,
              format: (v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v',
              semanticLabel: 'Weight',
              onChanged: changes.add,
              onTapValue: () => taps++,
            ),
          ),
        ));

    testWidgets('swiping left moves up the tape and snaps onto a value', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-3 * RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes, isNotEmpty);
      expect(changes.last, 107.5);
      final ctrl = tester
          .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .controller as FixedExtentScrollController;
      final steps = ctrl.offset / RulerPicker.defaultItemExtent;
      expect(steps, closeTo(steps.roundToDouble(), 0.01)); // snapped onto a mark
    });

    testWidgets('swiping right moves down the tape', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(3 * RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes.last, 92.5);
    });

    testWidgets('a rebuild with the same value never reports a change', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.pumpWidget(ruler());
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('an external value change re-centres without reporting it back', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.pumpWidget(ruler(value: 121)); // off the old grid
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      final ctrl = tester
          .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .controller as FixedExtentScrollController;
      final state = tester.state<RulerPickerState>(find.byType(RulerPicker));
      expect(state.scale.valueAt(ctrl.selectedItem), 121);
    });

    testWidgets('tapping the centre value asks for typed entry', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.tap(find.byKey(const Key('ruler-centre')));
      expect(taps, 1);
    });

    testWidgets('it is a slider for screen readers, with increase and decrease', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(ruler());
      final node = tester.getSemantics(find.bySemanticsLabel('Weight'));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.value, '100');
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(changes.last, 102.5);
      handle.dispose();
    });
  });
}
