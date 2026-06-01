# Local-First Standalone (Spec A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app a fully usable standalone local-first app — no server, no login required — with a first-launch onboarding choice (start empty vs add starter exercises), a locally-generated identity, and an editable server URL so sync becomes an optional opt-in.

**Architecture:** Add an `IdentityService` (persisted `currentUserId` + `onboardingComplete`, adopt-existing-or-generate). Port the server's exercise catalog into a client-side seed. Remove the login gate from app entry: `main()` opens the local DB and routes to onboarding (first launch) or the app shell; PowerSync `connect()` happens only when sync is explicitly enabled with a remembered session. Login moves into Settings as an optional action where the server URL is editable without being signed in.

**Tech Stack:** Flutter 3.44 (fvm), PowerSync (local SQLite, `connect()` optional), provider, shared_preferences, uuid. Run everything via `make -C app <target>`.

**Spec:** `docs/superpowers/specs/2026-06-01-local-first-standalone-design.md`

**Branch:** `local-first-standalone` (branch off `main`).

**Grounding facts (verified in code — do not re-derive):**
- Local read queries do NOT filter by `user_id` (`exercise_repository.dart:112` `SELECT * FROM exercises ORDER BY name`; `muscle_target_repository.dart:28` `SELECT ... FROM muscle_targets ORDER BY muscle`). So local rows with NULL `user_id` display fine. Identity is needed for the `muscle_targets` seed (table has `UNIQUE(user_id, muscle)`).
- `anyUserId()` runtime use is ONLY at `today_screen.dart:134` (the muscle-target auto-seed `_seedOnce`). The definition is `session_repository.dart:84`: `SELECT user_id FROM sessions LIMIT 1`.
- Client INSERT builders omit `user_id`/`created_at`/`is_template` (server stamps them on upload). The seed inserts are LOCAL-authored, so they stamp `created_by` + `is_template` themselves.
- `MuscleTargetRepository.seedDefaultsIfEmpty(String userId)` already exists and is idempotent (seeds 8 only when the table is empty).
- `LoginScreen({required AuthStore auth, required Future<void> Function() onLoggedIn})`.
- `ProfileScreen` already owns an editable `_serverCtrl` + `setServerUrl` + `apiBaseUrl =` + a server-switch flow; it's reached from the Today avatar. It currently assumes a signed-in session (shows email + Sign out).
- `SettingsService` is a shared_preferences-backed `ChangeNotifier`; tests use `SharedPreferences.setMockInitialValues({})`.

---

## Task 1: `IdentityService` + `SettingsService.syncEnabled`

**Files:**
- Create: `app/lib/identity/identity_service.dart`
- Modify: `app/lib/settings/settings_service.dart`
- Test: `app/test/identity/identity_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/identity/identity_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/identity/identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates and persists a fresh id when nothing exists, onboarding incomplete', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => null);
    expect(svc.currentUserId, isNotEmpty);
    expect(svc.onboardingComplete, isFalse);

    // A second service reading the same prefs reuses the id.
    final again = IdentityService();
    await again.init(probeExistingUserId: () async => 'IGNORED-because-already-persisted');
    expect(again.currentUserId, svc.currentUserId);
  });

  test('adopts an existing identity from the probe and marks onboarding complete', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => 'server-user-123');
    expect(svc.currentUserId, 'server-user-123');
    expect(svc.onboardingComplete, isTrue);
  });

  test('completeOnboarding persists the flag', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = IdentityService();
    await svc.init(probeExistingUserId: () async => null);
    expect(svc.onboardingComplete, isFalse);
    await svc.completeOnboarding();
    expect(svc.onboardingComplete, isTrue);
    final reload = IdentityService();
    await reload.init(probeExistingUserId: () async => null);
    expect(reload.onboardingComplete, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `identity_service.dart` not found / `IdentityService` undefined.

- [ ] **Step 3: Implement `IdentityService`**

Create `app/lib/identity/identity_service.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart' show uuid; // shared uuid singleton (project convention)
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the device-local identity for the standalone (server-optional) app.
///
/// `currentUserId` is the owner id used for local writes that need one (the
/// `muscle_targets` seed in particular). It is generated once and persisted, or
/// ADOPTED from an existing install (a remembered login / synced data) so prior
/// rows are not orphaned. `onboardingComplete` gates the first-launch screen.
class IdentityService extends ChangeNotifier {
  static const _kUserId = 'identity.current_user_id';
  static const _kOnboarded = 'identity.onboarding_complete';

