# Watch-Stream Re-Listen Crash Class Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the "infinite gray box" crash class — make every repository watch-stream safe to re-listen, fix a deterministic crash in Progress reachable from Home, stop stream errors from silently freezing Home, and replace Flutter's featureless release `ErrorWidget` with a readable, copyable card.

**Architecture:** One 12-line primitive (`reListenable`) wraps each repository `watchX()` so a second `listen()` opens a fresh query instead of throwing, with the last value replayed to a late listener. Applied at the repository layer, no screen can reintroduce the bug. Everything else is targeted null-safety and error-handling around that.

**Tech Stack:** Flutter 3.44.0 (pinned via fvm), Dart, PowerSync (`powersync` 2.2.0 over `sqlite_async` 0.14.2), `provider` for app-wide state, `flutter_test` only (no mocking package — all fakes are hand-written).

**Spec:** `docs/superpowers/specs/2026-07-28-watch-stream-relisten-crash-design.md`

## Global Constraints

- **Never run `flutter` directly.** Flutter is pinned via fvm (`app/.fvmrc`). Every command goes through the Makefile from the **repo root**: `make -C app analyze`, `make -C app test`, `make -C app test TEST=test/path/file.dart`, `make -C app get`. Never `cd`.
- `make -C app analyze` must end at **"No issues found"**. Deprecation warnings count as failures — do not introduce a deprecated API.
- `make -C app test` must be fully green before every commit.
- Commit style: **Conventional Commits, standard types, subject line only, no body.**
- **Never reference plan or spec numbers in code or comments.** Use descriptive language ("the sliver-recycle re-listen crash"), never "task 3" or "the plan".
- Parse numbers from TEXT columns with **`double.tryParse`, never `double.parse`** — `double.parse('')` throws and one bad row blanks an entire list stream. This caused the worst data-visibility bug in the project's history.
- `weight_kg` columns are TEXT; booleans are INTEGER 0/1; `sessions.date` is date-only `YYYY-MM-DD`.
- Confirm dialogs always use `showWConfirm`/`showWDialog` from `widgets/w_dialog.dart`, never `AlertDialog`.
- Widget tests that need `context.tokens` use `MaterialApp(theme: buildTheme(Brightness.dark, accents[0]))`; anything calling `AppLocalizations.of(context)` must use `wrapL10n` from `test/support/l10n_harness.dart`.
- No new user-visible strings in this increment, so **no ARB edits** — `test/l10n/arb_parity_test.dart` must stay green.

---

### Task 1: The `reListenable` primitive

**Files:**
- Create: `app/lib/data/re_listenable.dart`
- Test: `app/test/data/re_listenable_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Stream<T> reListenable<T>(Stream<T> Function() create)` — used by every repository in Task 2.

- [ ] **Step 1: Write the failing tests**

Create `app/test/data/re_listenable_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/re_listenable.dart';

void main() {
  // A single-subscription source, which is what PowerSync's db.watch() returns.
  // Do NOT use Stream.fromIterable here: as of Dart 3.12 it is implemented via
  // Stream.multi (dart-sdk/lib/async/stream.dart:354) and CAN be listened to
  // more than once, so it would silently make these tests prove nothing.
  Stream<int> singleSub(int value) {
    final ctrl = StreamController<int>();
    ctrl.add(value);
    return ctrl.stream;
  }

  test('a naked single-subscription stream throws on re-listen (control)',
      () async {
    final naked = singleSub(1);
    expect(await naked.first, 1);
    expect(() => naked.listen((_) {}), throwsStateError);
  });

  test('reListenable can be listened to again after a cancel', () async {
    var creations = 0;
    final s = reListenable<int>(() {
      creations++;
      return singleSub(creations);
    });

    expect(await s.first, 1);
    expect(await s.first, 1); // replayed last value, no throw
    expect(creations, 2); // upstream recreated for the second listener
  });

  test('reListenable replays the last value to a late listener', () async {
    // A BROADCAST controller here on purpose: the factory must be able to
    // return a usable source on every call, and a single-subscription
    // controller's stream can only ever be listened to once, factory or not.
    final ctrl = StreamController<int>.broadcast();
    final s = reListenable<int>(() => ctrl.stream);

    final seen = <int>[];
    final sub = s.listen(seen.add);
    ctrl.add(7);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // A brand-new listener sees 7 immediately, before any new upstream event.
    expect(await s.first, 7);
    await ctrl.close();
  });

  test('reListenable forwards errors', () async {
    final s = reListenable<int>(
        () => Stream<int>.error(StateError('boom')));
    expect(s.first, throwsStateError);
  });

  test('reListenable cancels the upstream when the last listener leaves',
      () async {
    var cancels = 0;
    final s = reListenable<int>(() {
      final ctrl = StreamController<int>(onCancel: () => cancels++);
      return ctrl.stream;
    });

    final sub = s.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(cancels, 1);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make -C app test TEST=test/data/re_listenable_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'workout_tracker'`-style import failure, or "reListenable isn't defined", because the source file does not exist yet. The control test (first one) is the only one that could pass.

- [ ] **Step 3: Write the implementation**

Create `app/lib/data/re_listenable.dart`:

```dart
import 'dart:async';

/// Wraps a single-subscription stream factory in a stream that can be listened
/// to more than once, replaying the most recent value to each new listener.
///
/// `PowerSyncDatabase.watch()` returns a SINGLE-SUBSCRIPTION stream, and
/// cancelling does not reset it — a second `listen()` throws
/// "Bad state: Stream has already been listened to". That is fatal for a
/// StreamBuilder living inside a lazy ListView: the sliver garbage-collects the
/// child when it scrolls out of the cache window (disposing the subscription)
/// and re-creates it on the way back, which re-listens. In a release build that
/// uncaught error renders as Flutter's featureless gray ErrorWidget.
///
/// [Stream.multi] runs its callback once PER listener, so each listener gets a
/// freshly created upstream. The captured [last] value is replayed immediately
/// so a recycled section repaints with data instead of flashing its loading
/// state, and the upstream is cancelled when a listener leaves so a recycled
/// child does not leak a SQL watch.
///
/// The `T?` sentinel assumes a non-nullable element type — true for every
/// current repository stream (Lists, ints, records). For a nullable element
/// type, track a separate `hasLast` flag instead.
Stream<T> reListenable<T>(Stream<T> Function() create) {
  T? last;
  return Stream.multi((controller) {
    final cached = last;
    if (cached != null) controller.add(cached);
    final sub = create().listen(
      (v) {
        last = v;
        controller.add(v);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make -C app test TEST=test/data/re_listenable_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Analyze**

Run: `make -C app analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/data/re_listenable.dart app/test/data/re_listenable_test.dart
git commit -m "feat(app): re-listenable watch-stream wrapper with last-value replay"
```

---

### Task 2: Apply `reListenable` to every repository

**Files:**
- Modify: `app/lib/data/stats_repository.dart` (5 watch methods)
- Modify: `app/lib/data/exercise_repository.dart:131` (`watchCatalog`)
- Modify: `app/lib/data/bodyweight_repository.dart:35` (`watchSeriesAsc`)
- Modify: `app/lib/data/muscle_target_repository.dart:58` (`watchTargets`)
- Modify: `app/lib/data/session_repository.dart:140,151` (`watchSessionStats`, `watchRecentSessions`)
- Modify: `app/lib/data/day_template_repository.dart:268` (`watchDays`)
- Modify: `app/lib/data/progress_repository.dart:18` (`watchSeriesFor`)
- Test: `app/test/data/repo_relisten_integration_test.dart`

**Interfaces:**
- Consumes: `reListenable<T>(Stream<T> Function() create)` from Task 1.
- Produces: every `watchX()` returns a re-listenable stream. No signature changes — callers are unaffected.

- [ ] **Step 1: Write the failing test**

This uses a real `PowerSyncDatabase`, following the established pattern in
`app/test/data/offline_create_integration_test.dart`. Create
`app/test/data/repo_relisten_integration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/day_template_repository.dart';
import 'package:workout_tracker/data/exercise_repository.dart';
import 'package:workout_tracker/sync/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-relisten');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('watchCatalog can be listened to twice', () async {
    await db.execute(
      "INSERT INTO exercises (id, name, slug, muscle_group, is_template) "
      "VALUES ('e1', 'Squat', 'squat', 'quads', 0)",
    );
    final stream = ExerciseRepository(db).watchCatalog();

    final first = await stream.first; // listens, then cancels
    final second = await stream.first; // re-listens — this threw before

    expect(first.length, 1);
    expect(second.length, 1);
  });

  test('watchDays can be listened to twice', () async {
    final stream = DayTemplateRepository(db).watchDays();
    await stream.first;
    await stream.first;
  });
}
```

Note on the INSERT: `exercises` columns must match `app/lib/sync/schema.dart`. Read that file and adjust the column list if it differs — the point of the test is the double `.first`, not the row shape. `await stream.first` subscribes and then cancels, which is exactly the recycle sequence.

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C app test TEST=test/data/repo_relisten_integration_test.dart`
Expected: FAIL on the second `await stream.first` with `Bad state: Stream has already been listened to.`

- [ ] **Step 3: Wrap each watch method**

The pattern, using `stats_repository.dart:19` as the worked example:

```dart
  /// Live count of working sets logged since [weekStart] (Monday of current week).
  Stream<int> watchSetsThisWeek({required DateTime weekStart}) {
    return reListenable(() => db
        .watch(
          'SELECT COUNT(*) AS n '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'WHERE s.is_warmup = 0 AND se.date >= ?',
          parameters: [isoDate(weekStart)],
        )
        .map((rs) => rs.first['n'] as int? ?? 0));
  }
```

Add `import 're_listenable.dart';` to each repository file. Apply the identical
transformation — wrap the whole existing expression in `reListenable(() => ...)`
— to all twelve watch methods:

- `stats_repository.dart`: `watchSetsThisWeek`, `watchDistinctMusclesThisWeek`, `watchPrsThisWeek`, `watchRecentPrs`, `watchWeeklyVolumeByMuscle`
- `exercise_repository.dart`: `watchCatalog`
- `bodyweight_repository.dart`: `watchSeriesAsc`
- `muscle_target_repository.dart`: `watchTargets`
- `session_repository.dart`: `watchSessionStats`, `watchRecentSessions`
- `day_template_repository.dart`: `watchDays`
- `progress_repository.dart`: `watchSeriesFor`

