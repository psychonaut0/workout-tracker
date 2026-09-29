// Mounts real screens over a real PowerSync database in widget tests.
//
// Screens that own watch-streams, or fire a one-shot read in initState, hang
// under fake time alone. Here the database opens inside `tester.runAsync`,
// frames advance with real-async ticks ([settleReal], never pumpAndSettle),
// and every test ends with [ScreenHarness.unmount] so the watch-throttle
// timers and subscriptions are released before [ScreenHarness.close].
//
// SyncStatus's constructor is @internal but is the only way to build the
// idle status the stub [SyncHealth] starts from.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase, SyncStatus;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/identity/identity_service.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/settings/settings_service.dart';
import 'package:workout_tracker/shell/w_tab_bar.dart';
import 'package:workout_tracker/sync/db.dart';
import 'package:workout_tracker/sync/schema.dart';
import 'package:workout_tracker/sync/sync_health.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/util/dates.dart';

import 'app_fonts.dart';
import 'layout_expect.dart';

// ── Long names: the seeds that broke the layout in the critique ─────────────

const longExercise =
    'Single-Arm Cable Lateral Raise with Wrist Strap (Behind Back)';
const longExercise2 = 'Kurzhantel-Schrägbankdrücken mit neutralem Griff und Pause';
const longDay = 'Oberkörper Schwerpunkt Brust & Schultern';
const longFocus = 'Brust · Schultern · Trizeps · Vorderer Delta';
const unscheduledLongDay = 'Beine und Gesäß mit Schwerpunkt Hinterseite';

// ── Conditions the layout must hold at ──────────────────────────────────────

typedef LayoutCondition = ({double width, double textScale, Locale locale});

final List<LayoutCondition> layoutConditions = [
  for (final width in const [320.0, 412.0])
    for (final textScale in const [1.0, 2.0])
      for (final code in const ['en', 'de', 'it'])
        (width: width, textScale: textScale, locale: Locale(code)),
];

String describeCondition(LayoutCondition c) =>
    '${c.width.round()}dp ${c.textScale}x ${c.locale.languageCode}';

// ── Harness ─────────────────────────────────────────────────────────────────

class ScreenHarness {
  Directory? _dir;
  PowerSyncDatabase? _db;
  late UnitService units;
  late SettingsService settings;
  late IdentityService _identity;
  late SessionManager _manager;
  late SyncHealth _syncHealth;

  PowerSyncDatabase get database => _db!;

  /// Mocks prefs and platform channels, opens and seeds a real database as
  /// the global `db`, loads the unit/settings services and the app's faces.
  Future<void> open(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    Future<void> Function(PowerSyncDatabase db) seed = seedLong,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'identity.current_user_id': 'u1',
      'identity.onboarding_complete': true,
      ...prefs,
    });
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('reps-screen');
      _dir = dir;
      _mockPlatformChannels(dir);
      final d = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
      await d.initialize();
      _db = d;
      dbForTests = d;
      await seed(d);
      units = UnitService();
      settings = SettingsService();
      await units.load();
      await settings.load();
      _identity = IdentityService();
      _manager = SessionManager();
      // Never started: no status subscription or poll timer, so it never
      // reports at risk and leaves nothing pending when the test ends.
      _syncHealth = SyncHealth(
        status: const Stream.empty(),
        initial: const SyncStatus(),
        pendingChanges: () async => 0,
        signedIn: () => false,
        syncEnabled: () => false,
      );
      await initializeDateFormatting();
      await preloadAppFonts();
    });
  }

  /// The providers and MaterialApp the real app puts above every route.
  Widget wrap(
    Widget home, {
    Locale locale = const Locale('en'),
    List<SingleChildWidget> extra = const [],
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UnitService>.value(value: units),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<IdentityService>.value(value: _identity),
        ChangeNotifierProvider<SessionManager>.value(value: _manager),
        ChangeNotifierProvider<SyncHealth>.value(value: _syncHealth),
        ...extra,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark, accents[0]),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
  }

  /// Ends a test body: disposes the screen's streams and timers for real.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleReal(tester, ticks: 5);
  }

  /// `tearDown(harness.close)`: closes and deletes the test database.
  Future<void> close() async {
    final d = _db;
    final dir = _dir;
    _db = null;
    _dir = null;
    dbForTests = null;
    if (d != null) await d.close();
    if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
  }

  void _mockPlatformChannels(Directory dir) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => <String, dynamic>{
              'appName': 'Reps',
              'packageName': 'io.github.psychonaut0.reps',
              'version': '0.16.0',
              'buildNumber': '34',
              'buildSignature': '',
            });
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null);
  }
}

// ── Tester helpers ──────────────────────────────────────────────────────────

/// A phone of [width]×[height] logical px at 2× density with status/nav
/// insets, at the given system text scale.
void setPhone(WidgetTester tester,
    {required double width, double height = 915, double textScale = 1.0}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.padding = const FakeViewPadding(top: 64, bottom: 32);
  tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 32);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Pumps real-async ticks so isolate-backed database work lands.
