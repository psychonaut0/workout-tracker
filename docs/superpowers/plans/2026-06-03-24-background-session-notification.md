# Background Session + Notification + Accordion Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A workout keeps running while you navigate the app (minimize + mini-bar + resume-on-launch), shows a silent ongoing Android notification with chronometer elapsed / rest countdown, and exercise-block accordions keep their collapsed state — per `docs/superpowers/specs/2026-06-03-background-session-notification-design.md`.

**Architecture:** New app-scoped `SessionManager` owns the `ActiveSessionController` (today the route owns it — `session_launcher.dart:23,43`). Rest-timer state moves from the screen State into the controller. The controller gains debounced draft autosave (today `DraftStore.save` has ZERO callers — the draft JSON is never written during a session) and a `fromDraft` resume path. A pure `notificationPayloadFor` + thin `WorkoutNotification` wrapper drive `flutter_local_notifications` (new dep). The accordion fix reuses the EXISTING `BlockState.expanded` model field (already serialized!) that the widget currently shadows with a local `_expanded`.

**Tech Stack:** Flutter 3.44 (fvm), provider, `flutter_local_notifications` ^21.0.0 (needs core-library desugaring in gradle), existing Motion/tokens system.

**Conventions:**
- Branch: create `background-session` off `main` first.
- Run everything via Makefile from repo root: `make -C app analyze`, `make -C app test`, `make -C app get`, `make -C app build` (Linux), `make -C app build-apk-release`. NEVER run `flutter` directly.
- Baseline: 168 tests green, analyze clean.
- Commit style: Conventional Commits, subject line only, no body.
- Test import prefix `package:workout_tracker/...`.

**Verified facts:**
- Controller: `app/lib/session/active_session_controller.dart` — `_draft`/`draft` getter (:274-281), `hasSession` (:282), `seedEmpty` (:330), `markChanged() => notifyListeners()` (:387), `discard()` nulls `_draft` + notifies (:503-506), `finish(SqlExecutor, {DraftStore? draftStore})` clears store + `_draft` (:441,494-496). `SessionDraft` (:231-262) and `BlockState` (:122-227) both have full toJson/fromJson; **`BlockState.expanded` (bool, non-final) is already serialized**.
- Screen: `app/lib/session/active_session_screen.dart` — rest fields `_restActive/_restStart/_restTotal` (:48-50), `_startRest` (:97-105), `_add30s` (:107-111), `_dismissRest` (:113-119), `_handleRestHaptics` (:70-87), auto-dismiss-at-0 post-frame (:205-213), RestTimerCard at (:318-329), rest started from `onToggleDone` (:257-259). `_Header` (:338-482): left circular button (rotated `WIcons.chevron`) currently wired to the DISCARD flow `onClose`; title Expanded; right elapsed column.
- Launcher: `app/lib/shell/session_launcher.dart:19-59` — creates controller, pushes `PageRouteBuilder` (250/200ms fade+slide) with `ChangeNotifierProvider.value` on the ROOT navigator.
- Shell: `app/lib/shell/app_shell.dart` — `import 'session_launcher.dart' as launcher;` (:16); `_fabStart`/`_start` (:64-75); build = PopScope > Scaffold(extendBody) > Stack[ _TabFade(IndexedStack), Align(bottomCenter, WTabBar) ] (:114-165).
- main: `app/lib/main.dart` — boot order settings→units→openDatabase→identity→backfillTopSets→auth→connectSync→runApp; MultiProvider children unitService/settingsService/identity (:104-108); MaterialApp has NO navigatorKey (:117-125).
- Accordion: `app/lib/session/exercise_block.dart` — local `bool _expanded = true` (:41), toggle (:89), border color (:80), chevron rotation (:182-186), content gate (:193). Blocks rendered in a `ListView` (children disposed past cache extent → state loss).
- flutter_local_notifications **21.0.0**: Flutter ≥3.38 OK; `initialize` uses NAMED params (`settings:`, `onDidReceiveNotificationResponse:`); `AndroidNotificationDetails` has `ongoing`, `autoCancel`, `onlyAlertOnce`, `showWhen`, `usesChronometer`, `chronometerCountDown` (count-down: `when` = FUTURE end time), `when` = **int epoch millis**; permission via `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission()`; channel via `createNotificationChannel`. Gradle: **core library desugaring REQUIRED**; compileSdk 36 = Flutter 3.44 default (no override needed). Manifest: only `POST_NOTIFICATIONS` (no receivers for non-scheduled). Android 14+: ongoing notifications are user-dismissible — accepted. Linux: do NOT initialize — guard everything with `Platform.isAndroid`.

---

### Task 1: Controller — rest state, fromDraft, debounced autosave (TDD)

**Files:**
- Modify: `app/lib/session/active_session_controller.dart`
- Test: `app/test/session/controller_session_lifecycle_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

`app/test/session/controller_session_lifecycle_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/active_session_draft.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

/// In-memory DraftStore double (DraftStore methods are non-final).
class FakeDraftStore extends DraftStore {
  String? saved;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<void> save(SessionDraft draft) async {
    saved = draft.name;
    saveCount++;
  }

  @override
  Future<SessionDraft?> load() async => null;