  String _currentUserId = '';
  bool _onboardingComplete = false;

  String get currentUserId => _currentUserId;
  bool get onboardingComplete => _onboardingComplete;

  /// Initialise from persisted prefs, falling back to:
  ///   1. persisted id (reuse), else
  ///   2. an id from [probeExistingUserId] (adopt existing install → onboarded), else
  ///   3. a freshly generated uuid (fresh install → onboarding pending).
  Future<void> init({
    required Future<String?> Function() probeExistingUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString(_kUserId);
    if (persisted != null && persisted.isNotEmpty) {
      _currentUserId = persisted;
      _onboardingComplete = prefs.getBool(_kOnboarded) ?? true;
      return;
    }
    final adopted = await probeExistingUserId();
    if (adopted != null && adopted.isNotEmpty) {
      _currentUserId = adopted;
      _onboardingComplete = true;
    } else {
      _currentUserId = uuid.v4();
      _onboardingComplete = false;
    }
    await prefs.setString(_kUserId, _currentUserId);
    await prefs.setBool(_kOnboarded, _onboardingComplete);
  }

  Future<void> completeOnboarding() async {
    _onboardingComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }
}
```

`uuid` here is the singleton re-exported by `package:powersync/powersync.dart` (the project convention — see `muscle_target_repository.dart:1` `import 'package:powersync/powersync.dart' show PowerSyncDatabase, uuid;`). Do NOT add a direct `package:uuid` dependency.

- [ ] **Step 4: Add `syncEnabled` to `SettingsService`**

In `app/lib/settings/settings_service.dart`, mirror the existing persisted-field pattern (e.g. how `serverUrl` is stored/loaded/exposed): add a private `bool _syncEnabled = false;`, a getter `bool get syncEnabled => _syncEnabled;`, load it in `load()` (`_syncEnabled = prefs.getBool('settings.sync_enabled') ?? false;`), and a setter:
```dart
  Future<void> setSyncEnabled(bool value) async {
    _syncEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings.sync_enabled', value);
    notifyListeners();
  }
```
(Match the exact prefs-access idiom already used in the file — if it caches a `SharedPreferences` instance, reuse that instead of calling `getInstance()`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!" (100 now: 97 + 3).

- [ ] **Step 6: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/identity/identity_service.dart app/lib/settings/settings_service.dart app/test/identity/identity_service_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): IdentityService + settings syncEnabled for local-first"
```

---

## Task 2: Client-side starter catalog seed

**Files:**
- Create: `app/lib/data/catalog_seed.dart`
- Test: `app/test/data/catalog_seed_test.dart`
- Read (source data): `server/db/migrations/00005_seed_template_exercises.sql`, `server/db/migrations/00019_seed_exercise_traits.sql`

- [ ] **Step 1: Write the failing test**

Create `app/test/data/catalog_seed_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/catalog_seed.dart';
import 'package:workout_tracker/data/session_writer.dart';

/// Records every execute() call so we can assert the seed's SQL/args.
class _FakeExec implements SqlExecutor {
  final List<(String, List<Object?>)> calls = [];
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

void main() {
  test('starterExercises holds the full catalog', () {
    expect(starterExercises.length, 24);
    // Every row has a non-empty slug + name + muscle group.
    for (final e in starterExercises) {
      expect(e.slug, isNotEmpty);
      expect(e.name, isNotEmpty);
      expect(e.muscleGroup, isNotEmpty);
    }
    // Slugs are unique.
    expect(starterExercises.map((e) => e.slug).toSet().length, 24);
  });

  test('seedStarterCatalog inserts one INSERT per exercise, owned by the user', () async {
    final exec = _FakeExec();
    await seedStarterCatalog(exec, 'user-1');
    expect(exec.calls.length, 24);
    final (sql, args) = exec.calls.first;
    expect(sql, contains('INSERT INTO exercises'));
    expect(sql, contains('created_by'));
    expect(sql, contains('is_template'));
    // created_by carries the local user id; is_template is 0 (the user's own row).
    expect(args, contains('user-1'));
    expect(args, contains(0));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `catalog_seed.dart` not found.

- [ ] **Step 3: Implement the seed (port the real catalog)**

READ `server/db/migrations/00005_seed_template_exercises.sql` (slug, name, muscle_group) and `server/db/migrations/00019_seed_exercise_traits.sql` (equip, compound, base_weight_kg, plate_step_kg, default_rep_low/high, default_warmup_sets, default_working_sets, default_rir_low/high), joining on slug. These two files are the canonical source of the 24-exercise catalog — port them verbatim. Create `app/lib/data/catalog_seed.dart`:

```dart
import 'package:powersync/powersync.dart' show uuid; // shared uuid singleton (project convention)

import 'session_writer.dart';

/// One row of the bundled starter catalog (ported from server migrations
/// 00005 + 00019, joined on slug). These are inserted as the user's OWN
/// exercises (created_by = local id, is_template = 0) so they are editable
/// and deletable.
class StarterExercise {
  final String slug;
  final String name;
  final String muscleGroup;
  final String equip; // '' if none
  final bool compound;
  final double? baseWeightKg; // null → '' (NULL locally)
  final double plateStepKg;
  final int defaultRepLow;
  final int defaultRepHigh;
  final int defaultWarmupSets;
  final int defaultWorkingSets;
  final int defaultRirLow;
  final int defaultRirHigh;