Future<void> settleReal(WidgetTester tester, {int ticks = 30}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Taps the bottom-nav tab showing [icon] (locale-independent).
Future<void> openTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.descendant(
      of: find.byType(WTabBar), matching: find.byIcon(icon)));
  await settleReal(tester, ticks: 10);
}

Finder verticalScrollableIn(Finder within) => find
    .descendant(
      of: within,
      matching: find.byWidgetPredicate((w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.vertical),
    )
    .first;

/// Scrolls the vertical list under [within] until [target] is built, then
/// brings it on screen.
Future<void> scrollIntoView(
    WidgetTester tester, Finder within, Finder target) async {
  final position =
      tester.state<ScrollableState>(verticalScrollableIn(within)).position;
  for (var i = 0;
      i < 40 &&
          target.evaluate().isEmpty &&
          position.pixels < position.maxScrollExtent;
      i++) {
    position.jumpTo(math.min(position.pixels + position.viewportDimension / 2,
        position.maxScrollExtent));
    await settleReal(tester, ticks: 2);
  }
  expect(target, findsWidgets, reason: 'scrolled $within without finding it');
  await tester.ensureVisible(target.first);
  await settleReal(tester, ticks: 2);
}

/// No overflow or build exception so far, and no word split on screen.
void expectLayoutHolds(WidgetTester tester, String where) {
  final error = tester.takeException();
  if (error != null) fail('$where: ${error.toString().split('\n').first}');
  expectNoSplitWords(tester, where: where);
}

/// [expectLayoutHolds] at the top of the vertical list under [within] and at
/// every 80%-of-a-screen step to its end; leaves the list back at the top.
Future<void> expectLayoutHoldsWhileScrolling(
    WidgetTester tester, Finder within, String where) async {
  expectLayoutHolds(tester, where);
  final scrollable = verticalScrollableIn(within);
  if (scrollable.evaluate().isEmpty) return;
  final position = tester.state<ScrollableState>(scrollable).position;
  for (var step = 1;
      step <= 20 && position.pixels < position.maxScrollExtent;
      step++) {
    position.jumpTo(math.min(
        position.pixels + position.viewportDimension * 0.8,
        position.maxScrollExtent));
    await settleReal(tester, ticks: 3);
    expectLayoutHolds(tester, '$where, scrolled $step');
  }
  position.jumpTo(0);
  await settleReal(tester, ticks: 2);
}

// ── Seeds ───────────────────────────────────────────────────────────────────

Future<void> seedExercise(PowerSyncDatabase d, String id, String name,
    {String muscle = 'chest', bool compound = true}) {
  return d.execute(
    'INSERT INTO exercises (id, slug, name, muscle_group, equip, compound, '
    'base_weight_kg, plate_step_kg, default_rep_low, default_rep_high, '
    'default_warmup_sets, default_working_sets, default_rir_low, '
    'default_rir_high, created_by, is_template, created_at) '
    "VALUES (?, ?, ?, ?, 'barbell', ?, '20.00', '2.50', 6, 10, 1, 3, 1, 2, 'u1', 0, ?)",
    [id, '$id-slug', name, muscle, compound ? 1 : 0,
      DateTime.now().toUtc().toIso8601String()],
  );
}

Future<void> seedDay(PowerSyncDatabase d, String id, String name,
    {required int position,
    String focus = '',
    List<String> exerciseIds = const [],
    int? weekday}) async {
  await d.execute(
    'INSERT INTO day_templates (id, slug, name, notes, position, is_template, '
    "created_by, created_at, focus, scheduled_weekday) VALUES (?, ?, ?, '', ?, 0, 'u1', ?, ?, ?)",
    [id, '$id-slug', name, position,
      DateTime.now().toUtc().toIso8601String(), focus, weekday],
  );
  for (var p = 0; p < exerciseIds.length; p++) {
    await d.execute(
      'INSERT INTO day_template_items (id, day_template_id, exercise_id, position, '
      'target_warmup_sets, target_working_sets, target_rep_low, target_rep_high, '
      'target_rir_low, target_rir_high, is_template, created_by, created_at) '
      "VALUES (?, ?, ?, ?, 1, 3, 6, 10, 1, 2, 0, 'u1', ?)",
      ['$id-i$p', id, exerciseIds[p], p,
        DateTime.now().toUtc().toIso8601String()],
    );
  }
}

/// One finished session; [sets] = (exerciseId, kg, reps, rir, warmup).
Future<void> seedSession(PowerSyncDatabase d, String id,
    {required DateTime date,
    required String label,
    String? dayId,
    int durationMin = 62,
    required List<(String, double, int, int?, bool)> sets}) async {
  await d.execute(
    'INSERT INTO sessions (id, user_id, date, split_label, notes, day_template_id, '
    "created_at, duration_min) VALUES (?, 'u1', ?, ?, '', ?, ?, ?)",
    [id, isoDate(date), label, dayId, date.toUtc().toIso8601String(),
      durationMin],
  );
  final top = <String, int>{};
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];
    if (s.$5) continue;
    final cur = top[s.$1];
    if (cur == null || sets[cur].$2 < s.$2) top[s.$1] = i;
  }
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];
    await d.execute(
      'INSERT INTO sets (id, session_id, exercise_id, user_id, set_number, weight_kg, '
      "reps, rir, is_warmup, is_top_set, is_pr, created_at, updated_at) VALUES (?, ?, ?, 'u1', ?, ?, ?, ?, ?, ?, 0, ?, ?)",
      ['$id-s$i', id, s.$1, i + 1, s.$2.toStringAsFixed(2), s.$3, s.$4,
        s.$5 ? 1 : 0, top[s.$1] == i ? 1 : 0,
        date.toUtc().toIso8601String(), date.toUtc().toIso8601String()],
    );
  }
}