For the two expression-bodied methods (`session_repository.dart:140`,
`progress_repository.dart:18`, both `=> db.watch(...)`), convert to:

```dart
  Stream<List<HistorySessionRow>> watchSessionStats() =>
      reListenable(() => db.watch(
            // ... existing SQL and .map untouched
          ));
```

Do **not** change any SQL, any `.map` mapper, any parameter, or any return type.

Leave `db.statusStream` (used in `profile_screen.dart`) alone — PowerSync already
backs it with a broadcast controller and it is paired with `initialData`.

- [ ] **Step 4: Run the new test to verify it passes**

Run: `make -C app test TEST=test/data/repo_relisten_integration_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Run the full suite and analyze**

Run: `make -C app test`
Expected: all green. The op-builder and repository tests assert SQL strings and mapper output, neither of which changed.

Run: `make -C app analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/data app/test/data/repo_relisten_integration_test.dart
git commit -m "fix(app): every repository watch-stream is re-listenable"
```

---

### Task 3: Lazy-list recycle regression test

Proves the shipped bug is actually gone at the widget level, which is where it manifested. No production code changes.

**Files:**
- Test: `app/test/widgets/sliver_recycle_relisten_test.dart`

**Interfaces:**
- Consumes: `reListenable` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Write the test**

Create `app/test/widgets/sliver_recycle_relisten_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/re_listenable.dart';