  const StarterExercise({
    required this.slug,
    required this.name,
    required this.muscleGroup,
    required this.equip,
    required this.compound,
    required this.baseWeightKg,
    required this.plateStepKg,
    required this.defaultRepLow,
    required this.defaultRepHigh,
    required this.defaultWarmupSets,
    required this.defaultWorkingSets,
    required this.defaultRirLow,
    required this.defaultRirHigh,
  });
}

/// The 24 starter exercises. PORTED FROM the two named migrations — keep slugs
/// EXACTLY as in 00005/00019 (the trait seed keys on these real slugs).
const List<StarterExercise> starterExercises = [
  // <-- Port all 24 rows here from 00005 + 00019. Example shape (replace with
  //     the real values; do NOT invent — copy from the migrations):
  // StarterExercise(slug: 'barbell-back-squat', name: 'Barbell Back Squat',
  //   muscleGroup: 'quads', equip: 'barbell', compound: true,
  //   baseWeightKg: 20.0, plateStepKg: 2.5, defaultRepLow: 5, defaultRepHigh: 8,
  //   defaultWarmupSets: 2, defaultWorkingSets: 3, defaultRirLow: 1, defaultRirHigh: 3),
];

/// Inserts every [starterExercises] row via [exec], owned by [userId].
/// Mirrors the exercise column layout but — unlike the runtime upsert which
/// lets the server stamp ownership — stamps created_by + is_template LOCALLY,
/// because in standalone mode there is no server.
Future<void> seedStarterCatalog(SqlExecutor exec, String userId) async {
  final nowIso = DateTime.now().toUtc().toIso8601String();
  for (final e in starterExercises) {
    await exec.execute(
      'INSERT INTO exercises '
      '(id, slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg, '
      'default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, '
      'default_rir_low, default_rir_high, created_by, is_template, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        uuid.v4(),
        e.slug,
        e.name,
        e.muscleGroup,
        e.equip,
        e.compound ? 1 : 0,
        e.baseWeightKg == null ? '' : e.baseWeightKg!.toStringAsFixed(2),
        e.plateStepKg.toStringAsFixed(2),
        e.defaultRepLow,
        e.defaultRepHigh,
        e.defaultWarmupSets,
        e.defaultWorkingSets,
        e.defaultRirLow,
        e.defaultRirHigh,
        userId,
        0,
        nowIso,
      ],
    );
  }
}
```

> The `const [...]` list MUST contain all 24 real rows from the migrations. After porting, the Step-1 test (`length == 24`, unique slugs) is the gate — if it's not 24, you missed rows.

> **CRITICAL schema cross-check (the test uses a FakeExec, so it CANNOT catch a wrong column name — a bad name only fails at runtime during onboarding, which no automated check exercises).** Before finishing, open `app/lib/sync/schema.dart` and confirm the `exercises` table declares EVERY column the INSERT writes: `slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg, default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, default_rir_low, default_rir_high, created_by, is_template, created_at` (`id` is implicit in PowerSync). If any column is named differently or absent in the schema, change the seed's SQL to match the ACTUAL schema column names (do not add columns to the schema). Note in your report which columns you confirmed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!" (102 now). If `length == 24` fails, you under/over-ported rows.

- [ ] **Step 5: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/data/catalog_seed.dart app/test/data/catalog_seed_test.dart
git commit -m "feat(app): client-side starter exercise catalog seed (24 exercises)"
```