Future<void> seedBodyweight(PowerSyncDatabase d, DateTime date, double kg) =>
    d.execute(
      "INSERT INTO bodyweight_logs (id, user_id, date, weight_kg, created_at) VALUES (?, 'u1', ?, ?, ?)",
      ['bw-${isoDate(date)}', isoDate(date), kg.toStringAsFixed(2),
        date.toUtc().toIso8601String()],
    );

/// Long exercise and day names, four sessions (one with a PR) and twelve
/// bodyweight entries over the last weeks.
Future<void> seedLong(PowerSyncDatabase d) async {
  await seedExercise(d, 'ex1', longExercise, muscle: 'shoulders', compound: false);
  await seedExercise(d, 'ex2', longExercise2, muscle: 'chest');
  await seedExercise(d, 'ex3', 'Bench Press', muscle: 'chest');
  await seedExercise(d, 'ex4', 'Brand New Movement', muscle: 'back');
  await seedDay(d, 'd1', longDay,
      position: 0, focus: longFocus, exerciseIds: ['ex1', 'ex2', 'ex3', 'ex4']);
  await seedDay(d, 'd2', 'Pull', position: 1, focus: 'Back', exerciseIds: ['ex3']);
  await seedDay(d, 'd3', unscheduledLongDay, position: 2, exerciseIds: ['ex2']);
  final now = DateTime.now();
  for (var w = 0; w < 4; w++) {
    await seedSession(d, 's$w',
        date: now.subtract(Duration(days: 2 + w * 3)),
        label: w.isEven ? longDay : 'Pull',
        dayId: w.isEven ? 'd1' : 'd2',
        durationMin: 71,
        sets: [
          ('ex1', 12.5, 12, null, true),
          ('ex1', 17.5 + w, 10, 1, false),
          ('ex1', 17.5 + w, 9, 1, false),
          ('ex2', 42.5 - w, 8, 2, false),
          ('ex2', 42.5 - w, 7, 1, false),
          ('ex3', 102.5 - w * 2.5, 5, 0, false),
        ]);
  }
  await d.execute(
      "UPDATE sets SET is_pr = 1 WHERE session_id = 's0' AND is_top_set = 1");
  for (var i = 0; i < 12; i++) {
    await seedBodyweight(d, now.subtract(Duration(days: i * 2)), 82.4 - i * 0.3);
  }
}

/// A live workout with the long names: a started block, a collapsed one and
/// a brand-new exercise.
SessionDraft longDraft() {
  Exercise ex(String id, String name, {bool compound = true}) => Exercise(
        id: id, name: name, slug: id, muscleGroup: 'chest',
        compound: compound, plateStepKg: 2.5, isTemplate: false,
      );
  SetState setOf(String id, double kg, int reps,
          {bool warm = false, bool done = false}) =>
      SetState(id: id, weightKg: kg, reps: reps, rir: warm ? null : 1,
          isWarmup: warm, done: done);
  BlockState block(Exercise e,
          {required List<SetState> warm,
          required List<SetState> work,
          bool expanded = true}) =>
      BlockState(
        exercise: e,
        resolved: ResolvedSlot(
            exercise: e, workSets: work.length, warmupSets: warm.length,
            repLow: 8, repHigh: 12, rirLow: 1, rirHigh: 2),
        warmupSets: warm,
        workingSets: work,
        expanded: expanded,
        lastTop: (
          weight: 17.5,
          reps: 10,
          date: isoDate(DateTime.now().subtract(const Duration(days: 2))),
        ),
        bestKg: 17.5,
      );
  return SessionDraft(
    templateId: 'd1',
    name: longDay,
    focus: longFocus,
    startedAt: DateTime.now().subtract(const Duration(minutes: 23)),
    blocks: [
      block(ex('ex1', longExercise, compound: false),
          warm: [setOf('w1', 7.5, 12, warm: true, done: true)],
          work: [setOf('l1', 17.5, 10, done: true), setOf('l2', 17.5, 9),
            setOf('l3', 17.5, 8)]),
      block(ex('ex2', longExercise2),
          warm: [], work: [setOf('k1', 42.5, 8), setOf('k2', 42.5, 8)],
          expanded: false),
      block(ex('ex4', 'Brand New Movement'),
          warm: [], work: [setOf('n1', 20, 10), setOf('n2', 20, 10)]),
    ],
  );
}
