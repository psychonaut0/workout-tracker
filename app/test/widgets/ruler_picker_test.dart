import 'package:flutter/gestures.dart';
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

    RulerPickerState state(WidgetTester tester) =>
        tester.state<RulerPickerState>(find.byType(RulerPicker));

    testWidgets('swiping left moves up the tape and snaps onto a value', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-3 * RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes, [102.5, 105, 107.5]);
      expect(state(tester).position, 107.5); // snapped onto a mark
    });

    testWidgets('swiping right moves down the tape', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(3 * RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes.last, 92.5);
    });

    testWidgets('a drag past the end stops at the lowest value', (tester) async {
      await tester.pumpWidget(ruler(value: 5));
      await tester.timedDrag(find.byType(RulerPicker), const Offset(10 * RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes, [2.5, 0]);
      expect(state(tester).position, 0);
    });

    testWidgets('a fling travels several values and lands exactly on one', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.fling(find.byType(RulerPicker), const Offset(-150, 0), 3000);
      await tester.pumpAndSettle();
      expect(changes.length, greaterThan(4), reason: 'the glide should carry on past the drag');
      for (var i = 1; i < changes.length; i++) {
        expect(changes[i] - changes[i - 1], 2.5, reason: 'each value is reported once, in order');
      }
      final pos = state(tester).position;
      expect(pos, changes.last);
      expect((pos - 100) / 2.5, closeTo(((pos - 100) / 2.5).roundToDouble(), 1e-9));
    });

    testWidgets('settleAll stops a glide on the last reported value', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.fling(find.byType(RulerPicker), const Offset(-150, 0), 3000);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final shown = changes.last;
      final reported = changes.length;
      RulerPicker.settleAll();
      await tester.pumpAndSettle();
      expect(changes.length, reported, reason: 'nothing reported after settling');
      expect(state(tester).position, shown);
    });

    testWidgets('a handed-in value off the two-decimal grid is not echoed back',
        (tester) async {
      await tester.pumpWidget(ruler());
      await tester.pumpWidget(ruler(value: 3 * 1.1, step: 1.1)); // 3.3000000000000003
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('a non-positive step does not crash the tape', (tester) async {
      await tester.pumpWidget(ruler(step: 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an external value change re-centres without reporting it back', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.pumpWidget(ruler(value: 105));
      await tester.pumpAndSettle();
      expect(state(tester).position, 105);
      await tester.pumpWidget(ruler(value: 121)); // off the old grid
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(state(tester).position, 121);
      // The tape moves in steps from the handed-in value.
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-RulerPicker.defaultItemExtent, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(changes, [123.5]);
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
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(taps, 1, reason: 'typed entry must be reachable with a screen reader');
      handle.dispose();
    });
  });

  group('RulerPicker zoom', () {
    late List<double> changes;
    setUp(() => changes = []);

    String fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

    Widget ruler({double value = 100, double? fineStep = 0.25}) => wrapL10n(Center(
          child: SizedBox(
            width: 320,
            child: RulerPicker(
              value: value,
              step: 1,
              fineStep: fineStep,
              max: 500,
              format: fmt,
              semanticLabel: 'Weight',
              onChanged: changes.add,
            ),
          ),
        ));

    RulerPickerState state(WidgetTester tester) =>
        tester.state<RulerPickerState>(find.byType(RulerPicker));
    bool whole(double v) => v == v.roundToDouble();
    bool quarter(double v) => (v * 4) == (v * 4).roundToDouble();

    /// Drags [steps] moves of [dx] each, one every 16 ms of the fake clock,
    /// continuing [gesture] from [from].
    Future<Duration> slide(WidgetTester tester, TestGesture gesture, Duration from,
        {required int steps, required double dx}) async {
      var t = from;
      for (var i = 0; i < steps; i++) {
        t += const Duration(milliseconds: 16);
        await gesture.moveBy(Offset(dx, 0), timeStamp: t);
        await tester.pump(const Duration(milliseconds: 16));
      }
      return t;
    }

    testWidgets('a fast swipe moves in coarse steps only', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-300, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(changes, isNotEmpty);
      expect(changes.every(whole), isTrue, reason: '$changes');
      expect(state(tester).zoom, 0);
      expect(state(tester).position, changes.last);
    });

    testWidgets('a slow drag zooms in and lands on a fine value', (tester) async {
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-150, 0),
          const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final last = changes.last;
      expect(quarter(last), isTrue, reason: '$changes');
      expect(whole(last), isFalse, reason: '$changes');
      expect(state(tester).position, last);
      expect(state(tester).zoom, 1, reason: 'a fractional value rests zoomed');
    });

    testWidgets('a hold then a small move steps by the fine step', (tester) async {
      await tester.pumpWidget(ruler());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await tester.pump(kHoldDwell + const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200)); // zoom animation
      expect(state(tester).zoom, 1);
      // Past the touch slop, then exactly one fine slot.
      await gesture.moveBy(const Offset(-kTouchSlop - 2, 0), timeStamp: const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(-kFineExtent, 0), timeStamp: const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up(timeStamp: const Duration(milliseconds: 2400));
      await tester.pumpAndSettle();
      expect(changes, [100.25]);
      expect(state(tester).zoom, 1);
    });

    testWidgets('a hold released in place zooms back out without reporting', (tester) async {
      await tester.pumpWidget(ruler());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await tester.pump(kHoldDwell + const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state(tester).zoom, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(state(tester).zoom, 0);
    });

    testWidgets('a zoomed drag that lands on a whole value rests coarse', (tester) async {
      await tester.pumpWidget(ruler());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await tester.pump(kHoldDwell + const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(-kTouchSlop - 2, 0), timeStamp: const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(-4 * kFineExtent, 0), timeStamp: const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up(timeStamp: const Duration(milliseconds: 4000));
      await tester.pumpAndSettle();
      expect(changes, [100.25, 100.5, 100.75, 101]);
      expect(state(tester).zoom, 0);
    });

    testWidgets('speeding up mid-drag zooms back out', (tester) async {
      await tester.pumpWidget(ruler());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      // ~94 dp/s: slow enough to zoom in.
      var t = await slide(tester, gesture, Duration.zero, steps: 40, dx: -1.5);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state(tester).zoom, 1);
      // ~1250 dp/s.
      t = await slide(tester, gesture, t, steps: 6, dx: -20);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state(tester).zoom, 0);
      await gesture.up(timeStamp: t);
      await tester.pumpAndSettle();
      expect(whole(changes.last), isTrue, reason: '$changes');
      expect(state(tester).zoom, 0);
    });

    testWidgets('a fractional value rests zoomed; a fast drag from it lands on the coarse grid',
        (tester) async {
      await tester.pumpWidget(ruler(value: 60.25));
      expect(state(tester).zoom, 1);
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-300, 0),
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(whole(changes.last), isTrue, reason: '$changes');
      expect(state(tester).position, changes.last);
      expect(state(tester).zoom, 0);
    });

    testWidgets('an on-grid value rests coarse, and handed-in values set the zoom', (tester) async {
      await tester.pumpWidget(ruler(value: 60));
      expect(state(tester).zoom, 0);
      await tester.pumpWidget(ruler(value: 60.5));
      await tester.pumpAndSettle();
      expect(state(tester).zoom, 1);
      expect(state(tester).position, 60.5);
      await tester.pumpWidget(ruler(value: 61));
      await tester.pumpAndSettle();
      expect(state(tester).zoom, 0);
      expect(changes, isEmpty);
    });

    testWidgets('a value off both grids keeps its own fine grid', (tester) async {
      await tester.pumpWidget(ruler(value: 60.3));
      expect(state(tester).zoom, 1);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await gesture.moveBy(const Offset(-kTouchSlop - 2, 0), timeStamp: const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(-kFineExtent, 0), timeStamp: const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up(timeStamp: const Duration(milliseconds: 2100));
      await tester.pumpAndSettle();
      expect(changes, [60.55]);
    });

    testWidgets('screen-reader steps are fine while resting zoomed', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(ruler(value: 60.25));
      final node = tester.getSemantics(find.bySemanticsLabel('Weight'));
      expect(node.increasedValue, '60.5');
      expect(node.decreasedValue, '60');
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(changes, [60.5]);
      handle.dispose();
    });

    testWidgets('settleAll during a zoom rests on the last value at its zoom', (tester) async {
      await tester.pumpWidget(ruler());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await tester.pump(kHoldDwell + const Duration(milliseconds: 20));
      RulerPicker.settleAll();
      expect(state(tester).zoom, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('no zoom without a fine step', (tester) async {
      await tester.pumpWidget(ruler(fineStep: null));
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-150, 0),
          const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(state(tester).zoom, 0);
      expect(changes, [101, 102]);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(RulerPicker)));
      await tester.pump(const Duration(seconds: 1));
      expect(state(tester).zoom, 0);
      await gesture.up();
    });

    testWidgets('under reduced motion the zoom and glide jump without animating', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures.allOn;
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(ruler());
      await tester.timedDrag(find.byType(RulerPicker), const Offset(-150, 0),
          const Duration(seconds: 2));
      await tester.pump();
      expect(state(tester).zoom, 1);
      expect(state(tester).position, changes.last);
      await tester.fling(find.byType(RulerPicker), const Offset(-150, 0), 3000);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(state(tester).zoom, 0);
      expect(state(tester).position, changes.last);
      expect(whole(changes.last), isTrue, reason: '$changes');
    });
  });
}
