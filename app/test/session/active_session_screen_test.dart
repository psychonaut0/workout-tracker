import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/active_session_screen.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/session/set_line.dart';
import 'package:workout_tracker/settings/settings_service.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/widgets/ruler_picker.dart';

/// Mounts [ActiveSessionScreen] with only the providers it reads. It never
/// touches `db` unless a test taps "Add exercise" or finishes the workout,
/// which none of these do — so this stays clear of the "screens that watch
/// PowerSync can't be widget-tested" trap (see app/AGENTS.md).
Widget _harness(ActiveSessionController controller, {SettingsService? settings}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ActiveSessionController>.value(value: controller),
      ChangeNotifierProvider<SessionManager>(create: (_) => SessionManager()),
      ChangeNotifierProvider<SettingsService>.value(value: settings ?? SettingsService()),
      ChangeNotifierProvider<UnitService>(create: (_) => UnitService()),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark, accents[0]),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ActiveSessionScreen(),
    ),
  );
}

const _compound = Exercise(
  id: 'squat', name: 'Squat', slug: 'squat', muscleGroup: 'legs',
  compound: true, plateStepKg: 2.5, isTemplate: false,
);

BlockState _block({required List<SetState> warm, required List<SetState> work, Exercise ex = _compound}) =>
    BlockState(
      exercise: ex,
      resolved: ResolvedSlot(exercise: ex, workSets: work.length, warmupSets: warm.length,
          repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 1),
      warmupSets: warm, workingSets: work, expanded: true,
    );

SessionDraft _draftWith(List<BlockState> blocks) => SessionDraft(
    templateId: 't', name: 'Leg day', focus: '', startedAt: DateTime.now(), blocks: blocks);

/// Ends the test by swapping in a widget with no ticker, so the screen's
/// 1-second Timer.periodic actually disposes before the test binding checks
/// for pending timers.
Future<void> _teardown(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('logging a warm-up starts no rest', (tester) async {
    final controller = ActiveSessionController();
    final warm = SetState(id: 'w1', weightKg: 20, reps: 8, rir: null, isWarmup: true, done: false);
    final work = SetState(id: 's1', weightKg: 100, reps: 8, rir: 1, isWarmup: false, done: false);
    controller.seedForTest(_draftWith([_block(warm: [warm], work: [work])]));

    await tester.pumpWidget(_harness(controller));
    await tester.pump();

    await tester.tap(find.byKey(const Key('log-set-bar')));
    await tester.pump();

    expect(controller.resting, isFalse);
    expect(warm.done, isTrue);

    await _teardown(tester);
  });

  testWidgets(
      'logging a working set on a compound exercise with no per-exercise '
      'rest override starts rest at the settings compound default',
      (tester) async {
    final controller = ActiveSessionController();
    final work = SetState(id: 's1', weightKg: 100, reps: 8, rir: 1, isWarmup: false, done: false);
    controller.seedForTest(_draftWith([_block(warm: [], work: [work])]));
    final settings = SettingsService();

    await tester.pumpWidget(_harness(controller, settings: settings));
    await tester.pump();

    await tester.tap(find.byKey(const Key('log-set-bar')));
    await tester.pump();

    expect(work.done, isTrue);
    expect(controller.resting, isTrue);
    expect(controller.restTotal, settings.restCompoundSeconds);
    expect(settings.restCompoundSeconds, 180);

    await _teardown(tester);
  });

  testWidgets('swipe-remove a pending set, then Undo restores it at its index',
      (tester) async {
    final controller = ActiveSessionController();
    final s0 = SetState(id: 's0', weightKg: 100, reps: 8, rir: 1, isWarmup: false, done: false);
    final s1 = SetState(id: 's1', weightKg: 100, reps: 8, rir: 1, isWarmup: false, done: false);
    final block = _block(warm: [], work: [s0, s1]);
    controller.seedForTest(_draftWith([block]));

    await tester.pumpWidget(_harness(controller));
    await tester.pump();
    // Let the blocks' one-shot Reveal entrance animations finish.
    await tester.pump(const Duration(milliseconds: 400));

    expect(block.workingSets, [s0, s1]);

    // Swipe s0 (index 0) away.
    await tester.drag(find.byKey(const Key('dismiss-s0')), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(block.workingSets, [s1]);

    // A real tap on the SnackBarAction is geometrically unreliable in a
    // narrow test surface (the bar sits right above the pinned LogSetBar and
    // widget-test hit-testing on SnackBars is a known-flaky area) — invoke
    // its callback directly; this still exercises exactly what the screen
    // wires up (`_removeSet`'s `SnackBarAction.onPressed`).
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    action.onPressed();
    await tester.pump();

    expect(block.workingSets, [s0, s1]);

    await _teardown(tester);
  });

  testWidgets(
      'a ruler change stays on its set when another set is tapped', (tester) async {
    final controller = ActiveSessionController();
    final s0 = SetState(id: 's0', weightKg: 100, reps: 8, rir: 1, isWarmup: false, done: false);
    final s1 = SetState(id: 's1', weightKg: 120, reps: 8, rir: 1, isWarmup: false, done: false);
    final block = _block(warm: [], work: [s0, s1]);
    controller.seedForTest(_draftWith([block]));

    await tester.pumpWidget(_harness(controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.liveSet!.set.id, 's0');

    await tester.timedDrag(find.byKey(const Key('live-weight')),
        const Offset(-2 * RulerPicker.defaultItemExtent, 0), const Duration(seconds: 1));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // let the tape snap
    }
    expect(s0.weightKg, 105);

    await tester.tap(find.byType(SetLine));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(s0.weightKg, 105);
    expect(s1.weightKg, 120);
    expect(controller.liveSet!.set.id, 's1');

    await _teardown(tester);
  });
}
