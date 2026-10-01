import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/day_editor.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/ui/plan_screen.dart';
import 'package:workout_tracker/ui/split_tab.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/screen_harness.dart';

final _l = lookupAppLocalizations(const Locale('en'));

Finder get _discardTitle => find.text(_l.planDiscardTitle);

// Field renders its label upper-cased.
Finder _inField(String label, Finder matching) => find.descendant(
      of: find.ancestor(
          of: find.text(label.toUpperCase()), matching: find.byType(Field)),
      matching: matching,
    );

Finder get _workingSetsInc =>
    _inField(_l.dayEditorWorkingSets, find.byKey(const Key('stepper-inc')));
Finder get _workingSetsDec =>
    _inField(_l.dayEditorWorkingSets, find.byKey(const Key('stepper-dec')));
Finder _workingSetsShows(String v) =>
    _inField(_l.dayEditorWorkingSets, find.text(v));

Finder get _startWeightInc => _inField(
    _l.exerciseEditorStartWeight, find.byKey(const Key('stepper-inc')));
Finder get _startWeightDec => _inField(
    _l.exerciseEditorStartWeight, find.byKey(const Key('stepper-dec')));

Finder _dayCard(String name) =>
    find.byWidgetPredicate((w) => w is SplitDayCard && w.name == name);

/// The ids of the day editors mounted now, fading ones included.
List<String?> _dayEditorIds(WidgetTester tester) => [
      for (final e in tester.widgetList<DayEditor>(find.byType(DayEditor)))
        e.id,
    ];

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settleReal(tester, ticks: 3);
}

/// Mounts the shell and switches to the Plan tab.
Future<void> _openPlan(WidgetTester tester, ScreenHarness harness) async {
  await tester.pumpWidget(
      harness.wrap(AppShell(onLogout: () async {}, auth: AuthStore())));
  await settleReal(tester);
  await openTab(tester, WIcons.plan);
}

/// Opens seedLong's four-slot day.
Future<void> _openDay(WidgetTester tester) async {
  await settleUntilFound(tester, _dayCard(longDay), where: 'Plan split');
  await tester.tap(_dayCard(longDay));
  await settleUntilFound(tester, find.byType(DaySlotRow), where: 'day editor');
}

/// Expands the open day's Bench Press slot, scrolling it to the top.
Future<void> _expandBenchPress(WidgetTester tester) => _tapVisible(
    tester,
    find.descendant(
        of: find.byType(DayEditor), matching: find.text('Bench Press')));

/// Opens Bench Press from the Exercises sub-tab.
Future<void> _openExercise(WidgetTester tester) async {
  await tester.tap(find
      .descendant(
          of: find.byType(PlanScreen), matching: find.text(_l.planTabExercises))
      .first);
  final row = find.descendant(
      of: find.byType(PlanScreen), matching: find.text('Bench Press'));
  await settleUntilFound(tester, row, where: 'exercise library');
  await tester.tap(row.first);
  await settleUntilFound(
      tester,
      find.descendant(
          of: find.byType(ExerciseEditor), matching: find.byType(ListView)),
      where: 'exercise editor');
}

/// A system back press, as the platform delivers it.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settleReal(tester, ticks: 10);
}