---

## Task 3: Onboarding screen + relocate the muscle-target seed

**Files:**
- Create: `app/lib/ui/onboarding_screen.dart`
- Modify: `app/lib/ui/today_screen.dart` (remove `_seedOnce` auto-seed)
- Test: `app/test/ui/onboarding_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `app/test/ui/onboarding_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/onboarding_screen.dart';

void main() {
  testWidgets('shows both choices and reports the selection', (tester) async {
    OnboardingChoice? chosen;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onChosen: (c) async => chosen = c),
    ));
    expect(find.text('Start empty'), findsOneWidget);
    expect(find.text('Add starter exercises'), findsOneWidget);

    await tester.tap(find.text('Add starter exercises'));
    await tester.pumpAndSettle();
    expect(chosen, OnboardingChoice.starter);
  });

  testWidgets('start empty reports the empty choice', (tester) async {
    OnboardingChoice? chosen;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onChosen: (c) async => chosen = c),
    ));
    await tester.tap(find.text('Start empty'));
    await tester.pumpAndSettle();
    expect(chosen, OnboardingChoice.empty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `onboarding_screen.dart` not found.

- [ ] **Step 3: Implement the onboarding screen**

Create `app/lib/ui/onboarding_screen.dart`. Use the existing design primitives where natural (e.g. `PrimaryBtn` from `widgets/plan_form.dart`, the theme via `Theme.of(context)`); keep it simple — a title, a one-line explainer, and two clear actions:
```dart
import 'package:flutter/material.dart';

enum OnboardingChoice { empty, starter }

/// First-launch screen: lets the user start with an empty library or seed a
/// starter set of exercises (+ default muscle targets). Everything seeded is
/// editable/deletable later. [onChosen] performs the seeding + marks onboarding
/// complete; this widget only collects the choice.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onChosen});

  final Future<void> Function(OnboardingChoice choice) onChosen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome', style: t.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'How would you like to start? You can change everything later.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => onChosen(OnboardingChoice.starter),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Add starter exercises'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => onChosen(OnboardingChoice.empty),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Start empty'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Remove the auto-seed from `today_screen.dart`**

The muscle-target seed must no longer fire automatically on Today (it would re-fill "start empty" users). In `app/lib/ui/today_screen.dart`:
- Delete the `_seedOnce()` method (the block around line 130-140 that calls `_sessions.anyUserId()` then `_targets.seedDefaultsIfEmpty(userId)`).
- Delete the `_seedOnce();` call in `initState` (around line 127) and the `_seeded` field if it becomes unused.
- Leave the `_targets` field/usage that the dashboard reads. If removing the seed leaves `_sessions.anyUserId` unused and `_sessions` otherwise unused, keep `_sessions` only if other code uses it (it does — recent sessions). Do NOT remove unrelated usage.

Run `make -C app analyze` after editing to catch any now-unused field/import and clean it up.

- [ ] **Step 5: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'` and `make -C app analyze 2>&1 | grep -iE 'no issues|error'`
Expected: "All tests passed!" (104 now) and "No issues found!".

- [ ] **Step 6: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/ui/onboarding_screen.dart app/lib/ui/today_screen.dart app/test/ui/onboarding_screen_test.dart
git commit -m "feat(app): onboarding screen; move muscle-target seed off Today"
```

---

## Task 4: Bootstrap rewiring — login-optional entry + identity wiring

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/ui/today_screen.dart` (identity for the relocated seed is now via onboarding, but Today must still read identity if it seeds — it no longer does, so no identity needed there)
- Test: `app/test/main_routing_test.dart`

> This task removes the login gate. `main()` always opens the local DB and routes on `onboardingComplete`; sync `connect()` happens only when `settings.syncEnabled && loggedIn`.

- [ ] **Step 1: Write the failing test for the routing decision**

The routing decision is pure — extract it so it's testable. Create `app/test/main_routing_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/main.dart';

void main() {
  test('routes to onboarding when not complete', () {
    expect(homeRouteFor(onboardingComplete: false), HomeRoute.onboarding);
  });
  test('routes to shell when onboarding complete', () {
    expect(homeRouteFor(onboardingComplete: true), HomeRoute.shell);
  });

  test('shouldConnectSync only when sync enabled AND logged in', () {
    expect(shouldConnectSync(syncEnabled: true, loggedIn: true), isTrue);
    expect(shouldConnectSync(syncEnabled: true, loggedIn: false), isFalse);
    expect(shouldConnectSync(syncEnabled: false, loggedIn: true), isFalse);
    expect(shouldConnectSync(syncEnabled: false, loggedIn: false), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `homeRouteFor`/`HomeRoute`/`shouldConnectSync` undefined.

- [ ] **Step 3: Implement bootstrap + routing helpers in `main.dart`**

Rewrite `app/lib/main.dart` so it: loads settings + units + identity (identity probes `SessionRepository(db).anyUserId`), conditionally connects sync, and routes via the pure helpers. Replace the current login-gated `_AppState` with onboarding/shell routing. Key additions (top-level, testable) and the new bootstrap:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_store.dart';
import 'data/catalog_seed.dart';
import 'data/muscle_target_repository.dart';
import 'data/session_repository.dart';
import 'data/session_writer.dart';
import 'identity/identity_service.dart';
import 'settings/settings_service.dart';
import 'shell/app_shell.dart';
import 'sync/db.dart';
import 'theme/app_theme.dart';
import 'ui/onboarding_screen.dart';
import 'units/unit_service.dart';

enum HomeRoute { onboarding, shell }

/// Pure routing decision for first-launch vs returning user.
HomeRoute homeRouteFor({required bool onboardingComplete}) =>
    onboardingComplete ? HomeRoute.shell : HomeRoute.onboarding;

/// Pure: only connect PowerSync when the user has opted into sync AND has a
/// remembered session.
bool shouldConnectSync({required bool syncEnabled, required bool loggedIn}) =>
    syncEnabled && loggedIn;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  await settingsService.load();
  final unitService = UnitService();
  await unitService.load();
  apiBaseUrl = settingsService.serverUrl;

  final auth = AuthStore();
  await openDatabase();

  final identity = IdentityService();
  await identity.init(
    probeExistingUserId: () => SessionRepository(db).anyUserId(),
  );

  final loggedIn = await auth.load();
  if (shouldConnectSync(
      syncEnabled: settingsService.syncEnabled, loggedIn: loggedIn)) {
    await connectSync(auth);
  }

  runApp(App(
    auth: auth,
    settingsService: settingsService,
    unitService: unitService,
    identity: identity,
  ));
}
```

Then the `App` widget provides all four services (use `ChangeNotifierProvider.value` for settings/units/identity, keep the `Builder`-under-`MultiProvider` theme pattern already in the file), and `home:` is computed from `identity.onboardingComplete`:
```dart
        home: homeRouteFor(onboardingComplete: identity.onboardingComplete) ==
                HomeRoute.onboarding
            ? OnboardingScreen(onChosen: (choice) => _onOnboardingChosen(ctx, choice))
            : AppShell(onLogout: _onLogout, auth: widget.auth),
```
where `_onOnboardingChosen` seeds when `starter` and always completes onboarding + rebuilds:
```dart
  Future<void> _onOnboardingChosen(BuildContext ctx, OnboardingChoice choice) async {
    final identity = ctx.read<IdentityService>();
    if (choice == OnboardingChoice.starter) {
      await db.writeTransaction(
        (tx) => seedStarterCatalog(PowerSyncTxExecutor(tx), identity.currentUserId),
      );
      await MuscleTargetRepository(db).seedDefaultsIfEmpty(identity.currentUserId);
    }
    await identity.completeOnboarding(); // notifies → App rebuilds → shell
  }
```
Make `_AppState` rebuild on `identity` changes (the `IdentityService` is a provider; watch it in the `Builder` so `completeOnboarding()`'s `notifyListeners()` re-routes to the shell). Remove `startLoggedIn`/`_loggedIn`-as-gate; `AppShell` is shown whenever onboarding is complete. Logout (`_onLogout`) keeps `disconnectAndClear()` + `auth.logout()` + `setSyncEnabled(false)` and returns to the shell (local app), NOT a login wall.

Confirm `MuscleTargetRepository` and `SessionRepository` constructors take the `db` positionally as used above (they take a `PowerSyncDatabase db` field — match their real constructors; adjust if named).

- [ ] **Step 4: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'` and `make -C app analyze 2>&1 | grep -iE 'no issues|error'`
Expected: "All tests passed!" (107 now) and "No issues found!".

- [ ] **Step 5: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/main.dart app/test/main_routing_test.dart
git commit -m "feat(app): login-optional bootstrap with onboarding routing"
```

---

## Task 5: Settings/Profile — optional sign-in, editable URL when signed out

**Files:**
- Modify: `app/lib/ui/profile_screen.dart`

> Now that app entry no longer requires login, Profile (reached from the Today avatar) is the place to opt into sync. When NOT synced, show the editable server URL + a "Sign in to sync" action; when synced, keep the existing email + Sign out + switch-server behaviour.

- [ ] **Step 1: Branch the Account/sync section on signed-in state**

In `app/lib/ui/profile_screen.dart`, determine signed-in state from `widget.auth.email != null` (or an `accessToken`/refresh presence). Render:
- **Signed in:** the existing email + "Sign out" + server-switch UI (unchanged).
- **Not signed in:** the editable server URL field (the existing `_serverCtrl` UI, but WITHOUT the "Switch server?" teardown that assumes a session) plus a primary action **"Sign in to sync"** that:
  1. persists the URL (`settings.setServerUrl(_serverCtrl.text.trim())` + `apiBaseUrl = ...`),
  2. pushes `LoginScreen(auth: widget.auth, onLoggedIn: ...)` as a route/overlay,
  3. on successful `onLoggedIn`: `await settings.setSyncEnabled(true)`, `await connectSync(widget.auth)`, pop back, and `setState`/notify so the UI reflects the signed-in state.

Import `connectSync` from `sync/db.dart` and `LoginScreen` from `ui/login_screen.dart`. Keep the signed-in server-switch flow exactly as-is.

- [ ] **Step 2: Verify analyze + tests**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "No issues found!" and "All tests passed!" (107 — no new tests; this is UI wiring validated by the smoke in Task 6).

- [ ] **Step 3: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/ui/profile_screen.dart
git commit -m "feat(app): optional sign-in for sync; editable server URL when signed out"
```

---

## Task 6: Verify (INLINE — controller runs this, not a subagent)

- [ ] **Step 1: Static + tests + build**

```bash
make -C app analyze 2>&1 | grep -iE 'no issues|error'
make -C app test 2>&1 | grep -E 'All tests passed|failed'
make -C app build 2>&1 | tail -3
```
Expected: 0 issues; all tests pass; Linux bundle links.

- [ ] **Step 2: Headless smoke — fresh DB shows onboarding, no crash**

A fresh profile (no persisted identity, no tokens) must boot to onboarding without crashing. Run the Linux release binary with a clean support dir:
```bash
cd app/build/linux/x64/release/bundle
rm -rf /tmp/wt_fresh && XDG_DATA_HOME=/tmp/wt_fresh timeout 25 ./workout_tracker > /tmp/wt_lf_smoke.log 2>&1; echo "EXIT=$? (124=ran full/no crash)"
grep -iE 'exception|error|overflow|providernotfound|assert|unhandled' /tmp/wt_lf_smoke.log | grep -ivE 'Connection refused|SocketException|powersync-token|/auth/login' | head
```
Expected: EXIT=124 (ran the full window, no crash); no exception/ProviderNotFound/assert lines other than benign network errors (there should be NO network errors at all now, since sync is off by default — their absence is itself the proof the app no longer phones home on a fresh start).

- [ ] **Step 3: Report results.** Summarise analyze/test/build/smoke outcomes for the merge decision.

---

## Verification summary (Spec A "done")

1. `make -C app analyze` → 0 issues; `make -C app test` → all green (≈107, was 97).
2. `make -C app build` → Linux bundle links.
3. Headless smoke from a clean profile → boots to onboarding, no crash, no outbound network (sync off by default).
4. The app is usable with zero network/login; the server URL is reachable/editable without signing in; sign-in is an opt-in that enables sync.

## Deferred (Spec B — separate spec, not here)

Registration endpoint + flow; first-login keep-local/keep-remote/auto-merge reconciliation; the PowerSync attach-later spike. See `docs/superpowers/specs/2026-06-01-local-first-standalone-design.md` "Spec B — deferred".