void main() {
  // A single-subscription source, matching what PowerSync's db.watch() returns.
  // Stream.fromIterable is NOT usable here — as of Dart 3.12 it is built on
  // Stream.multi and can be listened to repeatedly, which would make the
  // control test below pass for the wrong reason.
  Stream<int> singleSub(int value) {
    final ctrl = StreamController<int>();
    ctrl.add(value);
    return ctrl.stream;
  }

  // A lazy ListView child that scrolls far enough out of view is UNMOUNTED
  // (disposing its StreamBuilder subscription) and re-created on the way back,
  // which re-listens to the same stream instance. cacheExtent: 0 makes the
  // recycle deterministic instead of viewport-height dependent.
  Widget host(Stream<int> stream, ScrollController ctrl) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ListView.builder(
              controller: ctrl,
              // `cacheExtent: 0` is deprecated on the pinned SDK
              // (scroll_view.dart:118) and analyze treats deprecations as
              // failures, so use the sanctioned replacement.
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemCount: 12,
              itemExtent: 200,
              itemBuilder: (_, i) => i == 0
                  ? StreamBuilder<int>(
                      stream: stream,
                      builder: (_, snap) => Text('v=${snap.data ?? 0}'),
                    )
                  : Text('row $i'),
            ),
          ),
        ),
      );

  testWidgets('a naked cached stream crashes when its child recycles (control)',
      (tester) async {
    final ctrl = ScrollController();
    final naked = singleSub(1);

    await tester.pumpWidget(host(naked, ctrl));
    await tester.pumpAndSettle();

    ctrl.jumpTo(1200); // item 0 well outside the (zero) cache window
    await tester.pumpAndSettle();
    ctrl.jumpTo(0); // item 0 re-created → second listen()
    await tester.pumpAndSettle();

    expect(tester.takeException(), isStateError);
  });

  testWidgets('a reListenable cached stream survives its child recycling',
      (tester) async {
    final ctrl = ScrollController();
    final stream = reListenable<int>(() => singleSub(42));

    await tester.pumpWidget(host(stream, ctrl));
    await tester.pumpAndSettle();
    expect(find.text('v=42'), findsOneWidget);

    ctrl.jumpTo(1200);
    await tester.pumpAndSettle();
    ctrl.jumpTo(0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The replayed last value means no loading flash on the way back.
    expect(find.text('v=42'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `make -C app test TEST=test/widgets/sliver_recycle_relisten_test.dart`
Expected: PASS, 2 tests. If the control test does NOT throw, the recycle is not
happening — increase `itemCount`/`jumpTo` distance until it does, because a
control test that never reproduces the bug proves nothing.

- [ ] **Step 3: Commit**

```bash
git add app/test/widgets/sliver_recycle_relisten_test.dart
git commit -m "test(app): pin sliver-recycle re-listen behaviour with a negative control"
```

---

### Task 4: Test-only database seam

`today_screen` and `progress_screen` build their repositories from the global
`db` getter in `initState`, which throws `StateError` unless `openDatabase()` has
run. Widget tests for those screens need a way to install a temp database.

**Files:**
- Modify: `app/lib/sync/db.dart:11-19`

**Interfaces:**
- Consumes: nothing.
- Produces: `set dbForTests(PowerSyncDatabase? d)` — used by Tasks 5, 6 and 7.

- [ ] **Step 1: Add the seam**

In `app/lib/sync/db.dart`, add the annotation import and the setter directly
below the existing `db` getter (leave the getter and `openDatabase()` unchanged).

Import it from Flutter, NOT from `package:meta` — `foundation.dart` re-exports
`visibleForTesting` and `flutter` is already a direct dependency, so this needs
no new pubspec entry and adds no supply-chain surface:

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

```dart
/// Test-only seam: install a database instance (or null to reset between
/// tests). Production code always goes through [openDatabase].
@visibleForTesting
set dbForTests(PowerSyncDatabase? d) => _db = d;
```

- [ ] **Step 2: Confirm no new dependency is needed**

`app/pubspec.yaml` must NOT gain a `meta` entry. The `depend_on_referenced_packages`
lint (active via `flutter_lints`) would fire on a bare `package:meta/meta.dart`
import, which is exactly why the import above comes from
`package:flutter/foundation.dart` instead. If you find yourself adding a
dependency to satisfy analyze, you have used the wrong import.

- [ ] **Step 3: Analyze**

Run: `make -C app analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add app/lib/sync/db.dart app/pubspec.yaml
git commit -m "test(app): add a test-only seam for installing a temp PowerSync database"
```

---

### Task 5: Fix the Progress crash reachable from Home

`app_shell.dart:112-113` sets `_progressTarget` and switches tabs when a
Recent-PR row on Home is tapped; `app_shell.dart:180-182` builds
`ProgressScreen(key: ValueKey(_progressTarget), ...)`. The changed key remounts
the screen, so its root `StreamBuilder` (`progress_screen.dart:72-73`) restarts
and its first build has `snap.data == null` → `catalog = []`. With `_target`
non-null and not `bwId`, the early returns at `:86` and `:90` are skipped and
`:95-98` calls `catalog.firstWhere(..., orElse: () => catalog.first)` on the
empty list → `Bad state: No element`, every time.

**Files:**
- Modify: `app/lib/ui/progress_screen.dart:74-98`
- Test: `app/test/ui/progress_screen_target_test.dart`

**Interfaces:**
- Consumes: `dbForTests` from Task 4.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Create `app/test/ui/progress_screen_target_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/db.dart';
import 'package:workout_tracker/sync/schema.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-progress');
    database = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await database.initialize();
    dbForTests = database;
  });

  tearDown(() async {
    dbForTests = null;
    await database.close();
    await dir.delete(recursive: true);
  });

  testWidgets('a non-null initialTarget does not crash on the first frame',
      (tester) async {
    // Reproduces tapping a Recent-PR row on Home: the screen mounts with a
    // target already set, before the catalog stream has emitted anything.
    await tester.pumpWidget(wrapL10n(
      ChangeNotifierProvider<UnitService>(
        create: (_) => UnitService(),
        child: const ProgressScreen(initialTarget: 'some-exercise-id'),
      ),
    ));

    // The very first frame is the one that threw "Bad state: No element".
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C app test TEST=test/ui/progress_screen_target_test.dart`
Expected: FAIL with `Bad state: No element`.

- [ ] **Step 3: Make the lookup null-safe**

In `app/lib/ui/progress_screen.dart`, replace lines 74-98 (the builder opening
through the `firstWhere`) so the empty-catalog case is handled explicitly.
Keep the existing `bwId` and `_EmptyState` branches exactly as they are:

```dart
      builder: (context, snap) {
        final catalog = snap.data ?? const <Exercise>[];

        // Determine the effective target.
        String? target = _target;
        if (target == null && catalog.isNotEmpty) {
          // Default: first exercise that has history; else first alphabetical.
          // Since we can't await inside build, we use the first alphabetical
          // as the default and rely on the stream update for a better pick.
          target = catalog.first.id;
        }

        if (target == bwId) {
          return BodyweightView(onOpenPicker: () => _openPicker(catalog));
        }

        if (target == null) {
          return _EmptyState(onOpenPicker: () => _openPicker(catalog));
        }

        // The catalog stream's first emission is asynchronous, so a screen
        // mounted with a target already set (tapping a PR row on Home remounts
        // this screen with a new key) renders one frame with an EMPTY catalog.
        // Never index into it — that threw "Bad state: No element" on frame one.
        if (catalog.isEmpty) return const SizedBox.shrink();

        final exId = target;
        Exercise? found;
        for (final e in catalog) {
          if (e.id == exId) {
            found = e;
            break;
          }
        }
        // Target no longer in the catalog (deleted): fall back to the first
        // alphabetical entry, which is safe now that the list is non-empty.
        final ex = found ?? catalog.first;
```

Leave the nested `StreamBuilder` at `:100` and everything below it unchanged —
`exId` and `ex` keep the same names and types.

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test TEST=test/ui/progress_screen_target_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite and analyze**

Run: `make -C app test` then `make -C app analyze`
Expected: all green, "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/ui/progress_screen.dart app/test/ui/progress_screen_target_test.dart
git commit -m "fix(app): Progress no longer indexes an empty catalog on its first frame"
```

---

### Task 6: Stream errors must not freeze Home

`today_screen.dart:140` and `:147` subscribe with `.listen()` and no `onError`.
A row-mapper `TypeError` (a NULL `day_template_items.exercise_id`, a NULL
`day_template_id`) becomes an uncaught async error that kills the subscription
permanently: `_rotationLoaded` stays false and Home renders
`SizedBox(height: 290)` (`:264`) forever with an empty week strip.

**Files:**
- Modify: `app/lib/ui/today_screen.dart:140-154`
- Test: `app/test/ui/today_screen_bad_row_test.dart`

**Interfaces:**
- Consumes: `dbForTests` from Task 4.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Create `app/test/ui/today_screen_bad_row_test.dart`. Mirror the setUp/tearDown
from Task 5's test (temp dir, `PowerSyncDatabase`, `dbForTests`), then:

```dart
  testWidgets('a bad day-template row does not freeze Home', (tester) async {
    // A NULL exercise_id makes watchDays' row mapper throw. Without onError
    // that kills the subscription and Home is stuck on its 290px placeholder.
    await database.execute(
      "INSERT INTO day_templates (id, name, is_template) "
      "VALUES ('d1', 'Lower A', 0)",
    );
    await database.execute(
      "INSERT INTO day_template_items (id, day_template_id, exercise_id, position) "
      "VALUES ('i1', 'd1', NULL, 0)",
    );

    await tester.pumpWidget(wrapL10n(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UnitService>(create: (_) => UnitService()),
          ChangeNotifierProvider<SettingsService>(
              create: (_) => SettingsService()),
          ChangeNotifierProvider<SessionManager>(create: (_) => SessionManager()),
        ],
        child: TodayScreen(
          onStartSession: (_) {},
          onOpenExercise: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The mapper error is handled, not uncaught.
    expect(tester.takeException(), isNull);
  });
```

Read `today_screen.dart:48-74` for `TodayScreen`'s actual constructor parameters
and the providers it reads, and adjust the wrapper to match — the assertion is
what matters, not the exact argument list. Adjust the two INSERT column lists to
match `app/lib/sync/schema.dart`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C app test TEST=test/ui/today_screen_bad_row_test.dart`
Expected: FAIL — an unhandled `TypeError` surfaces through `tester.takeException()`.

- [ ] **Step 3: Add `onError` to both subscriptions**

In `app/lib/ui/today_screen.dart`, replace lines 140-154:

```dart
    // Subscribe to sessions + day templates; recompute the rotation pick when
    // EITHER changes (finishing a workout updates sessions, not days).
    //
    // Both need onError: a single unmappable row (a NULL exercise_id or
    // day_template_id) otherwise becomes an uncaught async error that kills the
    // subscription for good, leaving Home stuck on its placeholder forever.
    // Keep the last good data and let the next emission recover.
    _sessionsSub = _sessions.watchRecentSessions(limit: 100).listen((rows) {
      if (!mounted) return;
      setState(() {
        _recentSessions = rows;
        _recomputeRotation();
      });
    }, onError: (Object e, StackTrace st) {
      debugPrint('today: recent-sessions stream error: $e');
    });
    _daysSub = _days.watchDays().listen((days) {
      if (!mounted) return;
      setState(() {
        _dayList = days;
        _rotationLoaded = true;
        _recomputeRotation();
      });
    }, onError: (Object e, StackTrace st) {
      // Mark the rotation as loaded so the UI shows its real empty state
      // rather than an indefinite placeholder.
      if (!mounted) return;
      setState(() => _rotationLoaded = true);
      debugPrint('today: days stream error: $e');
    });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test TEST=test/ui/today_screen_bad_row_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite and analyze**

Run: `make -C app test` then `make -C app analyze`
Expected: all green, "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/ui/today_screen.dart app/test/ui/today_screen_bad_row_test.dart
git commit -m "fix(app): Home survives an unmappable session or day row"
```

---

### Task 7: Real-PowerSync Home render and scroll

The end-to-end proof. **If the seam from Task 4 plus the wrapper in Task 6's
test is not enough to mount `TodayScreen` — for example a plugin channel that
cannot be faked — stop, write down exactly what blocked it in the commit
message, and move on. Do not silently drop this task, and do not refactor
production code to force it.**

**Files:**
- Test: `app/test/ui/today_screen_scroll_test.dart`

**Interfaces:**
- Consumes: `dbForTests` from Task 4, the provider wrapper worked out in Task 6.
- Produces: nothing.

- [ ] **Step 1: Write the test**

Create `app/test/ui/today_screen_scroll_test.dart` reusing Task 6's setUp,
tearDown and provider wrapper. Seed a realistic database first (several
`day_templates`, `exercises`, `sessions` and `sets` rows, plus one
`bodyweight_logs` row and a few `muscle_targets`) so every section has content
and Home's content is taller than the viewport:

```dart
  testWidgets('Home scrolls end to end in a short viewport without crashing',
      (tester) async {
    // A short viewport is what makes the lazy ListView recycle its
    // StreamBuilder children — the exact condition that produced the gray box
    // on a phone in landscape or at a large font scale.
    tester.view.physicalSize = const Size(1080, 1200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(/* the Task 6 wrapper around TodayScreen */);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Scroll to the bottom and back, twice, so every section is unmounted and
    // re-created at least once.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 2; i++) {
      await tester.fling(list, const Offset(0, -1200), 3000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.fling(list, const Offset(0, 1200), 3000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
```

- [ ] **Step 2: Run it against the fixed code**

Run: `make -C app test TEST=test/ui/today_screen_scroll_test.dart`
Expected: PASS.

- [ ] **Step 3: Prove it would have caught the bug**

Temporarily revert one repository wrapper (e.g. make
`stats_repository.watchWeeklyVolumeByMuscle` return the naked stream again), run
the test, and confirm it FAILS with `Bad state: Stream has already been listened
to`. Then restore the wrapper and confirm it passes again. A regression test
that cannot fail is not a regression test.

- [ ] **Step 4: Commit**

```bash
git add app/test/ui/today_screen_scroll_test.dart
git commit -m "test(app): Home survives a full scroll cycle in a short viewport"
```

---

### Task 8: Error surfacing

The app currently has no `FlutterError.onError`, no `ErrorWidget.builder`, no
`runZonedGuarded` and no `PlatformDispatcher.instance.onError`. Every uncaught
build exception in release renders Flutter's featureless gray `ErrorWidget` and
its text reaches only logcat.

**Files:**
- Create: `app/lib/util/error_surface.dart`
- Modify: `app/lib/main.dart:36-37` (install the handlers at the top of `main`)
- Test: `app/test/util/error_surface_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `void installErrorSurface()` — called once from `main()`.

- [ ] **Step 1: Write the failing test**

Create `app/test/util/error_surface_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/error_surface.dart';

void main() {
  testWidgets('a build exception renders a readable card, not a blank box',
      (tester) async {
    installErrorSurface();

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
    installErrorSurface();

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C app test TEST=test/util/error_surface_test.dart`
Expected: FAIL — `installErrorSurface` is not defined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/util/error_surface.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The most recent build error's full details, kept so the on-screen card's
/// copy action can hand over the stack trace.
String _lastDetails = '';

/// Replaces Flutter's default release ErrorWidget — a featureless gray box —
/// with a card that says what actually went wrong and copies the full details
/// on tap.
///
/// The card is deliberately dependency-free: an ErrorWidget can be inflated
/// ABOVE MaterialApp, so there may be no Theme, Directionality, MediaQuery or
/// localizations in scope. It therefore supplies its own Directionality and
/// hardcodes its colours, uses no design tokens and no AppLocalizations, and
/// keeps its text wrapped so it cannot overflow inside a tightly constrained
/// sliver child.
void installErrorSurface() {
  FlutterError.onError = (details) {
    _lastDetails = '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) {
    final message = details.exceptionAsString();
    if (_lastDetails.isEmpty) {
      _lastDetails = '$message\n\n${details.stack ?? ''}';
    }
    final copyText = _lastDetails;
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
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test TEST=test/util/error_surface_test.dart`
Expected: PASS, 2 tests.

If the card's text is not found, the likely cause is `SingleChildScrollView`
needing bounded constraints in the failing widget's slot. Replace it with a
plain `Text` and keep `softWrap: true` — readability beats scrollability here.

- [ ] **Step 5: Install it in `main()`**

In `app/lib/main.dart`, add the import and call it as the first statement after
the binding is initialised:

```dart
import 'util/error_surface.dart';
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorSurface();
```

- [ ] **Step 6: Run the full suite and analyze**

Run: `make -C app test` then `make -C app analyze`
Expected: all green, "No issues found!"

Note: `main_routing_test.dart` tests pure routing helpers and does not call
`main()`, so installing a global handler does not affect it.

- [ ] **Step 7: Commit**

```bash
git add app/lib/util/error_surface.dart app/lib/main.dart app/test/util/error_surface_test.dart
git commit -m "feat(app): show a copyable error card instead of a gray ErrorWidget"
```

---

### Task 9: Null-safe active-session draft read

`active_session_controller.dart:315-318` is `assert(_draft != null); return _draft!;`.
Asserts are stripped in release, leaving a bare `!`, and `_ResumeHero`
(`today_screen.dart:822`) reads it once per second for the whole life of an
active workout. It is unreachable today only because `finish()` nulls the draft
and `SessionManager` clears before notifying with no `await` between — a margin
of one statement's ordering.

**Files:**
- Modify: `app/lib/session/active_session_controller.dart:315-318`
- Modify: `app/lib/ui/today_screen.dart:822`
- Test: `app/test/session/controller_draft_access_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `SessionDraft? get draftOrNull` on `ActiveSessionController`.

- [ ] **Step 1: Write the failing test**

Create `app/test/session/controller_draft_access_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

void main() {
  test('draftOrNull is null before a session is built', () {
    final c = ActiveSessionController();
    expect(c.hasSession, isFalse);
    expect(c.draftOrNull, isNull);
  });
}
```

Read `active_session_controller.dart`'s constructor first — if it requires
arguments, pass whatever the existing `test/session/*` tests pass (see
`controller_session_lifecycle_test.dart`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C app test TEST=test/session/controller_draft_access_test.dart`
Expected: FAIL — `draftOrNull` is not defined.

- [ ] **Step 3: Add the safe accessor**

In `app/lib/session/active_session_controller.dart`, keep `draft` exactly as it
is (callers that legitimately require a draft still use it) and add below it:

```dart
  /// Null-safe read for widgets that may render a frame while the draft is
  /// being torn down. `draft`'s assert is stripped in release, leaving a bare
  /// `!` that would crash instead.
  SessionDraft? get draftOrNull => _draft;
```

- [ ] **Step 4: Use it in `_ResumeHero`**

In `app/lib/ui/today_screen.dart`, change line 822 and guard the build:

```dart
    final draft = widget.controller.draftOrNull;
    if (draft == null) return const SizedBox.shrink();
```

Everything below keeps using the local `draft`, now non-nullable by promotion.

- [ ] **Step 5: Run the test and the suite**

Run: `make -C app test TEST=test/session/controller_draft_access_test.dart`
Expected: PASS.

Run: `make -C app test` then `make -C app analyze`
Expected: all green, "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add app/lib/session/active_session_controller.dart app/lib/ui/today_screen.dart app/test/session/controller_draft_access_test.dart
git commit -m "fix(app): null-safe draft read in the resume hero"
```

---

### Task 10: Cache the remaining per-build stream sites

Five screens still create a fresh watch-stream on every `build()`. Task 2 means
these can no longer crash, so this is purely to stop re-issuing queries on every
rebuild — the rule already documented in `app/CLAUDE.md`.

**Files:**
- Modify: `app/lib/ui/history_screen.dart:57`
- Modify: `app/lib/ui/exercise_library_tab.dart:55`
- Modify: `app/lib/ui/bodyweight_view.dart:53`
- Modify: `app/lib/ui/split_tab.dart:30,33` (StatelessWidget → StatefulWidget)
- Modify: `app/lib/ui/targets_tab.dart:25,28` (StatelessWidget → StatefulWidget)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — no signature changes.

- [ ] **Step 1: Cache the three that already have State**

For `history_screen.dart`, `exercise_library_tab.dart` and `bodyweight_view.dart`,
hoist the stream into a `late final` field beside the existing repository field
and reference it in the `StreamBuilder`. Worked example for `history_screen.dart`
(the repository field already exists; add the stream field next to it):

```dart
  late final Stream<List<HistorySessionRow>> _statsStream =
      _sessionRepo.watchSessionStats();
```

and at `:57`:

```dart
      stream: _statsStream,
```

Do the same for `exercise_library_tab.dart` (`_repo.watchCatalog()`) and
`bodyweight_view.dart` (`_bwRepo.watchSeriesAsc()`).

- [ ] **Step 2: Convert `split_tab.dart` to a StatefulWidget**

```dart
class SplitTab extends StatefulWidget {
  const SplitTab({super.key /* keep every existing parameter verbatim */});

  @override
  State<SplitTab> createState() => _SplitTabState();
}

class _SplitTabState extends State<SplitTab> {
  late final DayTemplateRepository _repo = DayTemplateRepository(db);
  late final Stream<List<DayTemplate>> _daysStream = _repo.watchDays();

  @override
  Widget build(BuildContext context) {
    // the existing build body, with `repo` → `_repo`,
    // `repo.watchDays()` → `_daysStream`, and every `widget.` prefix added
    // to what were constructor parameters
  }
}
```

- [ ] **Step 3: Convert `targets_tab.dart` the same way**

Same shape with `MuscleTargetRepository(db)` and `watchTargets()`.
`test/ui/targets_tab_test.dart` renders `TargetsList`, not `TargetsTab`, so it
should be unaffected — confirm by running it.

- [ ] **Step 4: Run the full suite and analyze**

Run: `make -C app test`
Expected: all green. Pay attention to `test/ui/targets_tab_test.dart` and any
test rendering the plan tabs.

Run: `make -C app analyze`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add app/lib/ui
git commit -m "perf(app): cache watch-streams in fields on the remaining five screens"
```

---

### Task 11: Memoize the exercise-keyed progress stream

`progress_screen.dart:101` creates `watchSeriesFor(exId)` inside a nested
builder. It is parameterised by the selected exercise, so a plain field will not
do — it needs a one-entry memo keyed on the id.

**Files:**
- Modify: `app/lib/ui/progress_screen.dart:43-56,101`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Add the keyed memo to `_ProgressScreenState`**

```dart
  String? _seriesKey;
  Stream<List<ProgressPoint>>? _seriesStream;

  /// One-entry memo: re-create the series stream only when the selected
  /// exercise actually changes, instead of on every rebuild.
  Stream<List<ProgressPoint>> _seriesFor(String exerciseId) {
    if (_seriesKey != exerciseId || _seriesStream == null) {
      _seriesKey = exerciseId;
      _seriesStream = _progressRepo.watchSeriesFor(exerciseId);
    }
    return _seriesStream!;
  }
```

- [ ] **Step 2: Use it**

At `progress_screen.dart:101`:

```dart
          stream: _seriesFor(exId),
```

- [ ] **Step 3: Run the tests and analyze**

Run: `make -C app test TEST=test/ui/progress_screen_target_test.dart`
Expected: PASS.

Run: `make -C app test` then `make -C app analyze`
Expected: all green, "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add app/lib/ui/progress_screen.dart
git commit -m "perf(app): memoize the progress series stream on the selected exercise"
```

---

### Task 12: CI gate and documentation corrections

`app/CLAUDE.md` claims "CI runs analyze + tests". It does not — `.github/workflows/`
contains only `android-release.yml` and the server image build. This class of bug
shipped three times behind a local-only gate.

**Files:**
- Create: `.github/workflows/app-ci.yml`
- Modify: `app/CLAUDE.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Add the workflow**

Create `.github/workflows/app-ci.yml`, matching the Flutter version pinned in
`android-release.yml:24` and `app/.fvmrc`:

```yaml
name: app-ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  analyze-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.0'
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Analyze
        working-directory: app
        run: flutter analyze

      - name: Test
        working-directory: app
        run: flutter test
```

This job calls `flutter` directly because it runs on a CI image with no fvm and
no repo-root Makefile context; the fvm rule governs local development. Keep the
version string in step 2 identical to `app/.fvmrc` — verify with
`cat app/.fvmrc`.

- [ ] **Step 2: Check the integration tests survive CI**

`test/data/offline_create_integration_test.dart` and the new
`repo_relisten_integration_test.dart` open a real `PowerSyncDatabase`, which
links a native SQLite extension. Push the branch and confirm the job passes.
If the native library is unavailable on the runner, do NOT delete the tests —
guard the CI step or the tests' `main()` with a skip and record the limitation
in `app/CLAUDE.md`, so the local gate still runs them.

- [ ] **Step 3: Correct `app/CLAUDE.md`**

Two edits in the "Hard-won rules" section:

1. Replace the claim that CI runs analyze + tests with what is now true: a
   `pull_request`/`push`-triggered workflow runs analyze + tests, while
   device-visible output (painters, layouts no test pumps) is still only
   verified on-device.
2. Extend the existing `NEVER create a single-subscription stream ... inside
   build()` rule with the caveat this increment exists to fix:

   > Caching a `db.watch()` stream in a `late final` field is only half the
   > rule — a cached SINGLE-SUBSCRIPTION stream turns a recycled lazy `ListView`
   > child into a hard crash when the sliver garbage-collects it and re-creates
   > it on scroll-back. Every repository `watchX()` now returns a re-listenable
   > stream (`data/re_listenable.dart`); keep new ones wrapped the same way.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/app-ci.yml app/CLAUDE.md
git commit -m "ci: run app analyze and tests on push and pull request"
```

---

### Task 13: Version bump and release

**Files:**
- Modify: `app/pubspec.yaml:4`

- [ ] **Step 1: Final full verification**

Run: `make -C app analyze`
Expected: "No issues found!"

Run: `make -C app test`
Expected: all green.

Run: `make -C app build`
Expected: a successful Linux desktop bundle — this compiles the PowerSync native
libs and is the project's smoke test.

- [ ] **Step 2: Verify the original crash is actually gone**

```bash
timeout 25 ./app/build/linux/x64/release/bundle/workout_tracker > /tmp/reps-check.out 2>&1
grep -c "Bad state" /tmp/reps-check.out
```

The release bundle must be rebuilt first (`make -C app build` produces the debug
bundle; use the release target the project uses for desktop). Expected: **0**
matches, where v0.12.15 produced 16 error reports per run. Redirect to a FILE —
piping to `tail` loses the output to buffering when `timeout` sends SIGTERM.

- [ ] **Step 3: Bump the version**

In `app/pubspec.yaml`, line 4: `version: 0.12.16+28`

```bash
git add app/pubspec.yaml
git commit -m "chore(app): bump version to 0.12.16"
```

- [ ] **Step 4: Adversarial review before merging**

Request a code review of the whole branch diff (see
`superpowers:requesting-code-review`). The two things to press hardest on:
whether `reListenable`'s replay can deliver a stale value that a consumer treats
as fresh, and whether any `onError` path leaves the UI in a state the user
cannot escape.

- [ ] **Step 5: Merge and tag**

```bash
git checkout main
git merge --no-ff <branch>   # subject must carry "(v0.12.16)"
git tag v0.12.16
git push origin main --tags
```

The release workflow hard-fails if the pubspec version (sans `+build`) does not
match the tag.

- [ ] **Step 6: Device verification (nothing here is provable in CI)**

- Home survives finishing and minimizing a workout.
- Home survives rotating to landscape and a system font scale of 1.3.
- Tapping a Recent-PR row on Home opens Progress with no gray screen.
- A deliberately broken build shows the error card with readable text, and
  tapping it copies the details.

---

## Self-Review

**Spec coverage:** §1 → Task 1. §2 → Task 2. §3 → Tasks 10, 11. §4 → Task 5.
§5 → Task 6. §6 → Task 8. §7 → Task 9. §8 (testing) → Tasks 1, 2, 3, 5, 6, 7, 8, 9.
§9 → Task 12. §10 (out of scope) → no task, by design. §11 → Task 13.
Task 4 is plan-only scaffolding the spec's §8 requires.

**Type consistency:** `reListenable<T>(Stream<T> Function())` is used with that
exact signature in Tasks 2 and 3. `dbForTests` is a setter taking
`PowerSyncDatabase?` in Tasks 4, 5, 6, 7. `draftOrNull` returns `SessionDraft?`
in Task 9's test and both of its call sites. `installErrorSurface()` takes no
arguments and returns void in Task 8's test and in `main.dart`.

**Known soft spots**, called out rather than hidden: the exact INSERT column
lists in Tasks 2 and 6 must be checked against `app/lib/sync/schema.dart`; the
provider wrapper in Task 6 must be checked against `TodayScreen`'s real
constructor; and Task 7 has an explicit permission to stop if the global-`db`
seam proves insufficient.