  @override
  Future<void> clear() async {
    saved = null;
    clearCount++;
  }
}

void main() {
  group('rest timer state', () {
    test('startRest/addRestTime/stopRest transitions and notifications', () {
      final c = ActiveSessionController();
      c.seedEmpty(name: 'Custom', focus: '');
      var notifies = 0;
      c.addListener(() => notifies++);

      expect(c.restStart, isNull);
      c.startRest(90);
      expect(c.restStart, isNotNull);
      expect(c.restTotal, 90);
      c.addRestTime(30);
      expect(c.restTotal, 120);
      c.stopRest();
      expect(c.restStart, isNull);
      expect(c.restTotal, 0);
      expect(notifies, 3);
    });

    test('addRestTime and stopRest are no-ops when not resting', () {
      final c = ActiveSessionController();
      c.seedEmpty(name: 'Custom', focus: '');
      var notifies = 0;
      c.addListener(() => notifies++);
      c.addRestTime(30);
      c.stopRest();
      expect(c.restTotal, 0);
      expect(notifies, 0);
    });
  });

  group('fromDraft', () {
    test('adopts an existing draft as-is', () {
      final draft = SessionDraft(
        templateId: null,
        name: 'Upper A',
        focus: 'Push',
        startedAt: DateTime(2026, 6, 3, 10, 0),
        blocks: [],
      );
      final c = ActiveSessionController.fromDraft(draft);
      expect(c.hasSession, isTrue);
      expect(c.draft.name, 'Upper A');
      expect(c.draft.startedAt, DateTime(2026, 6, 3, 10, 0));
    });
  });

  group('debounced autosave', () {
    test('mutation saves the draft after the debounce window', () async {
      final store = FakeDraftStore();
      final c = ActiveSessionController(draftStore: store);
      c.seedEmpty(name: 'Custom', focus: '');
      c.markChanged();
      expect(store.saveCount, 0); // not yet — debounced
      await Future<void>.delayed(
          ActiveSessionController.saveDebounce + const Duration(milliseconds: 200));
      expect(store.saveCount, 1);
      expect(store.saved, 'Custom');
    });

    test('discard cancels pending saves and clears the store', () async {
      final store = FakeDraftStore();
      final c = ActiveSessionController(draftStore: store);
      c.seedEmpty(name: 'Custom', focus: '');
      c.markChanged();
      c.discard();
      await Future<void>.delayed(
          ActiveSessionController.saveDebounce + const Duration(milliseconds: 200));
      expect(store.saveCount, 0); // pending save cancelled
      expect(store.clearCount, 1);
      expect(c.hasSession, isFalse);
    });

    test('no store → no autosave attempt (and no crash)', () async {
      final c = ActiveSessionController();
      c.seedEmpty(name: 'Custom', focus: '');
      c.markChanged();
      await Future<void>.delayed(
          ActiveSessionController.saveDebounce + const Duration(milliseconds: 200));
      // Nothing to assert beyond "did not throw".
      expect(c.hasSession, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (no `restStart`, no `fromDraft`, no `draftStore` param, no `saveDebounce`).

- [ ] **Step 3: Implement the controller changes**

In `app/lib/session/active_session_controller.dart` (READ the class first; add `import 'dart:async';` and `import '../data/active_session_draft.dart';` if missing — note `finish()` already references `DraftStore`, so the import exists):

(a) Constructors + autosave plumbing — replace the implicit default constructor:
```dart
  /// [draftStore] enables debounced autosave of the in-progress draft (used
  /// for resume-on-launch). Null (e.g. in unit tests) disables persistence.
  ActiveSessionController({DraftStore? draftStore}) : _draftStore = draftStore;

  /// Adopts a previously persisted draft (resume-on-launch / crash recovery).
  ActiveSessionController.fromDraft(SessionDraft draft, {DraftStore? draftStore})
      : _draftStore = draftStore,
        _draft = draft;

  final DraftStore? _draftStore;
  Timer? _saveDebounce;

  /// Autosave debounce window (exposed for tests).
  static const saveDebounce = Duration(seconds: 1);

  @override
  void notifyListeners() {
    _scheduleSave();
    super.notifyListeners();
  }

  void _scheduleSave() {
    final store = _draftStore;
    if (store == null || _draft == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(saveDebounce, () {
      final d = _draft;
      if (d != null) store.save(d);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
```
NOTE: `_draft` is currently declared as `SessionDraft? _draft;` — the `fromDraft` initializer list assigns it, so keep it a plain (non-late) nullable field.

(b) Rest-timer state (new section near the elapsed getter):
```dart
  // ── Rest timer (app-scoped so it survives minimizing the screen) ─────────
  DateTime? restStart;
  int restTotal = 0;

  bool get resting => restStart != null;

  void startRest(int seconds) {
    restStart = DateTime.now();
    restTotal = seconds;
    notifyListeners();
  }

  void addRestTime(int seconds) {
    if (restStart == null) return;
    restTotal += seconds;
    notifyListeners();
  }

  void stopRest() {
    if (restStart == null) return;
    restStart = null;
    restTotal = 0;
    notifyListeners();
  }
```

(c) `discard()` (replace :503-506) — cancel pending saves + clear the disk draft so a discarded workout cannot resurrect on next launch:
```dart
  void discard() {
    _saveDebounce?.cancel();
    _draft = null;
    restStart = null;
    restTotal = 0;
    _draftStore?.clear(); // fire-and-forget; corrupt/missing handled inside
    notifyListeners();
  }
```

(d) In `finish(...)`: add `_saveDebounce?.cancel();` immediately before the existing `await draftStore?.clear();`, and also clear rest state (`restStart = null; restTotal = 0;`) next to `_draft = null;`. The `Timer` body's null-guard already prevents a late save after `_draft = null`.

- [ ] **Step 4: Run `make -C app analyze` (clean) + `make -C app test`** — expect 173 (168 + 5).

- [ ] **Step 5: Commit**
```bash
git add app/lib/session/active_session_controller.dart app/test/session/controller_session_lifecycle_test.dart
git commit -m "feat(app): controller-owned rest timer, fromDraft resume, debounced draft autosave"
```

---

### Task 2: `SessionManager` + boot resume + main.dart wiring (TDD)

**Files:**
- Create: `app/lib/session/session_manager.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/session/session_manager_test.dart`

- [ ] **Step 1: Write the failing tests**

`app/test/session/session_manager_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/active_session_draft.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_manager.dart';

class FakeDraftStore extends DraftStore {
  FakeDraftStore({this.draft});
  SessionDraft? draft;

  @override
  Future<SessionDraft?> load() async => draft;

  @override
  Future<void> save(SessionDraft d) async => draft = d;

  @override
  Future<void> clear() async => draft = null;
}

void main() {
  test('register/clear lifecycle notifies', () {
    final m = SessionManager();
    var notifies = 0;
    m.addListener(() => notifies++);

    final c = ActiveSessionController();
    c.seedEmpty(name: 'Custom', focus: '');
    m.register(c);
    expect(m.hasActive, isTrue);
    expect(m.active, same(c));

    m.clear();
    expect(m.hasActive, isFalse);
    expect(notifies, 2);
  });

  test('controller discard auto-clears the manager', () {
    final m = SessionManager();
    final c = ActiveSessionController();
    c.seedEmpty(name: 'Custom', focus: '');
    m.register(c);

    c.discard(); // draft → null → manager clears itself
    expect(m.hasActive, isFalse);
  });

  test('resumeFromDraft restores a session from disk', () async {
    final store = FakeDraftStore(
      draft: SessionDraft(
        templateId: null,
        name: 'Upper A',
        focus: 'Push',
        startedAt: DateTime(2026, 6, 3, 9, 0),
        blocks: [],
      ),
    );
    final m = SessionManager();
    final resumed = await m.resumeFromDraft(store: store);
    expect(resumed, isTrue);
    expect(m.hasActive, isTrue);
    expect(m.active!.draft.name, 'Upper A');
    expect(m.active!.draft.startedAt, DateTime(2026, 6, 3, 9, 0));
  });

  test('resumeFromDraft without a draft is a no-op', () async {
    final m = SessionManager();
    final resumed = await m.resumeFromDraft(store: FakeDraftStore());
    expect(resumed, isFalse);
    expect(m.hasActive, isFalse);
  });

  test('screenOpen flag notifies on change only', () {
    final m = SessionManager();
    var notifies = 0;
    m.addListener(() => notifies++);
    m.screenOpen = true;
    m.screenOpen = true; // no-op
    m.screenOpen = false;
    expect(notifies, 2);
  });
}
```

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (session_manager.dart missing).

- [ ] **Step 3: Implement `app/lib/session/session_manager.dart`**
```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/active_session_draft.dart';
import 'active_session_controller.dart';
import 'workout_notification.dart';

/// App-scoped owner of the active workout. The session screen renders
/// [active]; minimizing the screen leaves the workout running here. Also the
/// single driver of the ongoing Android notification (when [notifier] is set).
class SessionManager extends ChangeNotifier {
  ActiveSessionController? _active;
  ActiveSessionController? get active => _active;
  bool get hasActive => _active != null;

  /// Set by the session screen (initState/dispose) so the shell knows whether
  /// to show the mini-bar and entry points know whether to resume vs reopen.
  bool _screenOpen = false;
  bool get screenOpen => _screenOpen;
  set screenOpen(bool v) {
    if (v == _screenOpen) return;
    _screenOpen = v;
    notifyListeners();
  }

  /// Optional notification surface (null on Linux/tests).
  WorkoutNotification? notifier;

  /// Stops the rest automatically when it expires while the screen is closed
  /// (with the screen open, its ticker handles this; stopRest is guarded).
  Timer? _restExpiry;

  void register(ActiveSessionController c) {
    _active?.removeListener(_onControllerChange);
    _active = c;
    c.addListener(_onControllerChange);
    notifier?.showFor(
      name: c.draft.name,
      startedAt: c.draft.startedAt,
      restStart: c.restStart,
      restTotal: c.restTotal,
    );
    notifyListeners();
  }

  void _onControllerChange() {
    final c = _active;
    if (c == null) return;
    if (!c.hasSession) {
      // discard()/finish() nulled the draft — tear everything down.
      clear();
      return;
    }
    _armRestExpiry(c);
    notifier?.showFor(
      name: c.draft.name,
      startedAt: c.draft.startedAt,
      restStart: c.restStart,
      restTotal: c.restTotal,
    );
    notifyListeners(); // mini-bar rest-mode swap
  }

  void _armRestExpiry(ActiveSessionController c) {
    _restExpiry?.cancel();
    final start = c.restStart;
    if (start == null) return;
    final remaining =
        start.add(Duration(seconds: c.restTotal)).difference(DateTime.now());
    _restExpiry = Timer(
      remaining.isNegative ? Duration.zero : remaining + const Duration(seconds: 1),
      c.stopRest, // guarded no-op if already stopped
    );
  }

  void clear() {
    _restExpiry?.cancel();
    _active?.removeListener(_onControllerChange);
    _active = null;
    notifier?.cancel();
    notifyListeners();
  }

  /// Boot path: restore a persisted draft (crash / process-death recovery).
  Future<bool> resumeFromDraft({DraftStore? store}) async {
    final s = store ?? DraftStore();
    final draft = await s.load();
    if (draft == null) return false;
    register(ActiveSessionController.fromDraft(draft, draftStore: s));
    return true;
  }

  @override
  void dispose() {
    _restExpiry?.cancel();
    _active?.removeListener(_onControllerChange);
    super.dispose();
  }
}
```
NOTE: this imports `workout_notification.dart` which is created in Task 4. To keep Task 2 self-contained and green, create a MINIMAL placeholder `app/lib/session/workout_notification.dart` now (Task 4 replaces its body):
```dart
/// Ongoing workout notification (Android). Fleshed out in the notification
/// task; this placeholder keeps SessionManager compilable.
class WorkoutNotification {
  Future<void> showFor({
    required String name,
    required DateTime startedAt,
    DateTime? restStart,
    int restTotal = 0,
  }) async {}

  Future<void> cancel() async {}
}
```

- [ ] **Step 4: Wire into `app/lib/main.dart`**
- Add imports: `session/session_manager.dart`.
- In `main()`, after `await backfillTopSets(db);` add:
```dart
  final sessionManager = SessionManager();
  await sessionManager.resumeFromDraft();
```
- Pass `sessionManager` into `App` (new required field, mirroring the others) and add to MultiProvider:
```dart
        ChangeNotifierProvider.value(value: widget.sessionManager),
```
- Add a root navigator key (used by the notification tap in Task 4): top-level in main.dart:
```dart
final appNavigatorKey = GlobalKey<NavigatorState>();
```
and `MaterialApp(navigatorKey: appNavigatorKey, ...)`.

- [ ] **Step 5: Run `make -C app analyze` (clean) + `make -C app test`** — expect 178 (173 + 5).

- [ ] **Step 6: Commit**
```bash
git add app/lib/session/session_manager.dart app/lib/session/workout_notification.dart app/lib/main.dart app/test/session/session_manager_test.dart
git commit -m "feat(app): app-scoped SessionManager with draft resume on launch"
```

---

### Task 3: Launcher/screen/shell integration — minimize, resume, rest-state move

**Files:**
- Modify: `app/lib/shell/session_launcher.dart`
- Modify: `app/lib/session/active_session_screen.dart`
- Modify: `app/lib/shell/app_shell.dart`

- [ ] **Step 1: Launcher — register with the manager + extract the resume path**

Rewrite `startSession` in `session_launcher.dart` (keep `nextInRotation` as is; add `import 'package:provider/provider.dart';` and `import '../session/session_manager.dart';` + `import '../data/active_session_draft.dart';`):
```dart
Future<void> startSession(
  BuildContext context, {
  DayTemplate? template,
}) async {
  final manager = context.read<SessionManager>();

  // A workout is already running → resume it instead of starting a new one.
  if (manager.hasActive) {
    await openActiveSession(context, manager);
    return;
  }

  final controller = ActiveSessionController(draftStore: DraftStore());

  if (template != null) {
    await controller.buildFromTemplate(
      template,
      exerciseRepo: ExerciseRepository(db),
      dayTemplateRepo: DayTemplateRepository(db),
      sessionRepo: SessionRepository(db),
    );
  } else {
    controller.seedEmpty(name: 'Custom', focus: '');
  }

  manager.register(controller);

  if (!context.mounted) return;
  await openActiveSession(context, manager);
}

/// Pushes the session route for the manager's active controller (no-op if
/// none or already open). Shared by start, mini-bar tap and notification tap.
Future<void> openActiveSession(BuildContext context, SessionManager manager) async {
  final controller = manager.active;
  if (controller == null || manager.screenOpen) return;

  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) =>
          ChangeNotifierProvider<ActiveSessionController>.value(
            value: controller,
            child: const ActiveSessionScreen(),
          ),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Motion.curve);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}
```
(The transition body is the EXISTING one — move it, don't retype it.)

- [ ] **Step 2: Session screen — read rest state from the controller, track screenOpen, minimize button**

In `active_session_screen.dart` (`_ActiveSessionScreenState`):
- Add `import 'package:provider/provider.dart';` (already there) + `import 'session_manager.dart';`.
- `initState`: after the ticker setup add
```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionManager>().screenOpen = true;
    });
```
- `dispose`: BEFORE `super.dispose()`, clear the flag without touching context-after-dispose pitfalls — capture the manager in `didChangeDependencies`:
```dart
  SessionManager? _manager;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager = context.read<SessionManager>();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _manager?.screenOpen = false;
    super.dispose();
  }
```
(merge with the existing dispose that cancels `_ticker`).
- DELETE fields `_restActive`, `_restStart`, `_restTotal` (:48-50) and methods `_startRest`/`_add30s`/`_dismissRest` (:97-119). Replace every use with the controller:
  - `onToggleDone` rest trigger (:257-259) → `controller.startRest(b.exercise.compound ? 180 : 90);`
  - `_handleRestHaptics` (:70-87): read `final start = controller.restStart;` etc. — it needs the controller; change the ticker callback to `_handleRestHaptics(context.read<ActiveSessionController>())` or simply pass the controller from build via a field — SIMPLEST: make `_handleRestHaptics(ActiveSessionController c)` take the controller and call it from the ticker via `_manager?.active` guard... The ticker runs in State without build context each second; capture the controller the same way as the manager in `didChangeDependencies` (`_controller = context.read<ActiveSessionController>();`) and use `_controller` in the ticker. Keep the haptic-guard fields as they are.
  - restRemaining computation (:205-213): use `controller.restStart`/`restTotal`; the auto-dismiss post-frame becomes `controller.stopRest()` (guarded internally, and the manager's expiry timer covers the minimized case).
  - RestTimerCard (:318-329):
```dart
              if (controller.restStart != null && restRemaining > 0)
                Positioned(
                  left: 16, right: 16, bottom: 44,
                  child: RestTimerCard(
                    totalSeconds: controller.restTotal,
                    startTime: controller.restStart!,
                    onAdd30s: () => controller.addRestTime(30),
                    onDismiss: controller.stopRest,
                  ),
                ),
```
- `_Header` (:338-482): rename `onClose` → split into `onMinimize` + `onDiscard`:
  - The existing left circular button now means MINIMIZE: change the icon to a downward chevron (`Transform.rotate(angle: 1.5708, child: Icon(WIcons.chevron, ...))` — quarter turn = pointing down) and wire `onTap: onMinimize`.
  - Add a discard button between the title `Expanded` and the elapsed column (same 36×36 circular style):
```dart
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDiscard,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.surface,
                      border: Border.all(color: tokens.line),
                    ),
                    alignment: Alignment.center,
                    child: Icon(WIcons.trash, size: 16, color: tokens.dim),
                  ),
                ),
```
  - Call site (:222-232): `onMinimize: () => Navigator.of(context).pop(), onDiscard: () => _handleClose(context, controller),`.
- `_handleClose` and `_handleFinish` need NO manager calls — `controller.discard()`/`finish()` null the draft and the manager auto-clears via its listener.

- [ ] **Step 3: AppShell — resume-aware entry points**

In `app_shell.dart` `_fabStart` and `_start`, the existing `launcher.startSession(...)` calls already resume when active (Step 1 logic) — no change needed there. (The mini-bar itself is Task 5.)

- [ ] **Step 4: Verify** — `make -C app analyze` clean; `make -C app test` 178 green (no test pumps ActiveSessionScreen today — if one does and now needs a SessionManager provider, wrap the TEST in `ChangeNotifierProvider<SessionManager>`).

- [ ] **Step 5: Commit**
```bash
git add app/lib/shell/session_launcher.dart app/lib/session/active_session_screen.dart app/lib/shell/app_shell.dart
git commit -m "feat(app): minimizable workout — manager-owned session, resume entry points"
```

---

### Task 4: Notification — dep, gradle desugaring, manifest, payload builder (TDD), wiring

**Files:**
- Modify: `app/pubspec.yaml`, `app/android/app/build.gradle.kts`, `app/android/app/src/main/AndroidManifest.xml`, `app/lib/session/workout_notification.dart` (replace placeholder), `app/lib/main.dart`
- Test: `app/test/session/workout_notification_test.dart`

- [ ] **Step 1: Dependency + gradle + manifest**
- `app/pubspec.yaml`:
```yaml
  # Ongoing workout notification (Android): chronometer elapsed / rest countdown.
  flutter_local_notifications: ^21.0.0
```
then `make -C app get` (if ^21 doesn't resolve, try ^20 and adapt — both use named initialize params).
- `app/android/app/build.gradle.kts`: inside `android { ... }` ensure/extend `compileOptions` (READ the file first — there may be an existing compileOptions/kotlinOptions block to merge with):
```kotlin
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
```
and add at the bottom-level `dependencies { ... }` block (create it if absent):
```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```
(If the resolved flutter_local_notifications README pins a newer desugar_jdk_libs, use that version.)
- `AndroidManifest.xml`: add as the second line inside `<manifest>`:
```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
No receivers (not using scheduled notifications).

- [ ] **Step 2: Write the failing payload tests**

`app/test/session/workout_notification_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/workout_notification.dart';

void main() {
  final started = DateTime(2026, 6, 3, 10, 0);
  final now = DateTime(2026, 6, 3, 10, 30);

  test('elapsed mode when not resting', () {
    final p = notificationPayloadFor(
      sessionName: 'Upper A',
      startedAt: started,
      now: now,
    );
    expect(p.title, 'Upper A');
    expect(p.body, 'Workout in progress');
    expect(p.countdown, isFalse);
    expect(p.when, started);
  });

  test('countdown mode while resting, when = rest end', () {
    final restStart = DateTime(2026, 6, 3, 10, 29, 30);
    final p = notificationPayloadFor(
      sessionName: 'Upper A',
      startedAt: started,
      restStart: restStart,
      restTotal: 90,
      now: now, // 30s in, 60s remaining
    );
    expect(p.title, 'Upper A');
    expect(p.body, 'Rest');
    expect(p.countdown, isTrue);
    expect(p.when, restStart.add(const Duration(seconds: 90)));
  });

  test('expired rest falls back to elapsed mode', () {
    final restStart = DateTime(2026, 6, 3, 10, 28, 0);
    final p = notificationPayloadFor(
      sessionName: 'Upper A',
      startedAt: started,
      restStart: restStart,
      restTotal: 90, // ended at 10:29:30, now is 10:30
      now: now,
    );
    expect(p.countdown, isFalse);
    expect(p.when, started);
    expect(p.body, 'Workout in progress');
  });
}
```

- [ ] **Step 3: Run `make -C app test` — expect FAIL** (`notificationPayloadFor` undefined).

- [ ] **Step 4: Replace `app/lib/session/workout_notification.dart`**
```dart
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Pure payload mapping for the ongoing workout notification (testable, no
/// plugin types). Elapsed mode: `when` = session start, Android chronometer
/// counts up. Rest mode: `when` = rest END time, chronometer counts down.
({String title, String body, bool countdown, DateTime when})
    notificationPayloadFor({
  required String sessionName,
  required DateTime startedAt,
  DateTime? restStart,
  int restTotal = 0,
  required DateTime now,
}) {
  if (restStart != null) {
    final end = restStart.add(Duration(seconds: restTotal));
    if (end.isAfter(now)) {
      return (title: sessionName, body: 'Rest', countdown: true, when: end);
    }
  }
  return (
    title: sessionName,
    body: 'Workout in progress',
    countdown: false,
    when: startedAt,
  );
}

/// Thin Android-only wrapper around flutter_local_notifications. All methods
/// are no-ops off-Android (Linux dev builds never initialize the plugin).
class WorkoutNotification {
  static const _id = 1;
  static const _channelId = 'workout_session';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  ({String title, bool countdown, DateTime when})? _lastShown;

  Future<void> init({void Function()? onTap}) async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Workout session',
          importance: Importance.low,
          playSound: false,
        ));
    _ready = true;
  }

  Future<void> showFor({
    required String name,
    required DateTime startedAt,
    DateTime? restStart,
    int restTotal = 0,
  }) async {
    if (!_ready) return;
    if (!_permissionAsked) {
      _permissionAsked = true;
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission(); // result ignored — degrades silently
    }
    final p = notificationPayloadFor(
      sessionName: name,
      startedAt: startedAt,
      restStart: restStart,
      restTotal: restTotal,
      now: DateTime.now(),
    );
    final key = (title: p.title, countdown: p.countdown, when: p.when);
    if (key == _lastShown) return; // unchanged → skip the re-show
    _lastShown = key;
    await _plugin.show(
      _id,
      p.title,
      p.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Workout session',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          usesChronometer: true,
          chronometerCountDown: p.countdown,
          when: p.when.millisecondsSinceEpoch,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );
  }

  Future<void> cancel() async {
    if (!_ready) return;
    _lastShown = null;
    await _plugin.cancel(id: _id);
  }
}
```
CHECK against the resolved package: v21 `initialize` uses named `settings:`; verify `cancel`'s signature (positional `cancel(_id)` in older versions, named in newer — adapt to whichever compiles). If `AndroidNotificationChannel`/`AndroidNotificationDetails` constructor shapes differ slightly in the resolved version, adapt the CALLS, not the pure function.

- [ ] **Step 5: Wire in `main.dart`**

After `final sessionManager = SessionManager();` (BEFORE `resumeFromDraft`, so a resumed session shows the notification):
```dart
  final workoutNotification = WorkoutNotification();
  await workoutNotification.init(onTap: () {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) openActiveSession(ctx, sessionManager);
  });
  sessionManager.notifier = workoutNotification;
  await sessionManager.resumeFromDraft();
```
Imports: `session/workout_notification.dart`, `shell/session_launcher.dart` (for `openActiveSession` — import with a prefix if name clashes).

- [ ] **Step 6: Verify** — `make -C app analyze` clean; `make -C app test` → 181 (178 + 3); `make -C app build` (Linux compiles with the plugin present but uninitialized); `make -C app build-apk` (debug APK — proves gradle desugaring config).

- [ ] **Step 7: Commit**
```bash
git add app/pubspec.yaml app/pubspec.lock app/android app/lib/session/workout_notification.dart app/lib/main.dart app/test/session/workout_notification_test.dart app/linux
git commit -m "feat(app): ongoing workout notification with chronometer elapsed and rest countdown"
```
(`app/linux` included in case plugin registrant files regenerate — commit them if changed.)

---

### Task 5: Mini-bar (TDD)

**Files:**
- Create: `app/lib/shell/session_mini_bar.dart`
- Modify: `app/lib/shell/app_shell.dart`
- Test: `app/test/shell/session_mini_bar_test.dart`

- [ ] **Step 1: Write the failing widget tests**

`app/test/shell/session_mini_bar_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/session_mini_bar.dart';

void main() {
  testWidgets('shows session name and ticking elapsed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionMiniBar(
          name: 'Upper A',
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: null,
          restTotal: 0,
          onTap: () => tapped = true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Upper A'), findsOneWidget);
    expect(find.textContaining('5:0'), findsOneWidget); // 5:00–5:09 window
    await tester.tap(find.byType(SessionMiniBar));
    expect(tapped, isTrue);
    // Let the internal 1s ticker settle so the test ends cleanly.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('swaps to rest countdown while resting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionMiniBar(
          name: 'Upper A',
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          restStart: DateTime.now().subtract(const Duration(seconds: 10)),
          restTotal: 90,
          onTap: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Rest'), findsOneWidget);
    expect(find.textContaining('1:'), findsOneWidget); // ~1:20 remaining
    await tester.pump(const Duration(seconds: 1));
  });
}
```

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (file missing).

- [ ] **Step 3: Implement `app/lib/shell/session_mini_bar.dart`**
```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';
import '../widgets/pressable.dart';

/// Docked "workout in progress" pill shown by the shell while a session is
/// active but its screen is minimized. Ticks elapsed time; swaps to an accent
/// rest countdown while resting. Tap → reopen the session screen.
class SessionMiniBar extends StatefulWidget {
  const SessionMiniBar({
    super.key,
    required this.name,
    required this.startedAt,
    required this.restStart,
    required this.restTotal,
    required this.onTap,
  });

  final String name;
  final DateTime startedAt;
  final DateTime? restStart;
  final int restTotal;
  final VoidCallback onTap;

  @override
  State<SessionMiniBar> createState() => _SessionMiniBarState();
}

class _SessionMiniBarState extends State<SessionMiniBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();

    int restRemaining = 0;
    final restStart = widget.restStart;
    if (restStart != null) {
      restRemaining =
          widget.restTotal - now.difference(restStart).inSeconds;
      if (restRemaining < 0) restRemaining = 0;
    }
    final resting = restRemaining > 0;

    return Reveal(
      child: PressableScale(
        onTap: widget.onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: tokens.lineStrong),
          ),
          child: Row(
            children: [
              Icon(WIcons.dumbbell, size: 15, color: tokens.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkoutType.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                resting
                    ? 'Rest ${_fmt(Duration(seconds: restRemaining))}'
                    : _fmt(now.difference(widget.startedAt)),
                style: WorkoutType.mono(
                  size: 13,
                  weight: FontWeight.w700,
                  color: resting ? tokens.accent : tokens.dim,
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
CHECK `PressableScale`'s actual API in `app/lib/widgets/pressable.dart` (it may take `onTap` or wrap a child with its own gesture handling — adapt: if it has no `onTap`, wrap with `GestureDetector(onTap: widget.onTap, child: PressableScale(child: ...))`).

- [ ] **Step 4: Dock in `app_shell.dart`**

Watch the manager and insert between the IndexedStack child and the WTabBar `Align` in the Stack (imports: `provider`, `../session/session_manager.dart`, `session_mini_bar.dart`, and `session_launcher.dart` is already imported as `launcher`):
```dart
            // Workout-in-progress mini-bar (only when the session screen is closed)
            Builder(builder: (context) {
              final manager = context.watch<SessionManager>();
              final c = manager.active;
              if (c == null || manager.screenOpen) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: 16,
                right: 16,
                bottom: 92, // sits above the WTabBar; verify visually, adjust ±8
                child: SessionMiniBar(
                  name: c.draft.name,
                  startedAt: c.draft.startedAt,
                  restStart: c.restStart,
                  restTotal: c.restTotal,
                  onTap: () => launcher.openActiveSession(context, manager),
                ),
              );
            }),
```

- [ ] **Step 5: Verify** — `make -C app analyze` clean; `make -C app test` → 183 (181 + 2). Run the Linux build (`make -C app build`) as a smoke.

- [ ] **Step 6: Commit**
```bash
git add app/lib/shell/session_mini_bar.dart app/lib/shell/app_shell.dart app/test/shell/session_mini_bar_test.dart
git commit -m "feat(app): workout mini-bar — minimized session pill with elapsed and rest"
```

---

### Task 6: Accordion fix (TDD)

**Files:**
- Modify: `app/lib/session/exercise_block.dart`
- Test: `app/test/session/exercise_block_accordion_test.dart`

- [ ] **Step 1: Write the failing test**

`app/test/session/exercise_block_accordion_test.dart` — collapse survives the State being disposed and recreated (simulates scroll-out-of-cache):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/exercise_block.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/units/unit_service.dart';

void main() {
  BlockState block() {
    final exercise = Exercise(
      id: 'e1',
      name: 'Bench Press',
      slug: 'bench',
      muscleGroup: 'chest',
      compound: true,
      plateStepKg: 2.5,
      isTemplate: false,
    );
    final resolved = ResolvedSlot(
      exercise: exercise,
      workSets: 1,
      warmupSets: 0,
      repLow: 8,
      repHigh: 10,
      rirLow: 1,
      rirHigh: 2,
    );
    return BlockState(
      exercise: exercise,
      resolved: resolved,
      warmupSets: [],
      workingSets: [
        SetState(
          id: 's1',
          weightKg: 60,
          reps: 8,
          rir: 1,
          isWarmup: false,
          done: false,
        ),
      ],
      expanded: true,
    );
  }

  Widget host(BlockState b, {required bool showBlock}) => MaterialApp(
        home: Scaffold(
          body: showBlock
              ? ExerciseBlock(
                  key: const ValueKey('e1'),
                  block: b,
                  unit: UnitService(),
                  onToggleDone: (_, __) {},
                  onSetChanged: (_, __) {},
                  onAddSet: (_) {},
                  onRemoveBlock: (_) {},
                )
              : const SizedBox.shrink(),
        ),
      );

  testWidgets('collapse survives State disposal (scroll-out simulation)',
      (tester) async {
    final b = block();

    await tester.pumpWidget(host(b, showBlock: true));
    await tester.pumpAndSettle();
    // Expanded: set rows visible.
    expect(find.byType(SetRowFinderProbe), findsNothing); // placeholder, see note

    // Collapse via the header tap (the exercise name).
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(b.expanded, isFalse); // model field updated

    // Simulate scroll-out: unmount the block entirely, then remount.
    await tester.pumpWidget(host(b, showBlock: false));
    await tester.pump();
    await tester.pumpWidget(host(b, showBlock: true));
    await tester.pumpAndSettle();

    // Still collapsed after remount.
    expect(b.expanded, isFalse);
  });
}
```
NOTE for the implementer: drop the `SetRowFinderProbe` placeholder line — assert the collapsed state through `b.expanded` plus (optionally) the absence of a known expanded-only widget (e.g. `find.text('Add set')` should be absent when collapsed, present when expanded — READ `exercise_block.dart:193+` to pick a stable expanded-only finder, and assert it both before collapsing [present] and after remount [absent]). If `ExerciseBlock`'s constructor/test setup needs different model fields (check `SetState`/`ResolvedSlot` constructors in `active_session_controller.dart`/`models.dart`), adapt the FIXTURE, not the assertion logic. The test pumps may also need a `MediaQuery(disableAnimations)` wrapper if entrance animations interfere — prefer `pumpAndSettle`.

- [ ] **Step 2: Run `make -C app test` — expect FAIL** (after collapsing and remounting, the block re-renders EXPANDED because `_expanded` is local; the `b.expanded` assertion fails because the widget never writes the model field).

- [ ] **Step 3: Fix `exercise_block.dart`**
- DELETE `bool _expanded = true;` (:41).
- Add keep-alive (also stops the block's `Reveal` replaying on scroll-back):
```dart
class _ExerciseBlockState extends State<ExerciseBlock>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
```
and make `build` start with `super.build(context);`.
- Replace every `_expanded` read with `widget.block.expanded` (:80 border, :182-186 chevron, :193 gate) and the toggle (:89) with:
```dart
    onTap: () => setState(() => widget.block.expanded = !widget.block.expanded),
```
(The model field is non-final and already serialized — collapse state now survives State disposal, minimize/reopen, AND draft resume.)

- [ ] **Step 4: Run `make -C app analyze` (clean) + `make -C app test`** — expect 184 (183 + 1), incl. the existing `set_row_overflow_test`.

- [ ] **Step 5: Commit**
```bash
git add app/lib/session/exercise_block.dart app/test/session/exercise_block_accordion_test.dart
git commit -m "fix(app): exercise accordion keeps collapsed state when scrolled off-screen"
```

---

### Task 7: Verify + ship v0.7.0 (INLINE — run by the orchestrating session, not a subagent)

- [ ] `make -C app analyze` + `make -C app test` (expect ~184) + `make -C app build-apk-release` → green (release build exercises the new desugaring config).
- [ ] Final adversarial review subagent over `git diff main...background-session`: controller listener/timer lifecycle (manager listener leaks, rest-expiry timer, save debounce races vs finish/discard), notifyListeners-during-build risks (screenOpen set post-frame? mini-bar watch), draft resurrection paths (autosave after discard/finish), notification dedup + permission flow, provider availability for `openActiveSession` from the navigator-key context, accordion keep-alive memory bound (sessions have ≤ ~10 blocks).
- [ ] Merge `--no-ff` → main, push, tag `v0.7.0` → CI publishes `reps-v0.7.0.apk`. User on-device checks: minimize → tabs browse → mini-bar ticks → reopen intact; back button minimizes; notification shows/updates on rest (+30s re-targets)/clears on finish & discard; tap notification reopens; force-kill mid-workout → relaunch → mini-bar restores with correct elapsed; accordion stays closed after scrolling; discard button (trash) still confirm-gated.

### Out of scope
Foreground service; notification actions; pause semantics; iOS; widget.