/// An Android predictive back gesture, started at the left edge and committed.
Future<void> _predictiveBack(WidgetTester tester) async {
  Future<void> send(String method, [Object? arguments]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        SystemChannels.backGesture.codec
            .encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
  await send('startBackGesture', <String, Object?>{
    'touchOffset': <double>[5.0, 300.0],
    'progress': 0.0,
    'swipeEdge': 0,
  });
  await send('commitBackGesture');
  await settleReal(tester, ticks: 10);
}

/// Real-async ticks with short frames until [until] holds: database work
/// lands, but a 220ms editor fade does not finish.
Future<void> _shortTicks(WidgetTester tester,
    {required bool Function() until}) async {
  for (var i = 0; i < 30 && !until(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 4));
  }
}

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  group('day editor', () {
    testWidgets('untouched, back closes it without asking', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a stepped count asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      expect(find.text(_l.planDiscardDayMessage), findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a count stepped up and back down does not ask',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);
      await _tapVisible(tester, _workingSetsDec);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('a half-typed count asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsShows('3'));
      final field = _inField(_l.dayEditorWorkingSets, find.byType(TextField));
      expect(field, findsOneWidget);
      // Still focused: nothing has committed the typed value yet.
      await tester.enterText(field, '5');
      await tester.pump();

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('an edited day name asks before back discards it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await tester.enterText(
          _inField(_l.dayEditorName, find.byType(TextField)), 'Renamed day');
      await tester.pump();

      await _back(tester);
      expect(_discardTitle, findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('Keep editing keeps the edit; Discard closes and drops it',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);
      expect(_workingSetsShows('4'), findsOneWidget);

      await _back(tester);
      await tester.tap(find.text(_l.commonKeepEditing));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(_workingSetsShows('4'), findsOneWidget);

      await _back(tester);
      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);

      await _openDay(tester);
      await _expandBenchPress(tester);
      expect(_workingSetsShows('3'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('Save closes without asking', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final save = find.text(_l.dayEditorSaveChanges);
      await scrollIntoView(tester, find.byType(DayEditor), save);
      await tester.tap(save);
      await settleReal(tester, ticks: 15);
      expect(_discardTitle, findsNothing);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('an edit survives a trip to another tab, with no prompt',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await openTab(tester, WIcons.history);
      expect(find.text(_l.planDiscardTitle, skipOffstage: false), findsNothing);
      expect(find.byType(DayEditor, skipOffstage: false), findsOneWidget);

      await openTab(tester, WIcons.plan);
      expect(_discardTitle, findsNothing);
      expect(_workingSetsShows('4'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a tap that falls through to the outgoing list keeps the '
        'opened editor', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await settleUntilFound(tester, _dayCard('Pull'), where: 'Plan split');
      await tester.tap(_dayCard(longDay));
      await tester.pump(const Duration(milliseconds: 50));
      // The new editor still shows its spinner; the list is fading out.
      await tester.tap(_dayCard('Pull'), warnIfMissed: false);
      await tester.pump();

      await settleUntilFound(tester, find.byType(DaySlotRow),
          where: 'day editor');
      expect(_dayEditorIds(tester), ['d1']);
      await harness.unmount(tester);
    });

    testWidgets('a save that lands after its editor closed leaves the next '
        'editor open', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await settleUntilFound(tester, _dayCard('Pull'), where: 'Plan split');
      await tester.tap(_dayCard('Pull'));
      await settleUntilFound(tester, find.byType(DaySlotRow),
          where: 'day editor');
      final save = find.text(_l.dayEditorSaveChanges);
      await scrollIntoView(tester, find.byType(DayEditor), save);
      final pullSave = find.descendant(
          of: find.byWidgetPredicate((w) => w is DayEditor && w.id == 'd2'),
          matching: find.byType(PrimaryBtn));
      bool pullSaveEnabled() => tester.widget<PrimaryBtn>(pullSave).enabled;

      // Hold the database's write lock, so the save waits for it.
      final release = Completer<void>();
      late Future<void> held;
      await tester.runAsync(() async {
        final locked = Completer<void>();
        held = harness.database.writeLock((_) async {
          locked.complete();
          await release.future;
        });
        await locked.future;
      });
      await tester.tap(save);
      await tester.pump();
      expect(pullSaveEnabled(), isFalse, reason: 'the save is waiting');

      // Saving, it closes on back without asking, then fades out for 220ms.
      await tester.binding.handlePopRoute();
      await tester.pump();
      final card = _dayCard(longDay).hitTestable();
      await _shortTicks(tester, until: () => card.evaluate().isNotEmpty);
      await tester.tap(card);
      await tester.pump();

      await tester.runAsync(() async {
        release.complete();
        await held;
      });
      // The closed editor re-enables its Save right after calling back, and
      // only while it is still mounted.
      await _shortTicks(tester, until: pullSaveEnabled);
      expect(pullSaveEnabled(), isTrue,
          reason: 'the save finished while its editor was fading out');
      await settleReal(tester, ticks: 10);
      expect(_dayEditorIds(tester), ['d1']);
      await harness.unmount(tester);
    });

    testWidgets('two back presses queued together ask once', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final first = tester.binding.handlePopRoute();
      final second = tester.binding.handlePopRoute();
      await first;
      await second;
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('a close requested while one is asking is refused',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      final plan = tester.state<PlanScreenState>(find.byType(PlanScreen));
      final first = plan.requestClose();
      final second = plan.requestClose();
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(await second, isFalse);

      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(await first, isTrue);
      expect(find.byType(DayEditor), findsNothing);
      await harness.unmount(tester);
    });


    testWidgets('a predictive back gesture asks before discarding',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openDay(tester);
      await _expandBenchPress(tester);
      await _tapVisible(tester, _workingSetsInc);

      await _predictiveBack(tester);
      expect(_discardTitle, findsOneWidget);
      expect(find.byType(DayEditor), findsOneWidget);
      await harness.unmount(tester);
    });
  });

  group('exercise editor', () {
    testWidgets('the header chevron closes it untouched and asks once edited',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);
      // The Back muscle chip carries the same label further down the tree.
      final chevron = find.bySemanticsLabel(_l.commonBack).first;

      await tester.tap(chevron);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);

      await _openExercise(tester);
      await _tapVisible(tester, _startWeightInc);
      await tester.tap(chevron);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      expect(find.text(_l.planDiscardExerciseMessage), findsOneWidget);
      await tester.tap(find.text(_l.commonKeepEditing));
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsNothing);

      // A screen reader's activation goes through the same check.
      tester.semantics.tap(find.semantics.byLabel(_l.commonBack).first);
      await settleReal(tester, ticks: 10);
      expect(_discardTitle, findsOneWidget);
      await tester.tap(find.text(_l.commonDiscard));
      await settleReal(tester, ticks: 10);
      expect(find.byType(ExerciseEditor), findsNothing);
      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('a start weight stepped up and back down in lb does not ask',
        (tester) async {
      await harness.open(tester, prefs: {'unit': 'lb'});
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);
      await _tapVisible(tester, _startWeightInc);
      await _tapVisible(tester, _startWeightDec);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('switching to lb behind an untouched editor does not ask',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 412);
      await _openPlan(tester, harness);
      await _openExercise(tester);

      await openTab(tester, WIcons.home);
      harness.units.setUnit(Unit.lb);
      await settleReal(tester, ticks: 5);
      await openTab(tester, WIcons.plan);

      await _back(tester);
      expect(_discardTitle, findsNothing);
      expect(find.byType(ExerciseEditor), findsNothing);
      await harness.unmount(tester);
    });
  });

  testWidgets('back on Today with unsaved Plan edits asks before exiting',
      (tester) async {
    final pops = <MethodCall>[];
    // The channel also carries haptics and SystemChrome calls.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') pops.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await harness.open(tester);
    setPhone(tester, width: 412);
    await _openPlan(tester, harness);
    await _openDay(tester);
    await _expandBenchPress(tester);
    await _tapVisible(tester, _workingSetsInc);
    await openTab(tester, WIcons.home);

    await _back(tester);
    expect(_discardTitle, findsOneWidget);
    // The shell switched to Plan, so the editor is on screen again.
    expect(find.byType(DayEditor), findsOneWidget);
    expect(pops, isEmpty);

    await tester.tap(find.text(_l.commonKeepEditing));
    await settleReal(tester, ticks: 10);
    expect(_workingSetsShows('4'), findsOneWidget);
    expect(pops, isEmpty);

    await openTab(tester, WIcons.home);
    await _back(tester);
    await tester.tap(find.text(_l.commonDiscard));
    await settleReal(tester, ticks: 10);
    expect(pops, hasLength(1));
    await harness.unmount(tester);
  });
}
