# Truthful Sync, Light Accent and Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Profile's sync label tells the truth.
- Today warns only when data is at risk.
- Accent text is readable in light mode.
- No main screen overflows or splits a word at 320/412dp × 1.0/2.0× × en/de/it.

**Architecture:**
- **Sync:** pure mappings in `sync/`, plus an app-scoped `SyncHealth` `ChangeNotifier` provided through `MultiProvider`.
- **Accent:** a computed `accentText` token, and a per-call-site split between fill and foreground.
- **Layout:**
  - bundled fonts;
  - a `FitLabel` widget;
  - targeted widget fixes;
  - a real-database screen harness that sweeps every main screen.

**Tech Stack:** Flutter (fvm 3.44.0), provider, powersync 2.2.0, google_fonts 6.x, shared_preferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-29-truthful-sync-light-accent-layout-design.md`

This plan runs on the same branch, `feat/live-loop-stability`, after the tasks of `docs/superpowers/plans/2026-09-29-live-loop-stability.md`.

## Global Constraints

- Run everything from the repo root with explicit paths. Never `cd`.
- Run tests ONLY as: `timeout 400 make -C app test TEST=<file> > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`.
  - Full suite: the same without `TEST=`, then `grep -E "All tests passed|Some tests failed" /tmp/claude-1000/lls_test.log`.
- Run `make -C app get` after editing `pubspec.yaml` or any `.arb` file.
- Commits:
  - Conventional Commits, subject line only, via `git -C /home/psy/Documents/personal/projects/workout-tracker …`.
  - No trailer lines (`Claude-Session:`, `Co-Authored-By:`).
  - No plan or task numbers in code or comments.
- Streams (app rule, see `app/CLAUDE.md`): a stream is subscribed once by its owner and cancelled in `dispose`. Widgets never re-listen a single-subscription stream.
- The data-at-risk threshold is `syncRiskAfter = Duration(days: 3)`, compared as strictly greater than.
- `accentText` must be ≥ 4.5:1 against every surface of its palette.
- `FitLabel` defaults: `maxLines = 1`, `minScale = 0.8`, step 0.05.
- `make -C app analyze` → "No issues found" at the end of every task.

## Review Focus

1. **Persisted last-sync after a restart while offline:** PowerSync may report `lastSyncedAt: null` before it connects. Today and Profile must use the last known time saved by `SyncHealth`, not claim "Not synced yet". Test in Task S2 ("a persisted last sync survives a null status").
2. **Signing out or turning sync off while the at-risk card shows:** it must disappear without a restart (`SyncHealth` listens to `SettingsService` and recomputes on auth changes). Test in Task S2 ("turning sync off recomputes").
3. **Expired and at-risk at the same time:** exactly one card shows, the expired one. Test in Task S3.
4. **Light theme + lime accent:** the lightest accent needs the most darkening. It must converge, and must not become black or change hue. Test in Task A1 ("every accent converges without going black").
5. **Very long single word at 2.0× in German:** for example "Oberschenkelrückseite" in a week-strip chip. It must shrink, then ellipsize on one line, never split. Covered by the layout sweep seeds (Task L-sweep).

---

### Task S1: Offline is a state; Profile says "Offline · synced …"

**Files:**
- Modify: `app/lib/sync/sync_status_ui.dart` (`syncDotStateFor` and its doc comment)
- Create: `app/lib/sync/sync_status_label.dart` (localized label, moved out of `profile_screen.dart`)
- Modify: `app/lib/ui/profile_screen.dart` (`_SyncStatusRight`, ~1158–1235: use the new label function; delete `_syncLabel` / `_relativeTime`)
- Modify: `app/lib/l10n/app_en.arb`, `app_it.arb`, `app_de.arb`, `app_es.arb` (add `syncOfflineSince`)
- Test: `app/test/sync/sync_status_ui_test.dart`, create `app/test/sync/sync_status_label_test.dart`

**Interfaces:**
- Produces:
  - `SyncDotState syncDotStateFor({required bool connected, required bool syncing, required bool hasError})` (new order: offline first).
  - `String syncStatusLabel(AppLocalizations l, SyncDotState state, DateTime? lastSyncedAt, DateTime now)`.

- [ ] **Step 1: Add the string**

After `"syncOffline"` in each ARB, add the key.

`app_en.arb`:

```json
  "syncOfflineSince": "Offline · synced {time}",
  "@syncOfflineSince": {"placeholders": {"time": {"type": "String"}}},
```

For the other three, add the same key and the same `@` block (copy the `@` block from en only if that file's existing keys carry them):
- `app_it.arb`: `"syncOfflineSince": "Offline · sincronizzato {time}",`
- `app_de.arb`: `"syncOfflineSince": "Offline · synchronisiert {time}",`
- `app_es.arb`: `"syncOfflineSince": "Sin conexión · sincronizado {time}",`

Run `make -C app get`.

- [ ] **Step 2: Write the failing tests**

In `app/test/sync/sync_status_ui_test.dart`, replace the `'error wins over everything'` test with:

```dart
    test('not connected is offline, even with a recorded error', () {
      expect(syncDotStateFor(connected: false, syncing: false, hasError: true),
          SyncDotState.offline);
      expect(syncDotStateFor(connected: false, syncing: true, hasError: true),
          SyncDotState.offline);
    });
    test('an error while connected is an error, even while syncing', () {
      expect(syncDotStateFor(connected: true, syncing: true, hasError: true),
          SyncDotState.error);
    });
```

Create `app/test/sync/sync_status_label_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/sync/sync_status_label.dart';
import 'package:workout_tracker/sync/sync_status_ui.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 9, 29, 12);

  test('offline with a known last sync says when', () {
    expect(syncStatusLabel(l, SyncDotState.offline, now.subtract(const Duration(hours: 3)), now),
        'Offline · synced 3h ago');
  });
  test('offline with no known sync is just Offline', () {
    expect(syncStatusLabel(l, SyncDotState.offline, null, now), 'Offline');
  });
  test('error, syncing and synced keep their labels', () {
    expect(syncStatusLabel(l, SyncDotState.error, null, now), 'Sync error');
    expect(syncStatusLabel(l, SyncDotState.syncing, null, now), 'Syncing…');
    expect(syncStatusLabel(l, SyncDotState.synced, now.subtract(const Duration(minutes: 5)), now),
        'Synced · 5m ago');
    expect(syncStatusLabel(l, SyncDotState.synced, null, now), 'Synced');
  });
}
```

- [ ] **Step 3: Run both to verify they fail**

Run: `timeout 400 make -C app test TEST=test/sync > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`
Expected:
- `sync_status_ui_test` fails: offline-with-error returns `error`.
- `sync_status_label_test` fails to compile: `sync_status_label.dart` doesn't exist.

- [ ] **Step 4: Implement**

`app/lib/sync/sync_status_ui.dart`, replace `syncDotStateFor` and its comment:

```dart
/// Maps raw connection facts to a dot state. Not connected is offline
/// whatever PowerSync recorded: a local-first app can't tell "server down"
/// from "no route to the server", and both mean the phone is offline. An
/// error only counts while connected; then syncing; then idle.
SyncDotState syncDotStateFor({
  required bool connected,
  required bool syncing,
  required bool hasError,
}) {
  if (!connected) return SyncDotState.offline;
  if (hasError) return SyncDotState.error;
  if (syncing) return SyncDotState.syncing;
  return SyncDotState.synced;
}
```

Create `app/lib/sync/sync_status_label.dart`:

```dart
import '../l10n/app_localizations.dart';
import 'sync_status_ui.dart';

/// The Profile sync row's text for [state]. Offline and synced carry the
/// last sync time when it is known.
String syncStatusLabel(
    AppLocalizations l, SyncDotState state, DateTime? lastSyncedAt, DateTime now) {
  switch (state) {
    case SyncDotState.syncing:
      return l.syncSyncing;
    case SyncDotState.error:
      return l.syncError;
    case SyncDotState.offline:
      if (lastSyncedAt == null) return l.syncOffline;
      return l.syncOfflineSince(relativeSyncTime(l, lastSyncedAt, now));
    case SyncDotState.synced:
      if (lastSyncedAt == null) return l.syncSynced;
      return l.syncSyncedAt(relativeSyncTime(l, lastSyncedAt, now));
  }
}

/// "just now" / "5m ago" / "3h ago" / "4/9" for [t].
String relativeSyncTime(AppLocalizations l, DateTime t, DateTime now) {
  final b = relativeTimeBucket(t, now);
  return switch (b.kind) {
    RelativeTimeKind.justNow => l.syncJustNow,
    RelativeTimeKind.minutes => l.syncMinutesAgo(b.value),
    RelativeTimeKind.hours => l.syncHoursAgo(b.value),
    RelativeTimeKind.date => l.syncDateShort(b.date!.day, b.date!.month),
  };
}
```

In `app/lib/ui/profile_screen.dart` `_SyncStatusRight.build`, replace `_syncLabel(l, state, s?.lastSyncedAt)` with `syncStatusLabel(l, state, s?.lastSyncedAt, DateTime.now())`. Delete the static `_syncLabel` and `_relativeTime`, and add `import '../sync/sync_status_label.dart';`. (Task S2 swaps `s?.lastSyncedAt` for `SyncHealth`'s value.)

- [ ] **Step 5: Run and verify they pass**

Run: `timeout 400 make -C app test TEST=test/sync > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log` → `All tests passed!`

- [ ] **Step 6: Analyze and commit**

`make -C app analyze` → "No issues found".

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/sync/sync_status_ui.dart app/lib/sync/sync_status_label.dart app/lib/ui/profile_screen.dart app/lib/l10n/app_en.arb app/lib/l10n/app_it.arb app/lib/l10n/app_de.arb app/lib/l10n/app_es.arb app/test/sync/sync_status_ui_test.dart app/test/sync/sync_status_label_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "fix(app): show Offline with the last sync time instead of Sync error when the server is unreachable"
```

---

### Task S2: `SyncHealth`: data-at-risk and a remembered last sync

**Files:**
- Modify: `app/lib/sync/sync_status_ui.dart` (add `syncRiskAfter`, `syncAtRisk`)
- Create: `app/lib/sync/sync_health.dart`
- Modify: `app/lib/main.dart` (create, start, provide)
- Modify: `app/lib/ui/profile_screen.dart` (`_SyncStatusRight` uses `SyncHealth.lastSyncedAt` as the fallback)
- Test: `app/test/sync/sync_status_ui_test.dart`, create `app/test/sync/sync_health_test.dart`

**Interfaces:**
- Produces:
  - `const Duration syncRiskAfter`.
  - `bool syncAtRisk({required bool signedIn, required bool syncEnabled, required bool connected, required int pendingChanges, required DateTime? lastSyncedAt, required DateTime now})`.
  - `class SyncHealth extends ChangeNotifier`, with:
    - constructor `SyncHealth({required Stream<SyncStatus> status, required SyncStatus initial, required Future<int> Function() pendingChanges, required bool Function() signedIn, required bool Function() syncEnabled, Listenable? settings, DateTime Function()? clock, Duration poll = const Duration(minutes: 5)})`;
    - `Future<void> start()`;
    - `bool get atRisk`;
    - `DateTime? get lastSyncedAt`;
    - `Future<void> recompute()`.
- Consumed by Task S3 (Today card) via `context.watch<SyncHealth>()`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/sync/sync_status_ui_test.dart` inside `main()`:

```dart
  group('syncAtRisk', () {
    final now = DateTime(2026, 9, 29, 12);
    bool risk({
      bool signedIn = true,
      bool syncEnabled = true,
      bool connected = false,
      int pending = 1,
      DateTime? last,
    }) =>
        syncAtRisk(
            signedIn: signedIn, syncEnabled: syncEnabled, connected: connected,
            pendingChanges: pending, lastSyncedAt: last, now: now);

    test('only past the threshold', () {
      expect(risk(last: now.subtract(syncRiskAfter)), isFalse);
      expect(risk(last: now.subtract(syncRiskAfter + const Duration(minutes: 1))), isTrue);
    });
    test('never synced with pending changes is at risk', () {
      expect(risk(last: null), isTrue);
    });
    test('nothing pending, connected, signed out or sync off is never at risk', () {
      final old = now.subtract(const Duration(days: 30));
      expect(risk(last: old, pending: 0), isFalse);
      expect(risk(last: old, connected: true), isFalse);
      expect(risk(last: old, signedIn: false), isFalse);
      expect(risk(last: old, syncEnabled: false), isFalse);
    });
  });
```

Create `app/test/sync/sync_health_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/sync_health.dart';

void main() {
  final now = DateTime(2026, 9, 29, 12);
  late StreamController<SyncStatus> status;
  late int pending;
  late bool syncOn;
  late ValueNotifier<int> settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    status = StreamController<SyncStatus>.broadcast();
    pending = 2;
    syncOn = true;
    settings = ValueNotifier(0);
  });
  tearDown(() => status.close());

  SyncHealth health({SyncStatus initial = const SyncStatus()}) => SyncHealth(
        status: status.stream,
        initial: initial,
        pendingChanges: () async => pending,
        signedIn: () => true,
        syncEnabled: () => syncOn,
        settings: settings,
        clock: () => now,
      );

  test('an old last sync with pending changes is at risk; a new status event recomputes', () async {
    final h = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(days: 5))));
    await h.start();
    expect(h.atRisk, isTrue);
    status.add(SyncStatus(connected: true, lastSyncedAt: now));
    await pumpEventQueue();
    expect(h.atRisk, isFalse);
    expect(h.lastSyncedAt, now);
    h.dispose();
  });

  test('a persisted last sync survives a null status', () async {
    final h1 = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(hours: 2))));
    await h1.start();
    h1.dispose();
    final h2 = health(); // after a restart, offline: PowerSync reports no time
    await h2.start();
    expect(h2.lastSyncedAt, now.subtract(const Duration(hours: 2)));
    expect(h2.atRisk, isFalse);
    h2.dispose();
  });

  test('turning sync off recomputes', () async {
    final h = health(initial: SyncStatus(lastSyncedAt: now.subtract(const Duration(days: 5))));
    await h.start();
    expect(h.atRisk, isTrue);
    syncOn = false;
    settings.value++;
    await pumpEventQueue();
    expect(h.atRisk, isFalse);
    h.dispose();
  });

  test('dispose cancels the subscription', () async {
    final h = health();
    await h.start();
    h.dispose();
    expect(status.hasListener, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `timeout 400 make -C app test TEST=test/sync > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`
Expected: compile errors, because `syncAtRisk`, `syncRiskAfter` and `sync_health.dart` don't exist.

- [ ] **Step 3: Implement the pure rule**

Append to `app/lib/sync/sync_status_ui.dart`:

```dart
/// How long local changes may wait unsynced before Today mentions it.
const Duration syncRiskAfter = Duration(days: 3);

/// Whether local changes are at risk: sync is meant to run, the phone is
/// offline, changes are waiting, and the last sync is older than
/// [syncRiskAfter] (or never happened).
bool syncAtRisk({
  required bool signedIn,
  required bool syncEnabled,
  required bool connected,
  required int pendingChanges,
  required DateTime? lastSyncedAt,
  required DateTime now,
}) {
  if (!signedIn || !syncEnabled || connected || pendingChanges <= 0) return false;
  return lastSyncedAt == null || now.difference(lastSyncedAt) > syncRiskAfter;
}
```

- [ ] **Step 4: Implement `SyncHealth`**

Create `app/lib/sync/sync_health.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_status_ui.dart';

/// App-wide sync health for Today's data-at-risk card and Profile's
/// "Offline · synced …". Owns one subscription to the PowerSync status
/// stream and remembers the last sync time itself, because PowerSync may
/// report none after a restart until it connects again.
class SyncHealth extends ChangeNotifier {
  SyncHealth({
    required Stream<SyncStatus> status,
    required SyncStatus initial,
    required Future<int> Function() pendingChanges,
    required bool Function() signedIn,
    required bool Function() syncEnabled,
    Listenable? settings,
    DateTime Function()? clock,
    Duration poll = const Duration(minutes: 5),
  })  : _statusStream = status,
        _status = initial,
        _pendingChanges = pendingChanges,
        _signedIn = signedIn,
        _syncEnabled = syncEnabled,
        _settings = settings,
        _clock = clock ?? DateTime.now,
        _poll = poll;

  static const _prefsKey = 'sync.last_synced_at_ms';

  final Stream<SyncStatus> _statusStream;
  final Future<int> Function() _pendingChanges;
  final bool Function() _signedIn;
  final bool Function() _syncEnabled;
  final Listenable? _settings;
  final DateTime Function() _clock;
  final Duration _poll;

  SyncStatus _status;
  StreamSubscription<SyncStatus>? _sub;
  Timer? _timer;
  DateTime? _saved;
  bool _atRisk = false;
  bool _disposed = false;

  bool get atRisk => _atRisk;

  /// The newest of PowerSync's time and the one remembered here.
  DateTime? get lastSyncedAt {
    final live = _status.lastSyncedAt;
    final saved = _saved;
    if (live == null) return saved;
    if (saved == null) return live;
    return live.isAfter(saved) ? live : saved;
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefsKey);
    _saved = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    _sub = _statusStream.listen((s) {
      _status = s;
      recompute();
    });
    _settings?.addListener(recompute);
    _timer = Timer.periodic(_poll, (_) => recompute());
    await recompute();
  }

  Future<void> recompute() async {
    final live = _status.lastSyncedAt;
    if (live != null && (_saved == null || live.isAfter(_saved!))) {
      _saved = live;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, live.millisecondsSinceEpoch);
    }
    final pending = await _pendingChanges();
    if (_disposed) return;
    final next = syncAtRisk(
      signedIn: _signedIn(),
      syncEnabled: _syncEnabled(),
      connected: _status.connected,
      pendingChanges: pending,
      lastSyncedAt: lastSyncedAt,
      now: _clock(),
    );
    if (next != _atRisk) {
      _atRisk = next;
      notifyListeners();
    } else if (live != null) {
      notifyListeners(); // Profile shows the new time
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _timer?.cancel();
    _settings?.removeListener(recompute);
    super.dispose();
  }
}
```

- [ ] **Step 5: Wire it in `main.dart` and Profile**

In `app/lib/main.dart`:
- Add imports: `import 'sync/sync_health.dart';` and, if it isn't there yet, `import 'package:provider/provider.dart';`.
- After `final loggedIn = await auth.load();` and the `connectSync` block, add:

```dart
  final syncHealth = SyncHealth(
    status: db.statusStream,
    initial: db.currentStatus,
    pendingChanges: pendingUploadCount,
    signedIn: () => auth.email != null,
    syncEnabled: () => settingsService.syncEnabled,
    settings: settingsService,
  );
  await syncHealth.start();
```

Thread `syncHealth` through:
- `runApp(App(... syncHealth: syncHealth))`;
- a `required this.syncHealth` constructor parameter and `final SyncHealth syncHealth;` field on `App`;
- add `ChangeNotifierProvider.value(value: widget.syncHealth),` to the `MultiProvider` providers list next to `sessionManager`.

Login and logout change `auth.email`. So wherever the app calls `auth.login`, `auth.register`, `auth.logout` or sign-out (search `app/lib` for `auth.logout(`, `auth.login(`, `auth.register(`), add `context.read<SyncHealth>().recompute();` after the awaited call. The call sites that have no `BuildContext` get the instance passed down instead.

In `app/lib/ui/profile_screen.dart` `_SyncStatusRight.build`, change the label argument to:

```dart
syncStatusLabel(l, state, s?.lastSyncedAt ?? context.read<SyncHealth>().lastSyncedAt, DateTime.now())
```

Add `import '../sync/sync_health.dart';` and `import 'package:provider/provider.dart';` if missing.

Any existing widget test that pumps `ProfileScreen` without a `SyncHealth` provider will now throw. Search `app/test` for `ProfileScreen(`. In each such test, wrap it in `ChangeNotifierProvider.value(value: SyncHealth(status: const Stream.empty(), initial: const SyncStatus(), pendingChanges: () async => 0, signedIn: () => false, syncEnabled: () => false))`. Only `_SyncStatusRight` reads it, so it isn't started.

- [ ] **Step 6: Run and verify they pass**

Run: `timeout 400 make -C app test TEST=test/sync > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log` → `All tests passed!`
Then run the full suite (the pattern in Global Constraints) → `All tests passed!`.

- [ ] **Step 7: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/sync app/lib/main.dart app/lib/ui/profile_screen.dart app/test
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "feat(app): track sync health and remember the last sync time"
```

---

### Task S3: Today's quiet data-at-risk card

**Files:**
- Create: `app/lib/widgets/sync_at_risk_card.dart`
- Modify: `app/lib/ui/today_screen.dart` (the sync-paused slot, ~288–307)
- Modify: `app/lib/l10n/app_en.arb`, `app_it.arb`, `app_de.arb`, `app_es.arb` (`todaySyncAtRisk`, `todaySyncAtRiskNever`)
- Test: create `app/test/widgets/sync_at_risk_card_test.dart`

**Interfaces:**
- Consumes: `SyncHealth` from Task S2.
- Produces: `SyncAtRiskCard({required SyncHealth health, required ValueListenable<bool> expired, required VoidCallback onTap})`. It renders `SizedBox.shrink()` unless `health.atRisk && !expired.value`.

- [ ] **Step 1: Add the strings**

`app_en.arb`:

```json
  "todaySyncAtRisk": "Not synced since {date} · changes are on this phone only",
  "@todaySyncAtRisk": {"placeholders": {"date": {"type": "String"}}},
  "todaySyncAtRiskNever": "Not synced yet · changes are on this phone only",
```

- `app_it.arb`:
  - `"todaySyncAtRisk": "Non sincronizzato dal {date} · le modifiche sono solo su questo telefono",`
  - `"todaySyncAtRiskNever": "Non ancora sincronizzato · le modifiche sono solo su questo telefono",`
- `app_de.arb`:
  - `"todaySyncAtRisk": "Nicht synchronisiert seit {date} · Änderungen nur auf diesem Telefon",`
  - `"todaySyncAtRiskNever": "Noch nicht synchronisiert · Änderungen nur auf diesem Telefon",`
- `app_es.arb`:
  - `"todaySyncAtRisk": "Sin sincronizar desde el {date} · los cambios solo están en este teléfono",`
  - `"todaySyncAtRiskNever": "Aún sin sincronizar · los cambios solo están en este teléfono",`

Run `make -C app get`.

- [ ] **Step 2: Write the failing test**

Create `app/test/widgets/sync_at_risk_card_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/sync/sync_health.dart';
import 'package:workout_tracker/widgets/sync_at_risk_card.dart';

import '../support/l10n_harness.dart';

void main() {
  final now = DateTime(2026, 9, 29, 12);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SyncHealth> health({DateTime? last, int pending = 1}) async {
    final h = SyncHealth(
      status: const Stream.empty(),
      initial: SyncStatus(lastSyncedAt: last),
      pendingChanges: () async => pending,
      signedIn: () => true,
      syncEnabled: () => true,
      clock: () => now,
    );
    await h.start();
    return h;
  }

  testWidgets('at risk: shows the date and opens Profile on tap', (tester) async {
    final h = await tester.runAsync(() => health(last: DateTime(2026, 9, 4)));
    var taps = 0;
    await tester.pumpWidget(wrapL10n(SyncAtRiskCard(
        health: h!, expired: ValueNotifier(false), onTap: () => taps++)));
    expect(find.textContaining('Not synced since'), findsOneWidget);
    expect(find.textContaining('Sep'), findsOneWidget);
    await tester.tap(find.byType(SyncAtRiskCard));
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('never synced uses the never copy', (tester) async {
    final h = await tester.runAsync(() => health(last: null));
    await tester.pumpWidget(wrapL10n(
        SyncAtRiskCard(health: h!, expired: ValueNotifier(false), onTap: () {})));
    expect(find.text('Not synced yet · changes are on this phone only'), findsOneWidget);
    h.dispose();
  });

  testWidgets('not at risk, or the session expired: nothing', (tester) async {
    final safe = await tester.runAsync(() => health(last: now, pending: 1));
    await tester.pumpWidget(wrapL10n(
        SyncAtRiskCard(health: safe!, expired: ValueNotifier(false), onTap: () {})));
    expect(find.textContaining('Not synced'), findsNothing);
    final risky = await tester.runAsync(() => health(last: null));
    await tester.pumpWidget(wrapL10n(
        SyncAtRiskCard(health: risky!, expired: ValueNotifier(true), onTap: () {})));
    expect(find.textContaining('Not synced'), findsNothing);
    safe.dispose();
    risky.dispose();
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `timeout 400 make -C app test TEST=test/widgets/sync_at_risk_card_test.dart > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`
Expected: compile error, because `sync_at_risk_card.dart` doesn't exist.

- [ ] **Step 4: Implement the card**

Create `app/lib/widgets/sync_at_risk_card.dart`:

```dart
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../sync/sync_health.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A quiet Today card shown only while local changes are at risk (see
/// [SyncHealth.atRisk]). The session-expired banner takes the slot when
/// both apply, so this renders nothing while [expired] is true.
class SyncAtRiskCard extends StatelessWidget {
  const SyncAtRiskCard({
    super.key,
    required this.health,
    required this.expired,
    required this.onTap,
  });

  final SyncHealth health;
  final ValueListenable<bool> expired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([health, expired]),
      builder: (context, _) {
        if (!health.atRisk || expired.value) return const SizedBox.shrink();
        final tokens = context.tokens;
        final l = AppLocalizations.of(context);
        final last = health.lastSyncedAt;
        final text = last == null
            ? l.todaySyncAtRiskNever
            : l.todaySyncAtRisk(
                DateFormat.MMMd(Localizations.localeOf(context).toString()).format(last));
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(
            button: true,
            label: text,
            onTap: onTap,
            excludeSemantics: true,
            child: PressableScale(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border.all(color: tokens.line),
                    borderRadius: BorderRadius.circular(AppRadius.radius),
                  ),
                  child: Row(
                    children: [
                      Icon(WIcons.cloud, size: 18, color: tokens.faint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: WorkoutType.body(size: 13, color: tokens.dim)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

Check `PressableScale`'s import path and constructor against `app/lib/widgets/sync_paused_banner.dart`, which uses it identically. Match that file if it differs.

- [ ] **Step 5: Place it on Today**

In `app/lib/ui/today_screen.dart`, directly after the `ValueListenableBuilder<bool>` that wraps `SyncPausedBanner`, add:

```dart
              SyncAtRiskCard(
                health: context.read<SyncHealth>(),
                expired: widget.auth.sessionExpired,
                onTap: widget.onOpenProfile,
              ),
```

Add the imports for `sync_at_risk_card.dart` and `sync_health.dart`, and `provider` if missing. Any existing Today widget test must now provide a `SyncHealth` too. Use the same not-started stub as in Task S2, with `pendingChanges: () async => 0`.

- [ ] **Step 6: Run and verify it passes**

Run the card test, then the full suite → `All tests passed!`.

- [ ] **Step 7: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/widgets/sync_at_risk_card.dart app/lib/ui/today_screen.dart app/lib/l10n app/test
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "feat(app): tell Today when unsynced changes are only on this phone"
```

(`app/lib/l10n` contains the gitignored generated files. `git add` on the directory only picks up the tracked `.arb` files, which is intended.)

---

### Task A1: `accentText`, a readable accent for text and thin marks

**Files:**
- Modify: `app/lib/theme/tokens.dart` (field, both factories, `copyWith`, `lerp`, new pure functions)
- Modify: `app/lib/theme/app_theme.dart` (component themes that draw the accent as foreground)
- Test: create `app/test/theme/accent_text_test.dart`

**Interfaces:**
- Produces:
  - `double contrastRatio(Color a, Color b)`.
  - `Color accentTextOn(Color accent, List<Color> surfaces, {double target = 4.5})`.
  - `WorkoutTokens.accentText`.
  - Task A2 migrates call sites to `tokens.accentText`.

- [ ] **Step 1: Write the failing test**

Create `app/test/theme/accent_text_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/tokens.dart';

void main() {
  List<Color> surfaces(WorkoutTokens t) => [t.bg, t.surface, t.surface2, t.surface3];

  test('contrastRatio matches WCAG for black on white', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
  });

  for (final accent in accents) {
    test('light: accentText ≥ 4.5:1 on every surface for $accent', () {
      final t = WorkoutTokens.light(accent);
      for (final s in surfaces(t)) {
        expect(contrastRatio(t.accentText, s), greaterThanOrEqualTo(4.5), reason: '$s');
      }
      expect(t.accent, accent, reason: 'fills keep the true accent');
    });

    test('dark: accentText is the accent and already ≥ 4.5:1 for $accent', () {
      final t = WorkoutTokens.dark(accent);
      expect(t.accentText, accent);
      for (final s in surfaces(t)) {
        expect(contrastRatio(t.accentText, s), greaterThanOrEqualTo(4.5), reason: '$s');
      }
    });
  }

  test('every accent converges without going black or shifting hue', () {
    for (final accent in accents) {
      final ink = WorkoutTokens.light(accent).accentText;
      final a = HSLColor.fromColor(accent), b = HSLColor.fromColor(ink);
      expect(b.lightness, greaterThan(0.1), reason: '$accent');
      expect((a.hue - b.hue).abs(), lessThan(1), reason: '$accent');
    }
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `timeout 400 make -C app test TEST=test/theme/accent_text_test.dart > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`
Expected: compile errors, because `contrastRatio`, `accentText` and `accentTextOn` don't exist.

- [ ] **Step 3: Implement the token**

In `app/lib/theme/tokens.dart`, add above `class WorkoutTokens`:

```dart
double _luminance(Color c) => c.computeLuminance();

/// WCAG 2 contrast ratio between two opaque colours (1–21).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [accent] darkened in HSL lightness (hue and saturation kept) until it
/// reaches [target] contrast against every colour in [surfaces]. For accent
/// used as text or a thin mark on a light surface; fills keep the accent.
Color accentTextOn(Color accent, List<Color> surfaces, {double target = 4.5}) {
  var hsl = HSLColor.fromColor(accent);
  bool ok(Color c) => surfaces.every((s) => contrastRatio(c, s) >= target);
  while (!ok(hsl.toColor()) && hsl.lightness > 0) {
    hsl = hsl.withLightness((hsl.lightness - 0.01).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}
```

Changes inside `WorkoutTokens`:
- Add `required this.accentText,` to the constructor after `accent`.
- Add the field with its comment:

```dart
  /// The accent as text, an icon or a mark ≤ 8dp on a surface: the accent
  /// itself in dark mode, a darker shade of it in light mode so it stays
  /// readable. Fills behind content use [accent].
  final Color accentText;
```

- In `WorkoutTokens.dark`, add `accentText: accent,`.
- `WorkoutTokens.light` needs its surfaces for the computation. Rewrite it as a factory body that declares the four surface constants first:

```dart
  factory WorkoutTokens.light(Color accent) {
    const bg = Color(0xFFf3f2ec);
    const surface = Color(0xFFffffff);
    const surface2 = Color(0xFFf6f5ef);
    const surface3 = Color(0xFFe9e8e0);
    return WorkoutTokens(
      bg: bg,
      surface: surface,
      surface2: surface2,
      surface3: surface3,
      line: const Color(0x14000000), // rgba(0,0,0,0.08) ≈ 0x14 (20/255)
      lineStrong: const Color(0x26000000), // rgba(0,0,0,0.15) ≈ 0x26 (38/255)
      text: const Color(0xFF15150f),
      dim: const Color(0x99000000), // rgba(0,0,0,0.6) ≈ 0x99 (153/255)
      faint: const Color(0x66000000), // rgba(0,0,0,0.4) ≈ 0x66 (102/255)
      accent: accent,
      accentText: accentTextOn(accent, const [bg, surface, surface2, surface3]),
      accentInk: _accentInk,
      danger: const Color(0xFFff6b5e),
    );
  }
```

- Add `Color? accentText,` to `copyWith`, with `accentText: accentText ?? this.accentText,`.
- Add `accentText: Color.lerp(accentText, other.accentText, t)!,` to `lerp`.
- Update the extension fallback in `app_theme.dart` only if it constructs tokens by hand. It calls `WorkoutTokens.dark(...)`, so it needs no change.

In `app/lib/theme/app_theme.dart` `buildTheme`, add component themes after `colorScheme:`. They make Material widgets that draw the accent as foreground use `accentText`:

```dart
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: tokens.accentText),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accentText),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accentText,
      selectionHandleColor: tokens.accentText,
      selectionColor: tokens.accent.withValues(alpha: 0.35),
    ),
```

- [ ] **Step 4: Run and verify it passes**

Run the test → `All tests passed!`. If a dark-mode case fails (an accent under 4.5:1 on a dark surface), stop and report it. The spec assumed dark already passes, and the fix would be a palette decision.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/theme/tokens.dart app/lib/theme/app_theme.dart app/test/theme/accent_text_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "feat(app): add a readable accent shade for text and thin marks"
```

---

### Task A2: Use `accentText` wherever the accent is foreground

**Files (every change is `tokens.accent` → `tokens.accentText`, or `t.` / `widget.tokens.` likewise, at exactly these lines; line numbers are from `main` at 90c7a56, so re-locate by the quoted code if they drifted):**

| File:line | Code | Why |
|---|---|---|
| `update/update_ui.dart:185` | `valueColor: AlwaysStoppedAnimation<Color>(tokens.accent)` | progress indicator |
| `session/session_summary_screen.dart:495` | `color: highlight ? tokens.accent : tokens.text` | text |
| `shell/w_tab_bar.dart:130` | `final color = active ? tokens.accent : tokens.faint;` | active nav label + icon |
| `session/session_header.dart:164` | elapsed timer `color: tokens.accent` | text |
| `session/session_header.dart:199` | final-seconds `tokens.accent` | text |
| `session/session_header.dart:260` | `Container(color: tokens.accent)` | 3–6dp bar |
| `session/live_set_card.dart:66` | `Border.all(color: tokens.accent, width: 1.5)` | thin border |
| `session/live_set_card.dart:75` | label `color: tokens.accent` | text |
| `session/exercise_picker_sheet.dart:271` | 8dp compound dot | mark |
| `session/set_line.dart:73` | set index `tokens.accent` | text |
| `session/reorder_exercises_sheet.dart:137` | count text | text |
| `ui/today_screen.dart:761` | bolt `Icon` | icon |
| `ui/today_screen.dart:935` | eyebrow text | text |
| `ui/today_screen.dart:955` | resting text | text |
| `shell/session_indicator.dart:72` | dumbbell `Icon` | icon |
| `shell/session_indicator.dart:81` | resting text | text |
| `widgets/ruler_picker.dart:618` | `accent: tokens.accent` (centre label colour) | text |
| `widgets/ruler_picker.dart:701` | centre marker `color: tokens.accent` | 2.5dp mark |
| `ui/history_screen.dart:840`, `:848` | `_InlineAction(... color: tokens.accent)` | text + icon |
| `ui/history_screen.dart:933` | compound `dotColor` | mark |
| `ui/history_screen.dart:969` | bolt `Icon` | icon |
| `widgets/sparkline.dart:34` | `stroke ?? context.tokens.accent` (and the two doc comments at :12/:25 → `accentText`) | line |
| `widgets/line_chart.dart:214` | `accent: tokens.accent` | chart lines/dots |
| `widgets/volume_bars.dart:74` | `fillColor … tokens.accent` | thin bar |
| `widgets/progress_widgets.dart:96` | `valueColor` | text |
| `widgets/progress_widgets.dart:199` | `Icon(icon, color: tokens.accent)` | icon |
| `widgets/week_strip.dart:235` | check `Icon` on `surface3` | icon |
| `ui/exercise_sheet.dart:350`, `:427` | selected border | thin border |
| `ui/exercise_sheet.dart:356`, `:381`, `:462` | icons | icon |
| `widgets/w_dialog.dart:129` | last-action text colour | text |
| `ui/profile_screen.dart:126` | row icon (non-danger branch) | icon |
| `ui/profile_screen.dart:1085` | "Save name" text | text |
| `ui/profile_screen.dart:1181` | 7px sync dot | mark |
| `ui/progress_screen.dart:554`, `:558`, `:690` | delta text, "Choose exercise" | text |
| `ui/set_editor_sheet.dart:339`, `:347`, `:587` | icon, text, 1.5 border | foreground |
| `ui/bodyweight_view.dart:382` | good-delta text | text |
| `ui/exercise_library_tab.dart:245` | compound dot | mark |
| `ui/exercise_editor.dart:445` | bolt `Icon` on `surface3` | icon |

**These stay `tokens.accent`** (fills behind content): `session_summary_screen.dart:200,297,350,623`; `w_tab_bar.dart:187,191`; `split_card.dart:378`; `tag.dart:41`; `log_set_bar.dart:90`; `number_entry_sheet.dart:140`; `set_line.dart:175`; `plan_form.dart:150,210,274`; `today_screen.dart:671`; `add_weight_sheet.dart:424`; `exercise_block.dart:145`; `rir_picker.dart:57`; `pr_badge.dart:88,165`; `week_strip.dart:110,278`; `profile_screen.dart:1017,1114`; `bodyweight_view.dart:277`; `exercise_library_tab.dart:115`; `export_service.dart:48`.

- Test: create `app/test/theme/accent_usage_test.dart`

**Interfaces:**
- Consumes: `WorkoutTokens.accentText` (Task A1).

- [ ] **Step 1: Write the failing test**

Create `app/test/theme/accent_usage_test.dart`. It pumps two representative foreground uses in the light theme and checks their colours:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/theme/tokens.dart';
import 'package:workout_tracker/widgets/sparkline.dart';

void main() {
  testWidgets('light theme: the sparkline stroke is accentText, not the raw accent', (tester) async {
    final theme = buildTheme(Brightness.light, accents[3]);
    final t = theme.extension<WorkoutTokens>()!;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: Sparkline(values: [1, 3, 2, 4]))),
    ));
    final paint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(Sparkline), matching: find.byType(CustomPaint)).first);
    // _SparklinePainter's `stroke` field is public API on a private class;
    // a dynamic read reaches it without widening the widget's surface.
    expect((paint.painter as dynamic).stroke, t.accentText);
    expect(t.accentText, isNot(t.accent));
  });
}
```

`Sparkline({required List<double> values, Color? stroke, double width = 92, double height = 22})` paints through `_SparklinePainter`, which has a `final Color stroke`. The `MountProgress` animation must settle before the check: add `await tester.pumpAndSettle();` after `pumpWidget`.

- [ ] **Step 2: Run to verify it fails**

Expected: the stroke equals the raw `accent`.

- [ ] **Step 3: Migrate every "foreground" row of the table above**

Change `tokens.accent` to `tokens.accentText` at each foreground row. Leave every "stays" line alone. Then run:

```bash
grep -rn "\.accent\b" /home/psy/Documents/personal/projects/workout-tracker/app/lib | grep -v "accentInk\|accentText\|accents\[\|theme/tokens.dart"
```

Expected: only the "stays" lines listed above (plus `export_service.dart:48`). If a line isn't in either list (new code since this plan was written), classify it by the spec's rule and name it in the commit's task report.

- [ ] **Step 4: Run and verify**

Run the new test, then the full suite → `All tests passed!`. `make -C app analyze` → "No issues found".

- [ ] **Step 5: Commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib app/test/theme/accent_usage_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "fix(app): draw accent text and marks in the readable shade"
```

---

## Layout tasks

Order: **L1, then L2, then L3, then L4 / L5 / L6 in any order, then L7**. L4–L6 depend on L2, and L5, L6 and L7 also depend on L3.

If the accent tasks landed first, keep the token they put at a line you edit (for example `accentText` on text). The layout changes don't depend on colour.

Analyze with: `timeout 400 make -C app analyze > /tmp/claude-1000/lls_analyze.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/claude-1000/lls_analyze.log` → `No issues found!`.

Known limits:
- The Profile sync row's right slot and the live screen's header, live set card and log bar at 2.0× weren't read closely when this was written. If the L7 sweep flags them, fix them there as L7 Step 2 describes.
- The exercise-editor RIR test in L7 pins behaviour that already works, so it isn't red-then-green.

### Task L1: Bundle the three font families

**Files:**
- Create: `app/assets/google_fonts/` with 13 TTFs and `OFL.txt`
- Modify: `app/pubspec.yaml` (the `flutter:` block, last 4 lines of the file)
- Modify: `app/lib/theme/typography.dart:11-13` (doc comment)
- Create: `app/test/support/app_fonts.dart`
- Test: `app/test/theme/bundled_fonts_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<void> preloadAppFonts()` in `test/support/app_fonts.dart`, plus the constants `displayWeights`, `bodyWeights`, `monoWeights`.
- Produces asset filenames. google_fonts 6.3.3 (`lib/src/google_fonts_base.dart`, `_findFamilyWithVariantAssetPath`) matches any manifest asset whose path without `.ttf` ends with `GoogleFontsFamilyWithVariant.toApiFilenamePrefix()`, which is `'$family-${variant.toApiFilenamePart()}'`. The parts are Regular / Medium / SemiBold / Bold / ExtraBold. The family strings are `SpaceGrotesk`, `HankenGrotesk` and `JetBrainsMono` (from `part_s/h/j.g.dart`). The files are:
  - `SpaceGrotesk-Regular.ttf`, `SpaceGrotesk-Medium.ttf`, `SpaceGrotesk-SemiBold.ttf`, `SpaceGrotesk-Bold.ttf`
  - `HankenGrotesk-Regular.ttf`, `HankenGrotesk-Medium.ttf`, `HankenGrotesk-SemiBold.ttf`, `HankenGrotesk-Bold.ttf`, `HankenGrotesk-ExtraBold.ttf`
  - `JetBrainsMono-Regular.ttf`, `JetBrainsMono-Medium.ttf`, `JetBrainsMono-SemiBold.ttf`, `JetBrainsMono-Bold.ttf`
  - Suffix matching is safe: `…-ExtraBold` does not end with `HankenGrotesk-Bold`, and `…-SemiBold` does not end with `SpaceGrotesk-Bold`.

- [ ] **Step 1: Write the failing test**

`app/test/support/app_fonts.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:workout_tracker/theme/typography.dart';

/// The weights the app draws each family in (see `WorkoutType`).
const displayWeights = [
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
  FontWeight.w700,
];
const bodyWeights = [
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
  FontWeight.w700,
  FontWeight.w800,
];
const monoWeights = [
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
  FontWeight.w700,
];

/// Loads every bundled face the app draws, so a test lays out with the real
/// metrics from its first frame. Call it outside fake time: in `setUpAll`,
/// a plain `test`, or inside `tester.runAsync`.
Future<void> preloadAppFonts() async {
  for (final w in displayWeights) {
    WorkoutType.display(weight: w);
  }
  for (final w in bodyWeights) {
    WorkoutType.body(weight: w);
  }
  for (final w in monoWeights) {
    WorkoutType.mono(weight: w);
  }
  await GoogleFonts.pendingFonts();
}
```

`app/test/theme/bundled_fonts_test.dart`:
```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:workout_tracker/theme/typography.dart';

import '../support/app_fonts.dart';

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every face the app draws loads from the bundle, with no network',
      () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);
    // A face missing from assets/google_fonts/ throws here instead of
    // falling back to a fetch.
    await preloadAppFonts();
  });

  test('the bundled faces replace the test font', () async {
    await preloadAppFonts();
    // JetBrains Mono advances every glyph 0.6 em; the test font draws 1 em
    // squares.
    expect(_width('0000000000', WorkoutType.mono(size: 20)), closeTo(120, 1));
    // Space Grotesk and Hanken Grotesk are proportional: "i" is far narrower
    // than "M" (the test font draws them the same width).
    final display = WorkoutType.display(size: 20, letterSpacing: 0);
    expect(_width('iiii', display), lessThan(_width('MMMM', display) / 2));
    final body = WorkoutType.body(size: 20);
    expect(_width('iiii', body), lessThan(_width('MMMM', body) / 2));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

`timeout 400 make -C app test TEST=test/theme/bundled_fonts_test.dart > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log`

Expected: EXIT≠0. The first test fails with `Exception: GoogleFonts.config.allowRuntimeFetching is false but font SpaceGrotesk-Regular was not found in the application assets…`.

- [ ] **Step 3: Implement**

The google/fonts repo ships only variable fonts for all three families; `ofl/spacegrotesk`, `ofl/hankengrotesk` and `ofl/jetbrainsmono` contain `*[wght].ttf` and no `static/` folder. So download the exact static files that google_fonts itself would fetch. Its generated parts list a sha256 per variant, and the URL is `https://fonts.gstatic.com/s/a/<sha256>.ttf` (`GoogleFontsFile.url`). The loop below verifies every checksum. I ran the extraction and it yields 13 hashes; the files are static (no `fvar` table) with the right weight classes.

```bash
P=/home/psy/.pub-cache/hosted/pub.dev/google_fonts-6.3.3/lib/src/google_fonts_parts
D=/home/psy/Documents/personal/projects/workout-tracker/app/assets/google_fonts
mkdir -p "$D"
printf '%s\n' "s spaceGrotesk SpaceGrotesk 400,500,600,700" "h hankenGrotesk HankenGrotesk 400,500,600,700,800" "j jetBrainsMono JetBrainsMono 400,500,600,700" |
while read part fn fam weights; do
  awk -v fn="static TextStyle $fn(" -v fam="$fam" -v want=",$weights," '
    index($0, fn) {on=1}
    on && /static TextTheme/ {on=0}
    on && /fontWeight: FontWeight.w/ {match($0,/w[0-9]+/); w=substr($0,RSTART+1,3)}
    on && /fontStyle: FontStyle/ {st=($0 ~ /normal/)}
    on && /^ *\x27[0-9a-f]+\x27,/ {h=$0; gsub(/[^0-9a-f]/,"",h); if (st && index(want, "," w ",")) print fam, w, h}
  ' "$P/part_$part.g.dart"
done |
while read fam w hash; do
  case $w in 400) n=Regular;; 500) n=Medium;; 600) n=SemiBold;; 700) n=Bold;; 800) n=ExtraBold;; esac
  curl -fsSL -o "$D/$fam-$n.ttf" "https://fonts.gstatic.com/s/a/$hash.ttf"
  echo "$hash  $D/$fam-$n.ttf" | sha256sum -c -
done
for f in spacegrotesk hankengrotesk jetbrainsmono; do
  curl -fsSL "https://raw.githubusercontent.com/google/fonts/main/ofl/$f/OFL.txt"; printf '\n\n'
done > "$D/OFL.txt"
ls -la "$D"
```
Expected: 13 lines of `…: OK`, then 13 `.ttf` files (about 57–115 KB each) plus `OFL.txt`. Check the version first with `grep -A5 '^  google_fonts:' app/pubspec.lock`; it is 6.3.3 today.

`app/pubspec.yaml`: replace the last block
```yaml
flutter:
  uses-material-design: true
  # Generate AppLocalizations from lib/l10n/*.arb (config in l10n.yaml).
  generate: true
```
with
```yaml
flutter:
  uses-material-design: true
  # Generate AppLocalizations from lib/l10n/*.arb (config in l10n.yaml).
  generate: true
  # Space Grotesk / Hanken Grotesk / JetBrains Mono static TTFs (OFL, see
  # OFL.txt). Named in google_fonts' asset convention (`Family-Weight.ttf`),
  # so GoogleFonts.* loads them from the bundle with no network; runtime
  # fetching stays on as the fallback for any weight not bundled.
  assets:
    - assets/google_fonts/
```

`app/lib/theme/typography.dart:11-13`: replace
```dart
/// google_fonts fetches font files over HTTP on first use and falls back to
/// system fonts offline. GoogleFonts.xxx() returns a TextStyle synchronously,
/// so tests and analyze work without network access.
```
with
```dart
/// The faces are bundled in `assets/google_fonts/` (google_fonts' naming,
/// `Family-Weight.ttf`), so they load from the app bundle with no network —
/// the first offline run and the tests included. Runtime fetching stays on
/// as the fallback for a weight that isn't bundled. GoogleFonts.xxx() returns
/// a TextStyle synchronously; the face swaps in once its file has loaded.
```

Then run `make -C app get`.

- [ ] **Step 4: Run and verify pass**

- `timeout 400 make -C app test TEST=test/theme/bundled_fonts_test.dart > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log` → EXIT=0.
- Full suite, because widget tests now pick up real faces once they load: `timeout 400 make -C app test TEST=test > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log` → EXIT=0.

- [ ] **Step 5: Analyze and commit**

Run the analyze command above, then:
```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/assets/google_fonts app/pubspec.yaml app/lib/theme/typography.dart app/test/support/app_fonts.dart app/test/theme/bundled_fonts_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "feat(app): bundle the Space Grotesk, Hanken Grotesk and JetBrains Mono faces"
```

---

### Task L2: FitLabel and the split-word check

**Design note (differs from the brief).** `LayoutBuilder` can't answer intrinsic-size queries; it asserts. Two of the target sites sit under `IntrinsicHeight`: the Today stat row at `today_screen.dart:463` and the week strip at `week_strip.dart:57`. So FitLabel is a `RenderProxyBox` around a real `Text`:
- It decides the scale in `performLayout`, applies it to the child `RenderParagraph` inside `invokeLayoutCallback` (the same mechanism `LayoutBuilder` uses), and computes intrinsics and dry layout with its own `TextPainter`.
- Because the tree still holds a `Text`, `find.text`, semantics (the full text) and `RenderParagraph`-based checks keep working.
- `FitLabel.rich` is added for the two-style labels in History and the summary.

**Files:**
- Create: `app/lib/widgets/fit_label.dart`
- Create: `app/test/support/layout_expect.dart`
- Test: `app/test/widgets/fit_label_test.dart`, `app/test/support/layout_expect_test.dart`

**Interfaces:**
- Produces: `FitLabel(String text, {Key? key, required TextStyle style, int maxLines = 1, double minScale = 0.8, TextAlign? textAlign})`.
- Produces: `FitLabel.rich(InlineSpan span, {Key? key, TextStyle? style, int maxLines = 1, double minScale = 0.8, TextAlign? textAlign})`.
- Produces: `class RenderFitLabel extends RenderProxyBox`, with `double get appliedScale` and `bool get ellipsized`.
- Produces: `void expectNoSplitWords(WidgetTester tester, {Finder? within, String? where})` and `void expectOneLine(WidgetTester tester, Finder text)`.

- [ ] **Step 1: Write the failing tests**

`app/test/widgets/fit_label_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/fit_label.dart';

import '../support/layout_expect.dart';

const _style = TextStyle(fontSize: 20);

/// Plain host: no theme, so every width comes from the test font alone.
Widget _host(Widget child,
    {required double width, TextScaler scaler = TextScaler.noScaling}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: scaler),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: _style,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Width of [text] on one line at [scale] × the style.
double _natural(String text, {double scale = 1}) {
  final p = TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

RenderFitLabel _fit(WidgetTester tester) =>
    tester.renderObject<RenderFitLabel>(find.byType(FitLabel));

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

void main() {
  testWidgets('keeps the full size when the label fits', (tester) async {
    await tester.pumpWidget(_host(const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') + 10));
    expect(_fit(tester).appliedScale, 1.0);
    expect(_fit(tester).ellipsized, isFalse);
    expect(_paragraph(tester, 'BODYWEIGHT').textScaler, TextScaler.noScaling);
  });

  testWidgets('shrinks before it ellipsizes', (tester) async {
    await tester.pumpWidget(_host(const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.97));
    final p = _paragraph(tester, 'BODYWEIGHT');
    expect(_fit(tester).appliedScale, 0.95);
    expect(_fit(tester).ellipsized, isFalse);
    expect(p.didExceedMaxLines, isFalse);
    expect(p.textScaler.scale(20), closeTo(19, 1e-9));
  });

  testWidgets('ellipsizes on one line at minScale rather than splitting',
      (tester) async {
    await tester.pumpWidget(_host(const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.5));
    final p = _paragraph(tester, 'BODYWEIGHT');
    expect(_fit(tester).appliedScale, 0.8);
    expect(_fit(tester).ellipsized, isTrue);
    expect(p.maxLines, 1);
    expect(p.didExceedMaxLines, isTrue);
    expect(p.textScaler.scale(20), closeTo(16, 1e-9));
    expectNoSplitWords(tester);
  });

  testWidgets('wraps between words when maxLines allows it', (tester) async {
    await tester.pumpWidget(_host(
        const FitLabel('LOWER BODY', style: _style, maxLines: 2),
        width: _natural('LOWER') + 4));
    final p = _paragraph(tester, 'LOWER BODY');
    expect(_fit(tester).appliedScale, 1.0);
    expect(_fit(tester).ellipsized, isFalse);
    final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(p.size.height, greaterThan(line * 1.5)); // two lines
    expectNoSplitWords(tester);
  });

  testWidgets('shrinks a word too wide for the line even when two lines would do',
      (tester) async {
    await tester.pumpWidget(_host(
        const FitLabel('BODYWEIGHT', style: _style, maxLines: 2),
        width: _natural('BODYWEIGHT') * 0.97));
    expect(_fit(tester).appliedScale, 0.95);
    expectOneLine(tester, find.text('BODYWEIGHT'));
  });

  testWidgets('multiplies the ambient text scale instead of replacing it',
      (tester) async {
    await tester.pumpWidget(_host(const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT', scale: 2) * 0.97,
        scaler: const TextScaler.linear(2)));
    expect(_fit(tester).appliedScale, 0.95);
    expect(_paragraph(tester, 'BODYWEIGHT').textScaler.scale(20),
        closeTo(38, 1e-9));
  });

  testWidgets('keeps the full text in semantics when ellipsized',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const FitLabel('BODYWEIGHT', style: _style),
        width: _natural('BODYWEIGHT') * 0.4));
    expect(_fit(tester).ellipsized, isTrue);
    expect(find.bySemanticsLabel('BODYWEIGHT'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('answers intrinsic sizes, so it works under IntrinsicHeight',
      (tester) async {
    await tester.pumpWidget(_host(
      const IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
                child: FitLabel('LOWER BODY', style: _style, maxLines: 2)),
            Expanded(child: ColoredBox(color: Color(0xFF000000))),
          ],
        ),
      ),
      width: (_natural('LOWER') + 2) * 2,
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Row)).height,
        tester.getSize(find.text('LOWER BODY')).height);
  });

  testWidgets('re-fits when the text changes', (tester) async {
    final width = _natural('BODY') + 2;
    await tester.pumpWidget(
        _host(const FitLabel('BODY', style: _style), width: width));
    expect(_fit(tester).appliedScale, 1.0);
    await tester.pumpWidget(
        _host(const FitLabel('BODYWEIGHT', style: _style), width: width));
    expect(_fit(tester).ellipsized, isTrue);
  });

  testWidgets('FitLabel.rich fits a label of several styled runs',
      (tester) async {
    await tester.pumpWidget(_host(
      const FitLabel.rich(
        TextSpan(children: [
          TextSpan(text: 'UPPER'),
          TextSpan(
              text: ' PUSH',
              style: TextStyle(fontSize: 20, color: Color(0xFF888888))),
        ]),
        style: _style,
      ),
      width: _natural('UPPER PUSH') * 0.97,
    ));
    expect(_fit(tester).appliedScale, 0.95);
    expect(find.text('UPPER PUSH'), findsOneWidget);
  });
}
```

`app/test/support/layout_expect_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/fit_label.dart';

import 'layout_expect.dart';

const _style = TextStyle(fontSize: 20);

Widget _host(Widget child, {required double width}) => Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: _style,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  testWidgets('flags a word split across lines', (tester) async {
    await tester.pumpWidget(_host(const Text('BODYWEIGHT'), width: 40));
    expect(() => expectNoSplitWords(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('flags a number split across lines', (tester) async {
    await tester.pumpWidget(_host(const Text('1200'), width: 40));
    expect(() => expectNoSplitWords(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('passes a label that wraps between words', (tester) async {
    await tester.pumpWidget(_host(const Text('LOWER BODY'), width: 110));
    expectNoSplitWords(tester);
  });

  testWidgets('passes the same word in a FitLabel', (tester) async {
    await tester.pumpWidget(
        _host(const FitLabel('BODYWEIGHT', style: _style), width: 40));
    expectNoSplitWords(tester);
  });

  testWidgets('within limits the check to the matched subtree',
      (tester) async {
    await tester.pumpWidget(_host(
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BODYWEIGHT'),
          FitLabel('LOWER BODY', style: _style),
        ],
      ),
      width: 40,
    ));
    expectNoSplitWords(tester, within: find.byType(FitLabel));
    expect(() => expectNoSplitWords(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('expectOneLine fails on a wrapped label', (tester) async {
    await tester.pumpWidget(_host(const Text('LOWER BODY'), width: 110));
    expect(() => expectOneLine(tester, find.text('LOWER BODY')),
        throwsA(isA<TestFailure>()));
  });
}
```
The test font draws every glyph 1 em wide, so at 20 px 'LOWER' is 100 px. A width of 110 wraps 'LOWER BODY' at the space, and a width of 40 splits 'BODYWEIGHT' every 2 characters.

- [ ] **Step 2: Run it to verify it fails**

Run the test command with `TEST=test/widgets/fit_label_test.dart`, then again with `TEST=test/support/layout_expect_test.dart`. Expected: EXIT≠0, compile errors `Target of URI doesn't exist: 'package:workout_tracker/widgets/fit_label.dart'` and `'layout_expect.dart'`.

- [ ] **Step 3: Implement**

`app/lib/widgets/fit_label.dart`:
```dart
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A label that shrinks a little, then ellipsizes — and never splits a word
/// across lines.
///
/// It lays out at the full [style]. If the text needs more than [maxLines]
/// lines, or any single word (split on whitespace) is wider than the space
/// available, it retries at smaller sizes in 0.05 steps down to [minScale].
/// If it still doesn't fit, it renders at [minScale] on one line with an
/// ellipsis: "BODYWEIGHT" becomes smaller, then "BODYWEI…", never
/// "BODYWEI/GHT".
///
/// The shrink multiplies the ambient [TextScaler], so the user's text size is
/// respected, never replaced. A real [Text] stays in the tree, so finders,
/// semantics (the full text) and selection behave as for any label.
///
/// Unlike a `LayoutBuilder` it answers intrinsic-size queries, so it works
/// under `IntrinsicHeight` (the Today stat row and the week strip).
class FitLabel extends StatelessWidget {
  const FitLabel(
    String this.text, {
    super.key,
    required TextStyle this.style,
    this.maxLines = 1,
    this.minScale = 0.8,
    this.textAlign,
  })  : span = null,
        assert(maxLines >= 1),
        assert(minScale > 0 && minScale <= 1);

  /// A label of several styled runs (e.g. a name and a dimmer focus).
  const FitLabel.rich(
    InlineSpan this.span, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.minScale = 0.8,
    this.textAlign,
  })  : text = null,
        assert(maxLines >= 1),
        assert(minScale > 0 && minScale <= 1);

  final String? text;
  final InlineSpan? span;
  final TextStyle? style;
  final int maxLines;
  final double minScale;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final ambient = MediaQuery.textScalerOf(context);
    final label = span == null
        ? Text(
            text!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textScaler: ambient,
          )
        : Text.rich(
            span!,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textScaler: ambient,
          );
    return _FitScope(
      ambient: ambient,
      maxLines: maxLines,
      minScale: minScale,
      child: label,
    );
  }
}

class _FitScope extends SingleChildRenderObjectWidget {
  const _FitScope({
    required this.ambient,
    required this.maxLines,
    required this.minScale,
    required Widget super.child,
  });

  final TextScaler ambient;
  final int maxLines;
  final double minScale;

  @override
  RenderFitLabel createRenderObject(BuildContext context) => RenderFitLabel(
        ambient: ambient,
        maxLines: maxLines,
        minScale: minScale,
      );

  @override
  void updateRenderObject(BuildContext context, RenderFitLabel renderObject) {
    renderObject
      ..ambient = ambient
      ..maxLines = maxLines
      ..minScale = minScale;
  }
}

typedef _Fit = ({TextScaler scaler, double scale, bool ellipsized});

/// Lays its [Text] child out at the largest scale, from 1.0 down to
/// [minScale] in 0.05 steps, at which the text needs at most [maxLines]
/// lines and no word is wider than the line; failing that, at [minScale] on
/// one ellipsized line.
class RenderFitLabel extends RenderProxyBox {
  RenderFitLabel({
    required TextScaler ambient,
    required int maxLines,
    required double minScale,
  })  : _ambient = ambient,
        _maxLines = maxLines,
        _minScale = minScale;

  static const double _step = 0.05;
  static const String _ellipsis = '…';

  TextScaler get ambient => _ambient;
  TextScaler _ambient;
  set ambient(TextScaler value) {
    if (value == _ambient) return;
    _ambient = value;
    markNeedsLayout();
  }

  int get maxLines => _maxLines;
  int _maxLines;
  set maxLines(int value) {
    if (value == _maxLines) return;
    _maxLines = value;
    markNeedsLayout();
  }

  double get minScale => _minScale;
  double _minScale;
  set minScale(double value) {
    if (value == _minScale) return;
    _minScale = value;
    markNeedsLayout();
  }

  /// The scale the last layout applied (1.0 = the full style).
  double get appliedScale => _appliedScale;
  double _appliedScale = 1.0;

  /// Whether the last layout fell back to one ellipsized line.
  bool get ellipsized => _ellipsized;
  bool _ellipsized = false;

  /// The label's paragraph: the child itself, or under single-child
  /// wrappers `Text` may add (e.g. a `MouseRegion` inside a `SelectionArea`).
  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node != null && node is! RenderParagraph) {
      node = node is RenderObjectWithChildMixin<RenderObject> ? node.child : null;
    }
    return node is RenderParagraph ? node : null;
  }

  TextScaler _scalerFor(double scale) =>
      scale == 1.0 ? _ambient : _MultipliedTextScaler(_ambient, scale);

  TextPainter _painter(RenderParagraph p, TextScaler scaler,
      {int? maxLines, bool ellipsis = false}) {
    return TextPainter(
      text: p.text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: ellipsis ? _ellipsis : null,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
    );
  }

  bool _fits(RenderParagraph p, TextScaler scaler, double maxWidth) {
    final wrapped = _painter(p, scaler, maxLines: _maxLines)
      ..layout(maxWidth: maxWidth);
    final exceeded = wrapped.didExceedMaxLines;
    wrapped.dispose();
    if (exceeded) return false;
    // The widest word must fit whole, or the line breaker splits it.
    final plain = p.text.toPlainText(includeSemanticsLabels: false);
    final line = _painter(p, scaler)..layout();
    try {
      for (final word in RegExp(r'\S+').allMatches(plain)) {
        final boxes = line.getBoxesForSelection(
            TextSelection(baseOffset: word.start, extentOffset: word.end));
        if (boxes.isEmpty) continue;
        final left = boxes.map((b) => b.left).reduce(math.min);
        final right = boxes.map((b) => b.right).reduce(math.max);
        if (right - left > maxWidth) return false;
      }
      return true;
    } finally {
      line.dispose();
    }
  }

  _Fit _resolve(RenderParagraph p, double maxWidth) {
    if (!maxWidth.isFinite) {
      return (scaler: _ambient, scale: 1.0, ellipsized: false);
    }
    var scale = 1.0;
    while (true) {
      final scaler = _scalerFor(scale);
      if (_fits(p, scaler, maxWidth)) {
        return (scaler: scaler, scale: scale, ellipsized: false);
      }
      if (scale <= _minScale) {
        return (scaler: scaler, scale: scale, ellipsized: true);
      }
      scale = math.max(_minScale, ((scale - _step) * 100).round() / 100);
    }
  }

  T _withFittedPainter<T>(RenderParagraph p, BoxConstraints constraints,
      T Function(TextPainter painter) read) {
    final fit = _resolve(p, constraints.maxWidth);
    final painter = _painter(p, fit.scaler,
        maxLines: fit.ellipsized ? 1 : _maxLines, ellipsis: true)
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    try {
      return read(painter);
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final p = _paragraph;
    if (p == null) return super.computeMinIntrinsicWidth(height);
    final painter = _painter(p, _scalerFor(_minScale))..layout();
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final p = _paragraph;
    if (p == null) return super.computeMaxIntrinsicWidth(height);
    final painter = _painter(p, _ambient)..layout();
    final width = painter.maxIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final p = _paragraph;
    if (p == null) return super.computeMinIntrinsicHeight(width);
    return _withFittedPainter(
        p, BoxConstraints(maxWidth: width), (painter) => painter.height);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final p = _paragraph;
    if (p == null) return super.computeMaxIntrinsicHeight(width);
    return _withFittedPainter(
        p, BoxConstraints(maxWidth: width), (painter) => painter.height);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final p = _paragraph;
    if (p == null) return super.computeDryLayout(constraints);
    return _withFittedPainter(
        p, constraints, (painter) => constraints.constrain(painter.size));
  }

  @override
  double? computeDryBaseline(
      covariant BoxConstraints constraints, TextBaseline baseline) {
    final p = _paragraph;
    if (p == null) return super.computeDryBaseline(constraints, baseline);
    return _withFittedPainter(p, constraints,
        (painter) => painter.computeDistanceToActualBaseline(baseline));
  }

  @override
  void performLayout() {
    final p = _paragraph;
    if (p != null) {
      final fit = _resolve(p, constraints.maxWidth);
      _appliedScale = fit.scale;
      _ellipsized = fit.ellipsized;
      // Mutating the child during our layout is only allowed inside a layout
      // callback — the same mechanism LayoutBuilder uses to build children.
      invokeLayoutCallback<BoxConstraints>((_) {
        p
          ..textScaler = fit.scaler
          ..maxLines = fit.ellipsized ? 1 : _maxLines;
      });
    }
    super.performLayout();
  }
}

/// The ambient [TextScaler] times a shrink factor: a fitted label still
/// follows the user's text size, including a non-linear system scaler.
class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
```

`app/test/support/layout_expect.dart`:
```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Fails if a laid-out paragraph starts a line between two letters or digits
/// — a word split across lines ("BODYWEI/GHT", "1/200"). A break at a space
/// or a hyphen passes; so does a line cut short by an ellipsis.
///
/// [within] limits the check to paragraphs under the matched widgets (and
/// must match something); [where] prefixes the failure message. Offstage
/// paragraphs (hidden IndexedStack tabs) are laid out, so they count.
void expectNoSplitWords(WidgetTester tester, {Finder? within, String? where}) {
  final prefix = where == null ? '' : '$where: ';
  if (within != null && within.evaluate().isEmpty) {
    fail('${prefix}nothing matched $within');
  }
  final texts = within == null
      ? find.byType(RichText, skipOffstage: false)
      : find.descendant(
          of: within,
          matching: find.byType(RichText, skipOffstage: false),
          matchRoot: true,
          skipOffstage: false,
        );
  final seen = <RenderParagraph>{};
  final offenders = <String>[];
  for (final element in texts.evaluate()) {
    final p = element.renderObject;
    if (p is! RenderParagraph || !seen.add(p)) continue;
    if (!p.attached || !p.hasSize || p.debugNeedsLayout) continue;
    final split = _firstSplit(p);
    if (split != null) offenders.add(split);
  }
  if (offenders.isNotEmpty) {
    fail('${prefix}words split across lines:\n  ${offenders.join('\n  ')}');
  }
}

String? _firstSplit(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  Rect? previous;
  for (var i = 0; i < text.length; i++) {
    final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    final rect = boxes.isEmpty ? null : boxes.first.toRect();
    if (i > 0 &&
        rect != null &&
        previous != null &&
        _wordChar.hasMatch(text[i - 1]) &&
        _wordChar.hasMatch(text[i]) &&
        rect.top >= previous.bottom - 0.5) {
      return '"$text" breaks inside a word: '
          '"${text.substring(0, i)}|${text.substring(i)}"';
    }
    previous = rect;
  }
  return null;
}

/// Fails unless the paragraph of [text] sits on a single line.
void expectOneLine(WidgetTester tester, Finder text) {
  final p = tester.renderObject<RenderParagraph>(text);
  final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
  expect(p.size.height, lessThan(line * 1.5),
      reason: '"${p.text.toPlainText()}" should sit on one line');
}
```
`RenderParagraph.getLineBoundary` is private (`_getLineAtOffset`), so the check compares character boxes. The next character's top at or below the previous character's bottom means a new line. This also stays correct for mixed-size spans on one line.

- [ ] **Step 4: Run and verify pass**

Run the test command for both files. Expected: EXIT=0 each time.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/widgets/fit_label.dart app/test/support/layout_expect.dart app/test/support/layout_expect_test.dart app/test/widgets/fit_label_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "feat(app): add FitLabel, a label that shrinks then ellipsizes but never splits a word"
```

---

### Task L3: Screen harness over a real database

**Files:**
- Create: `app/test/support/screen_harness.dart`. It is built from `.claude/worktrees/agent-a5aa99d5dd59988ba/app/test/critique/critique_harness.dart` and the `seedLong` in `c_d_e_tour_critique_test.dart`, minus the PNG capture, the scratchpad gfcache/`FontLoader` hacks and the MaterialIcons path.
- Test: `app/test/support/screen_harness_test.dart`

**Interfaces:**
- Consumes: `preloadAppFonts()` (L1), `expectNoSplitWords` (L2), `dbForTests` (`lib/sync/db.dart:25`), `schema` (`lib/sync/schema.dart:17`).
- Produces:
  - Name constants: `longExercise` (61 chars), `longExercise2`, `longDay` (41 chars), `longFocus`, `unscheduledLongDay`.
  - `class ScreenHarness { Future<void> open(WidgetTester, {Map<String, Object> prefs, Future<void> Function(PowerSyncDatabase) seed}); Widget wrap(Widget home, {Locale locale, List<SingleChildWidget> extra}); Future<void> unmount(WidgetTester); Future<void> close(); UnitService units; SettingsService settings; }`
  - Tester helpers: `setPhone(tester, {required double width, double height, double textScale})`, `settleReal(tester, {int ticks})`, `openTab(tester, IconData)`, `verticalScrollableIn(Finder)`, `scrollIntoView(tester, within, target)`.
  - Assertions: `expectLayoutHolds(tester, where)`, `expectLayoutHoldsWhileScrolling(tester, within, where)`.
  - Sweep inputs: `layoutConditions`, `describeCondition`, `longDraft()`, `seedLong(PowerSyncDatabase)`.

- [ ] **Step 1: Write the failing test**

`app/test/support/screen_harness_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/history_screen.dart';

import 'pump_until.dart';
import 'screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('mounts a screen with a one-shot read over the seeded database',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(
        harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
    await pumpUntilFound(tester, find.text(longExercise));
    tester.takeException(); // layout is the sweep's job; this pins the harness
    await harness.unmount(tester);
  });

  testWidgets('drives the stream-owning shell across tabs without hanging',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(harness
        .wrap(AppShell(onLogout: () async {}, auth: AuthStore())));
    await settleReal(tester);
    await openTab(tester, WIcons.history);
    expect(
        find.descendant(
            of: find.byType(HistoryScreen), matching: find.byType(SessionCard)),
        findsWidgets);
    tester.takeException();
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

`TEST=test/support/screen_harness_test.dart` → EXIT≠0, `Target of URI doesn't exist: 'screen_harness.dart'`.

- [ ] **Step 3: Implement**

`app/test/support/screen_harness.dart`:
```dart
// Mounts real screens over a real PowerSync database in widget tests.
//
// Screens that own watch-streams, or fire a one-shot read in initState, hang
// under fake time alone. Here the database opens inside `tester.runAsync`,
// frames advance with real-async ticks ([settleReal], never pumpAndSettle),
// and every test ends with [ScreenHarness.unmount] so the watch-throttle
// timers and subscriptions are released before [ScreenHarness.close].
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
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
```
The `ActiveSessionController` import is for L7's live sweep, which reuses these helpers. If analyze reports it unused here, drop it and import it in the live sweep file instead.

- [ ] **Step 4: Run and verify pass**

`TEST=test/support/screen_harness_test.dart` → EXIT=0, both tests pass and the run exits without a hang.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/test/support/screen_harness.dart app/test/support/screen_harness_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "test(app): add a screen harness that mounts real screens over a real database"
```

---

### Task L4: Today (hero card, week strip, stat tiles, sparkline, weekly volume)

**Files:**
- Modify: `app/lib/widgets/split_card.dart`:
  - `:1-12` imports
  - `:69-78` eyebrow
  - `:107-132` stats row
  - `:193-247` CustomSlide body
  - `:415-417` pager height
  - `:476-484` Start label
- Modify: `app/lib/widgets/week_strip.dart:132-171` and `:195-205`
- Modify: `app/lib/widgets/stat_tile.dart:85-96` and `:142-148`
- Modify: `app/lib/widgets/sparkline.dart` (whole file). The call site `today_screen.dart:476` passes no width and needs no change.
- Modify: `app/lib/widgets/volume_bars.dart` (build and `_VolumeRow`)
- Test: `app/test/widgets/split_card_layout_test.dart`, `app/test/widgets/today_layout_test.dart`

**Interfaces:**
- Consumes: `FitLabel`, `expectNoSplitWords`, `expectOneLine`, `preloadAppFonts`.
- Produces: `Sparkline({double? width})`, where null (the new default) fills the parent's width and falls back to 92 when unbounded. The painter no longer takes `canvasWidth`/`canvasHeight`.

- [ ] **Step 1: Write the failing tests**

`app/test/widgets/split_card_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/widgets/split_card.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';

const _nextName = 'Oberkörper Schwerpunkt Brust & Schultern';
const _longName = 'Beine und Gesäß mit Schwerpunkt Hinterseite';

final _days = [
  (
    day: DayTemplate(id: 'd1', name: _nextName,
        focus: 'Brust · Schultern · Trizeps · Vorderer Delta',
        scheduledWeekday: 0, position: 0, slots: const []),
    exerciseCount: 4,
    lastAgo: '2d ago',
  ),
  (
    day: DayTemplate(id: 'd3', name: _longName, focus: null,
        scheduledWeekday: null, position: 1, slots: const []),
    exerciseCount: 1,
    lastAgo: '—',
  ),
];

Future<void> _pump(WidgetTester tester,
    {required int page, required double width, double scale = 1.0,
    Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(width, 900),
        textScaler: TextScaler.linear(scale)),
    child: wrapL10n(
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SplitCard(days: _days, nextIndex: 0, selectedIndex: page,
              onStart: (_) {}),
        ),
      ),
      locale: locale,
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(preloadAppFonts);

  testWidgets('the Custom slide fits a 320dp card', (tester) async {
    await _pump(tester, page: 2, width: 320);
    expect(tester.takeException(), isNull);
    expectNoSplitWords(tester, within: find.byType(SplitCard));
  });

  testWidgets('a long unscheduled day keeps its eyebrow on one line (de, 412dp)',
      (tester) async {
    await _pump(tester, page: 1, width: 412, locale: const Locale('de'));
    final eyebrow = lookupAppLocalizations(const Locale('de'))
        .splitSwitchTo(_longName.toUpperCase());
    expectOneLine(tester, find.text(eyebrow));
    expect(tester.takeException(), isNull);
  });

  for (final page in [0, 2]) {
    testWidgets('slide $page holds at 320dp and 2.0x in German', (tester) async {
      await _pump(tester, page: page, width: 320, scale: 2.0,
          locale: const Locale('de'));
      expect(tester.takeException(), isNull);
      expectNoSplitWords(tester, within: find.byType(SplitCard));
    });
  }
}
```

`app/test/widgets/today_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/typography.dart';
import 'package:workout_tracker/widgets/fit_label.dart';
import 'package:workout_tracker/widgets/sparkline.dart';
import 'package:workout_tracker/widgets/stat_tile.dart';
import 'package:workout_tracker/widgets/volume_bars.dart';
import 'package:workout_tracker/widgets/week_strip.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';

Future<void> _pumpAt(WidgetTester tester, Widget child,
    {required double width, double scale = 1.0, double padding = 16}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(width, 900),
        textScaler: TextScaler.linear(scale)),
    child: wrapL10n(SingleChildScrollView(
      child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding), child: child),
    )),
  ));
  await tester.pump(const Duration(seconds: 1)); // let mount animations land
}

double _width(String text, TextStyle style) {
  final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr)
    ..layout();
  final w = p.width;
  p.dispose();
  return w;
}

void main() {
  setUpAll(preloadAppFonts);

  group('WeekStrip at 320dp and 2.0x', () {
    const days = [
      (name: 'Oberkörper Schwerpunkt Brust & Schultern', weekday: 0,
        isNext: true, done: false),
      (name: 'Pull', weekday: 2, isNext: false, done: true),
      (name: 'Legs', weekday: 4, isNext: false, done: false),
    ];
    Widget strip() =>
        WeekStrip(days: days, selectedIndex: 0, onSelect: (_) {});

    testWidgets('a long name shrinks a little or ellipsizes, never to a speck',
        (tester) async {
      await _pumpAt(tester, strip(), width: 320, scale: 2.0);
      final rect = tester.getRect(find.text(days[0].name));
      expect(rect.height, greaterThanOrEqualTo(13 * 2.0 * 0.8));
      expect(tester.takeException(), isNull);
      expectNoSplitWords(tester, within: find.byType(WeekStrip));
    });

    testWidgets('NEXT keeps its full line height', (tester) async {
      await _pumpAt(tester, strip(), width: 320, scale: 2.0);
      final next = find.text('NEXT');
      final p = tester.renderObject<RenderParagraph>(next);
      final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
      expect(tester.getSize(next).height, greaterThanOrEqualTo(line - 0.5));
    });
  });

  group('StatTile', () {
    testWidgets('tile labels never split a word at 320dp (Today row)',
        (tester) async {
      await _pumpAt(
        tester,
        const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(label: 'Bodyweight', value: '82.4',
                    unit: 'kg', spark: Sparkline(values: [82, 82.4, 82.1])),
              ),
              SizedBox(width: 10),
              Expanded(
                  child: StatTile(label: 'Sets this week', value: '12',
                      sub: '−15 vs last wk')),
              SizedBox(width: 10),
              Expanded(
                  child: StatTile(label: 'PRs this week', value: '3',
                      sub: 'last 27 Sep', fitSub: true)),
            ],
          ),
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expectNoSplitWords(tester);
    });

    testWidgets('the sub-label shrinks a little before it ellipsizes',
        (tester) async {
      const sub = '−15 vs last wk';
      final natural = _width(sub, WorkoutType.mono(size: 10.5));
      await _pumpAt(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            // 14 + 14 padding and 1 + 1 border around the text.
            width: natural * 0.92 + 30,
            child: const StatTile(label: 'Sets', value: '12', sub: sub),
          ),
        ),
        width: 412,
      );
      final p = tester.renderObject<RenderParagraph>(find.text(sub));
      expect(p.didExceedMaxLines, isFalse, reason: 'the sub-label was cut');
    });
  });

  testWidgets('the sparkline draws inside the width it is given',
      (tester) async {
    await _pumpAt(
      tester,
      const Center(
        child: SizedBox(
            width: 60, height: 22, child: Sparkline(values: [1, 3, 2])),
      ),
      width: 412,
    );
    final paint = tester.renderObject(find.descendant(
        of: find.byType(Sparkline), matching: find.byType(CustomPaint)));
    // The end dot sits at the right edge of the 60dp box, not at 92.
    expect(paint, paints..circle(x: 60.0));
  });

  testWidgets('volume counts stay whole and names aren’t cut at 2.0x (320dp)',
      (tester) async {
    await _pumpAt(
      tester,
      const VolumeBars(rows: [
        (muscle: 'Shoulders', sets: 12, target: 10),
        (muscle: 'Chest', sets: 4, target: 12),
      ]),
      width: 320,
      scale: 2.0,
      padding: 0,
    );
    expect(tester.takeException(), isNull);
    expectNoSplitWords(tester, within: find.byType(VolumeBars));
    expectOneLine(tester, find.text('12/10'));
    final name = tester.renderObject<RenderFitLabel>(find.ancestor(
        of: find.text('Shoulders'), matching: find.byType(FitLabel)));
    expect(name.ellipsized, isFalse);
  });
}
```
Unicode `’` in a test name is fine. The last test fails today at `expectNoSplitWords` (the count wraps digit by digit) before it reaches the `FitLabel` finder.

- [ ] **Step 2: Run them to verify they fail**

Run `TEST=test/widgets/split_card_layout_test.dart`, then `TEST=test/widgets/today_layout_test.dart`. Expected failures:
- Custom slide: `A RenderFlex overflowed by … pixels on the right` from `split_card.dart:231`.
- Eyebrow: `should sit on one line`.
- Both 2.0× slides: a RenderFlex overflow (pager column and stats/start rows).
- Week strip name: its height is only a few px (FittedBox).
- NEXT: its height is below the line height (clipped to 14).
- Tile labels: `"BODYWEIGHT" breaks inside a word`.
- Sub-label: `the sub-label was cut`.
- Sparkline: the circle is at `x: 92.0`.
- Volume: `"12/10" breaks inside a word`.

- [ ] **Step 3: Implement**

**`split_card.dart`**

After `import 'dashed_border.dart';` (`:11`) add `import 'fit_label.dart';`.

Replace `:69-78` (the eyebrow `Text`):
```dart
            // Eyebrow — one line: a long day name shrinks, then ellipsizes.
            FitLabel(
              eyebrow,
              style: WorkoutType.mono(
                size: 11,
                weight: FontWeight.w700,
                color: accentDim,
                letterSpacing: 11 * 0.1,
              ),
            ),
```

Replace `:107-132` (from `const SizedBox(height: 16),` through the closing `),` of the stats `Row`):
```dart
            const SizedBox(height: 16),
            // Stats row — scales down as a unit rather than overflowing a
            // narrow card at large text.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatCol(
                    value: '$exerciseCount',
                    label: l.splitExercises,
                    valueColor: accentInk,
                    labelColor: accentDim,
                  ),
                  const SizedBox(width: 18),
                  _StatCol(
                    value: l.splitEstTimeValue(est),
                    label: l.splitEstTime,
                    valueColor: accentInk,
                    labelColor: accentDim,
                  ),
                  const SizedBox(width: 18),
                  _StatCol(
                    value: lastAgo.isEmpty ? '—' : lastAgo,
                    label: l.splitLast,
                    valueColor: accentInk,
                    labelColor: accentDim,
                  ),
                ],
              ),
            ),
```

Replace the `CustomSlide.build` return (`:193-247`, `return Column(` … `);`):
```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow
        FitLabel(
          l.splitNoTemplate,
          style: WorkoutType.mono(
            size: 11,
            weight: FontWeight.w700,
            color: dimColor,
            letterSpacing: 11 * 0.1,
          ),
        ),
        const SizedBox(height: 10),
        // Name
        FitLabel(
          l.todayCustomSession,
          style: WorkoutType.display(
            size: 40,
            weight: FontWeight.w700,
            color: textColor,
            letterSpacing: 40 * -0.03,
          ),
        ),
        const SizedBox(height: 4),
        // Sub
        FitLabel(
          l.splitBuildAsYouGo,
          style: WorkoutType.display(
            size: 19,
            weight: FontWeight.w600,
            color: dimColor,
            letterSpacing: 19 * -0.025,
          ),
        ),
        const SizedBox(height: 18),
        // Hint row — the hint takes the rest of the row, two lines at most.
        Row(
          children: [
            Icon(WIcons.plus, size: 17, color: dimColor),
            const SizedBox(width: 9),
            Flexible(
              child: FitLabel(
                l.splitAddExercisesLive,
                maxLines: 2,
                style: WorkoutType.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: dimColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
```

Replace `:415-417`:
```dart
                    SizedBox(
                      // Fixed height to keep the card stable as slides
                      // scroll; the text part grows with the user's text
                      // size (180 at 1.0×) so a slide never overflows.
                      height: 32 + MediaQuery.textScalerOf(context).scale(148),
```

Replace `:476-484` (the Start label `Text(…)`):
```dart
                              Flexible(
                                child: FitLabel(
                                  btnLabel,
                                  style: WorkoutType.display(
                                    size: 17,
                                    weight: FontWeight.w700,
                                    color: btnInk,
                                    letterSpacing: 17 * 0.01,
                                  ),
                                ),
                              ),
```

**`week_strip.dart`**

Add `import '../widgets/fit_label.dart';`. Since this file is in `widgets/`, use `import 'fit_label.dart';`.

Replace `:132-171` (from `// Weekday label` through the status `SizedBox`):
```dart
              // Weekday label — a 2–3 letter code: scales down, never wraps.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  weekdayLabel,
                  maxLines: 1,
                  softWrap: false,
                  style: WorkoutType.mono(
                    size: 9.5,
                    color: filled
                        ? tokens.accentInk.withValues(alpha: 0.7)
                        : tokens.faint,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              // Day name — two lines, shrinks a little, then ellipsizes.
              FitLabel(
                day.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: WorkoutType.display(
                  size: 13,
                  weight: FontWeight.w700,
                  color: filled ? tokens.accentInk : tokens.text,
                  letterSpacing: 0,
                ),
              ),
              // Status slot — 14 tall at 1.0×, growing with the text size so
              // NEXT is never clipped.
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(14),
                child: Center(
                  child: _StatusIndicator(
                    isNext: day.isNext,
                    isDone: isDone,
                    filled: filled,
                    tokens: tokens,
                  ),
                ),
              ),
```

Replace `:196-205` (the `next` Text and `if (!isDone) return next;`):
```dart
      final next = Text(
        AppLocalizations.of(context).weekStripNext,
        maxLines: 1,
        softWrap: false,
        style: WorkoutType.mono(
          size: 9,
          weight: FontWeight.w700,
          color: filled ? tokens.accentInk : tokens.accent,
          letterSpacing: 0.06 * 9,
        ),
      );
      // One line always: a narrow chip scales it down rather than wrapping.
      if (!isDone) return FittedBox(fit: BoxFit.scaleDown, child: next);
```

**`stat_tile.dart`**

Add `import 'fit_label.dart';`.

Replace `:89-94` (the label `Text(…)` inside `Align`):
```dart
              child: FitLabel(
                label.toUpperCase(),
                style: labelStyle,
                maxLines: 2,
              ),
```

Replace `:142-148` (`else` branch `Text(sub!, …)`):
```dart
            else
              FitLabel(sub!, style: subStyle),
```

**`sparkline.dart`**: replace the whole file.
```dart
import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// A tiny polyline sparkline, ported from `ui.jsx` → `Sparkline`.
///
/// Fills the width its parent offers (92 when that is unbounded), 22 tall, so
/// in a narrow stat tile it never paints past the tile. Returns
/// [SizedBox.shrink] when fewer than 2 values are provided.
///
/// The [stroke] color defaults to `context.tokens.accent`; callers that want a
/// muted line (e.g. the bodyweight tile) pass `context.tokens.dim` explicitly.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.stroke,
    this.width,
    this.height = 22,
  });

  final List<double> values;

  /// Stroke / fill colour. Defaults to [WorkoutTokens.accent].
  final Color? stroke;

  /// A fixed width; null fills the parent's width.
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final color = stroke ?? context.tokens.accent;
    final box = SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: MountProgress(
        duration: Motion.base,
        builder: (_, t) => CustomPaint(
          painter: _SparklinePainter(
            values: values,
            stroke: color,
            progress: t,
          ),
        ),
      ),
    );
    return width == null ? LimitedBox(maxWidth: 92, child: box) : box;
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.stroke,
    this.progress = 1.0,
  });

  final List<double> values;
  final Color stroke;

  /// One-shot mount progress 0→1. Strokes the line on; the end dot appears at
  /// completion. Identical to a static render at 1.0.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final n = values.length;

    final lo = values.reduce(min);
    final hi = values.reduce(max);
    final sp = max(hi - lo, 0.001);

    double xOf(int i) => (i / (n - 1)) * w;
    double yOf(double v) => h - 2 - ((v - lo) / sp) * (h - 4);

    // Build the polyline as a Path so it can be stroked on via PathMetric.
    final linePath = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = 1; i < n; i++) {
      linePath.lineTo(xOf(i), yOf(values[i]));
    }

    final linePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw only the first `progress` fraction of the line's length. At t=1 the
    // extracted path equals the full polyline.
    for (final m in linePath.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), linePaint);
    }

    // Filled dot at the last data point — only once the line fully arrives.
    if (progress >= 1.0) {
      final dotPaint = Paint()
        ..color = stroke
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(xOf(n - 1), yOf(values[n - 1])),
        2.0,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.progress != progress || old.values != values || old.stroke != stroke;
}
```

**`volume_bars.dart`**

Add `import 'dart:math' as math;` and `import 'fit_label.dart';`.

Replace `VolumeBars.build` (`:34-55`):
```dart
  static TextStyle _countStyle(Color color) =>
      WorkoutType.mono(size: 11.5, color: color);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    // The count column fits the widest '{sets}/{target}' at the current text
    // size (38 dp at 1.0×), so a count never wraps digit by digit.
    var countWidth = 38.0;
    for (final row in rows) {
      final painter = TextPainter(
        text: TextSpan(
            text: '${row.sets}/${row.target}', style: _countStyle(tokens.text)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      countWidth = math.max(countWidth, painter.width.ceilToDouble());
      painter.dispose();
    }

    return WCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Muscle names get 74 dp at 1.0×, growing with the text size but
          // never past 38% of the row, so the bar keeps its share.
          final grown = scaler.scale(74);
          final labelWidth = constraints.hasBoundedWidth
              ? math.min(grown, constraints.maxWidth * 0.38)
              : grown;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, row) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: _VolumeRow(
                    row: row,
                    tokens: tokens,
                    index: index,
                    labelWidth: labelWidth,
                    countWidth: countWidth,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
```

In `_VolumeRow`:
- Add the constructor params `required this.labelWidth, required this.countWidth` and the fields `final double labelWidth; final double countWidth;`.
- Replace the label `SizedBox(width: 74, child: Text(…))` (`:85-96`) with:
```dart
        // Muscle label — shrinks a little, then ellipsizes.
        SizedBox(
          width: labelWidth,
          child: FitLabel(
            row.muscle,
            style: WorkoutType.body(size: 12.5, color: tokens.dim),
          ),
        ),
```
- Replace the value `SizedBox(width: 38, child: Text(…))` (`:151-162`) with:
```dart
        // '{sets}/{target}' value — as wide as the widest count, one line.
        SizedBox(
          width: countWidth,
          child: Text(
            '${row.sets}/${row.target}',
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: VolumeBars._countStyle(valueColor),
          ),
        ),
```
- Update the class doc bullets `74 px` → `74 dp at 1.0×, scaled` and `fixed width 38` → `measured width`.

- [ ] **Step 4: Run and verify pass**

- `TEST=test/widgets/split_card_layout_test.dart`, `TEST=test/widgets/today_layout_test.dart` → EXIT=0.
- Regressions: `TEST=test/widgets/today_widgets_test.dart`, `TEST=test/widgets/split_card_test.dart`, `TEST=test/widgets/sparkline_test.dart`, `TEST=test/widgets/volume_bars_test.dart` → EXIT=0.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/widgets/split_card.dart app/lib/widgets/week_strip.dart app/lib/widgets/stat_tile.dart app/lib/widgets/sparkline.dart app/lib/widgets/volume_bars.dart app/test/widgets/split_card_layout_test.dart app/test/widgets/today_layout_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "fix(app): keep Today's hero, week strip, tiles and volume rows whole at 320dp and large text"
```

---

### Task L5: Plan, History, Profile and the bottom nav

**Files:**
- Modify: `app/lib/ui/split_tab.dart:107-110`, `:157-174`
- Modify: `app/lib/ui/plan_screen.dart:333-359`
- Modify: `app/lib/ui/history_screen.dart`:
  - `:338-355` summary card
  - `:376-406` week header
  - `:482-499` date block
  - `:529-551` split label
  - `:554-584` meta row
- Modify: `app/lib/ui/profile_screen.dart:134-141`
- Modify: `app/lib/shell/w_tab_bar.dart:144-151`
- Modify: `app/test/ui/split_tab_test.dart:16`
- Test:
  - `app/test/ui/split_tab_test.dart` (add cases)
  - `app/test/shell/w_tab_bar_layout_test.dart`
  - `app/test/ui/history_layout_test.dart`
  - `app/test/ui/plan_profile_layout_test.dart`

**Interfaces:** consumes `FitLabel`, `FitLabel.rich`, `ScreenHarness` and friends, `expectNoSplitWords`, `expectOneLine`. Produces no new API.

- [ ] **Step 1: Write the failing tests**

In `app/test/ui/split_tab_test.dart`, change `:16` from `expect(find.text('Push · 7 exercises'), findsOneWidget);` to:
```dart
    expect(find.text('Push'), findsOneWidget);
    expect(find.text(' · 7 exercises'), findsOneWidget);
```
Then append these tests inside `main()`, before the final `}`. They need these imports: `import 'package:flutter/rendering.dart';`, `import '../support/app_fonts.dart';`, `import '../support/layout_expect.dart';`, and a `setUpAll(preloadAppFonts);` at the top of `main`.
```dart
  testWidgets('a long focus leaves the exercise count whole (de, 320dp)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapL10n(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SplitDayCard(
          weekday: 0,
          name: 'Pull',
          focus: 'Brust · Schultern · Trizeps · Vorderer Delta',
          exerciseCount: 4,
          onTap: () {},
        ),
      ),
      locale: const Locale('de'),
    ));
    final count = find.text(' · 4 Übungen');
    expect(count, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(count).didExceedMaxLines,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long day name never splits a word at 2.0x (de, 320dp)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 800), textScaler: TextScaler.linear(2.0)),
      child: wrapL10n(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SplitDayCard(
            weekday: 0,
            name: 'Oberkörper Schwerpunkt Brust & Schultern',
            focus: 'Brust',
            exerciseCount: 4,
            onTap: () {},
          ),
        ),
        locale: const Locale('de'),
      ),
    ));
    expect(tester.takeException(), isNull);
    expectNoSplitWords(tester, within: find.byType(SplitDayCard));
  });
```

`app/test/shell/w_tab_bar_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/w_tab_bar.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';

void main() {
  setUpAll(preloadAppFonts);

  for (final width in [320.0, 412.0]) {
    testWidgets('nav labels never split at 2.0x (${width.round()}dp)',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
            size: Size(width, 900), textScaler: const TextScaler.linear(2.0)),
        child: wrapL10n(Align(
          alignment: Alignment.bottomCenter,
          child: WTabBar(currentIndex: 1, onTab: (_) {}, onStart: () {}),
        )),
      ));
      expect(tester.takeException(), isNull);
      expectNoSplitWords(tester, within: find.byType(WTabBar));
    });
  }
}
```

`app/test/ui/history_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/util/dates.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';
import '../support/pump_until.dart';
import '../support/screen_harness.dart';

class _NoSets implements SessionRepository {
  @override
  Future<List<LoggedSet>> setsForSession(String sessionId) =>
      Future.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await preloadAppFonts();
  });

  testWidgets('a session card holds at 320dp and 2.0x (PR badge, long name)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final yesterday =
        isoDate(DateTime.now().subtract(const Duration(days: 1)));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 900), textScaler: TextScaler.linear(2.0)),
      child: wrapL10n(SingleChildScrollView(
        child: SessionCard(
          session: HistorySessionRow(
            id: 'S', date: yesterday,
            splitLabel: 'Oberkörper Schwerpunkt Brust & Schultern · Brust',
            durationMin: 71, exerciseCount: 4, prCount: 1, tonnageKg: 5000,
          ),
          catalogMap: const {},
          sessionRepo: _NoSets(),
          units: UnitService(),
        ),
      )),
    ));
    expect(tester.takeException(), isNull);
    expectNoSplitWords(tester, within: find.byType(SessionCard));
  });

  group('HistoryScreen', () {
    final harness = ScreenHarness();
    tearDown(harness.close);

    testWidgets('week header, cards and 4-week summary hold at 320dp, 2.0x',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 320, textScale: 2.0);
      await tester.pumpWidget(
          harness.wrap(const Scaffold(body: HistoryScreen())));
      await pumpUntilFound(tester, find.byType(SessionCard));
      await settleReal(tester, ticks: 5);
      expectLayoutHolds(tester, 'History 320dp 2.0x');
      await harness.unmount(tester);
    });
  });
}
```

`app/test/ui/plan_profile_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/plan_screen.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/layout_expect.dart';
import '../support/pump_until.dart';
import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('the Plan sub-tab reads "Exercises" whole at 2.0x (412dp)',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412, textScale: 2.0);
    await tester.pumpWidget(harness.wrap(const Scaffold(body: PlanScreen())));
    final label = find.text('Exercises');
    await pumpUntilFound(tester, label);
    await settleReal(tester, ticks: 5);
    expectNoSplitWords(tester, within: label);
    expectOneLine(tester, label);
    expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse);
    await harness.unmount(tester);
  });

  testWidgets('Profile row titles never split a word at 320dp',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 320);
    await tester.pumpWidget(harness.wrap(ProfileScreen(
        onClose: () {}, onLogout: () async {}, auth: AuthStore())));
    await settleReal(tester);
    final title = find.text('Compound rest');
    await scrollIntoView(tester, find.byType(ProfileScreen), title);
    expectNoSplitWords(tester, within: title);
    await harness.unmount(tester);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run each of the four files. Expected failures:
- `split_tab_test`: `' · 7 exercises'` and `' · 4 Übungen'` are not found; `"Oberkörper" breaks inside a word`.
- `w_tab_bar_layout_test`: `"Progress" breaks inside a word`.
- `history_layout_test`: the card throws `A RenderFlex overflowed` (meta row). The screen reports `History 320dp 2.0x: A RenderFlex overflowed …` (week header).
- `plan_profile_layout_test`: `"Exercises" breaks inside a word` and `"Compound rest" breaks inside a word`.

- [ ] **Step 3: Implement**

**`split_tab.dart`**: add `import '../widgets/fit_label.dart';`.

Replace `:107-110`:
```dart
    final focusText = focus?.trim() ?? '';
    // The count only (the "{focus} · " prefix stripped), localized.
    final countText = l
        .splitDayMeta('', exerciseCount)
        .replaceFirst(RegExp(r'^\s*·\s*'), '');
    final metaStyle = WorkoutType.mono(size: 11, color: tokens.faint);
```

Replace `:157-174` (the name `Text` through the meta `Text`):
```dart
                  FitLabel(
                    name,
                    maxLines: 2,
                    style: WorkoutType.body(
                      size: 15.5,
                      weight: FontWeight.w600,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // A long focus ellipsizes; the count keeps its own slot.
                  Row(
                    children: [
                      if (focusText.isNotEmpty)
                        Flexible(
                          child: Text(
                            focusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                      Text(
                        focusText.isNotEmpty ? ' · $countText' : countText,
                        maxLines: 1,
                        softWrap: false,
                        style: metaStyle,
                      ),
                    ],
                  ),
```

**`plan_screen.dart`**: add `import '../widgets/fit_label.dart';`.

In `_SegBtn` replace `:333-359`, from `child: AnimatedContainer(` through its `child: Text(…),`:
```dart
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                // 36 tall at 1.0×; grows with a large text size.
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36 * 0.6),
                  color: active ? tokens.surface3 : Colors.transparent,
                  border: Border.all(
                      color: active ? tokens.lineStrong : tokens.line),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: tokens.lineStrong,
                            blurRadius: 0,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: FitLabel(
                  label,
                  textAlign: TextAlign.center,
                  style: WorkoutType.mono(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: active ? tokens.text : tokens.faint,
                  ),
                ),
```

**`history_screen.dart`**: add `import '../widgets/fit_label.dart';`.

Replace `:338-355` (the summary card's two Texts):
```dart
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: WorkoutType.display(
                size: 23,
                weight: FontWeight.w700,
                color: tokens.text,
                letterSpacing: 23 * -0.025,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FitLabel(
            AppLocalizations.of(context).historySummarySuffix(label),
            maxLines: 2,
            style: WorkoutType.mono(
              size: 9.5,
              color: tokens.faint,
              letterSpacing: 0.07 * 9.5,
            ),
          ),
```

Replace the `_WeekHeader.build` body `:377-405`:
```dart
    final l = AppLocalizations.of(context);
    final prs = sessions.fold<int>(0, (sum, s) => sum + s.prCount);
    final countLabel = l.historyWeekSessions(sessions.length) +
        (prs > 0 ? l.sessionPrCount(prs) : '');
    final weekLabel = l.historyWeekOf(fmtDate(
      weekKey,
      Localizations.localeOf(context).toLanguageTag(),
    ).toUpperCase());
    final weekStyle = WorkoutType.mono(
      size: 11,
      weight: FontWeight.w600,
      color: tokens.faint,
      letterSpacing: 0.08 * 11,
    );
    final countStyle = WorkoutType.mono(size: 10.5, color: tokens.dim);

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          double widthOf(String text, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          // Side by side when both fit with a 12 dp gap; otherwise the count
          // drops to its own line instead of colliding with the week.
          final sideBySide = widthOf(weekLabel, weekStyle) +
                  12 +
                  widthOf(countLabel, countStyle) <=
              constraints.maxWidth;
          if (sideBySide) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(weekLabel, maxLines: 1, style: weekStyle),
                Text(countLabel, maxLines: 1, style: countStyle),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FitLabel(weekLabel, style: weekStyle, maxLines: 2),
              const SizedBox(height: 2),
              FitLabel(countLabel, style: countStyle, maxLines: 2),
            ],
          );
        },
      ),
    );
```

Replace `:482-499` (the day and month Texts of the date block):
```dart
                          // Scale down rather than wrap "28" at large text.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${date.day}',
                              maxLines: 1,
                              softWrap: false,
                              style: WorkoutType.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: tokens.text,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              monthLabel.toUpperCase(),
                              maxLines: 1,
                              softWrap: false,
                              style: WorkoutType.mono(
                                size: 9.5,
                                color: tokens.faint,
                                letterSpacing: 0.04 * 9.5,
                              ),
                            ),
                          ),
```

Replace `:529-551` (`RichText(…)` of the split label):
```dart
                            FitLabel.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: labelName,
                                    style: WorkoutType.body(
                                      size: 14.5,
                                      weight: FontWeight.w600,
                                      color: tokens.text,
                                    ),
                                  ),
                                  if (labelFocus != null)
                                    TextSpan(
                                      text: ' · $labelFocus',
                                      style: WorkoutType.body(
                                        size: 14.5,
                                        weight: FontWeight.w500,
                                        color: tokens.faint,
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 2,
                            ),
```

Replace `:553-584` (the meta `Row`):
```dart
                          // Meta — wraps to a second line instead of running
                          // under the PR badge at large text.
                          Wrap(
                            spacing: 12,
                            runSpacing: 2,
                            children: [
                              Text(
                                AppLocalizations.of(context)
                                    .historyExerciseCountShort(
                                        session.exerciseCount),
                                style: WorkoutType.mono(
                                  size: 10.5,
                                  color: tokens.faint,
                                ),
                              ),
                              if (session.durationMin != null)
                                Text(
                                  '${session.durationMin}m',
                                  style: WorkoutType.mono(
                                    size: 10.5,
                                    color: tokens.faint,
                                  ),
                                ),
                              Text(
                                localizedDaysAgo(l, session.date),
                                style: WorkoutType.mono(
                                  size: 10.5,
                                  color: tokens.faint,
                                ),
                              ),
                            ],
                          ),
```

**`profile_screen.dart`**: add `import '../widgets/fit_label.dart';`.

Replace `:134-141` (the `_Row` title `Text`):
```dart
                FitLabel(
                  title,
                  maxLines: 2,
                  style: WorkoutType.body(
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: danger ? tokens.danger : tokens.text,
                  ),
                ),
```
The subtitle at `:144-149` is already one line with an ellipsis; leave it.

**`w_tab_bar.dart`**: add `import '../widgets/fit_label.dart';`.

Replace `:144-151`:
```dart
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FitLabel(
                  label,
                  textAlign: TextAlign.center,
                  style: WorkoutType.mono(
                    size: 9.5,
                    weight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
```

- [ ] **Step 4: Run and verify pass**

- The four files → EXIT=0.
- Regressions: `TEST=test/ui/history_session_card_test.dart`, `TEST=test/widgets/tap_targets_test.dart`, `TEST=test/ui/plan_eyebrow_test.dart` → EXIT=0.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/ui/split_tab.dart app/lib/ui/plan_screen.dart app/lib/ui/history_screen.dart app/lib/ui/profile_screen.dart app/lib/shell/w_tab_bar.dart app/test/ui/split_tab_test.dart app/test/shell/w_tab_bar_layout_test.dart app/test/ui/history_layout_test.dart app/test/ui/plan_profile_layout_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "fix(app): keep Plan, History, Profile and nav labels whole at 320dp and large text"
```

---

### Task L6: The live workout badge and the post-workout summary

**Files:**
- Modify: `app/lib/session/exercise_block.dart:141-156`
- Modify: `app/lib/session/session_summary_screen.dart`:
  - `:1-16` imports
  - `:211-233` title
  - `:490-504` tile
  - `:539-546` name
- Test: `app/test/session/exercise_block_badge_test.dart`, `app/test/session/session_summary_layout_test.dart`

**Interfaces:**
- Consumes: `FitLabel`, `FitLabel.rich`, the harness, `expectOneLine`.
- Produces: the badge key `ValueKey('block-badge-${exercise.id}')`.

- [ ] **Step 1: Write the failing tests**

`app/test/session/exercise_block_badge_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/exercise_block.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/app_fonts.dart';
import '../support/l10n_harness.dart';
import '../support/layout_expect.dart';

void main() {
  setUpAll(preloadAppFonts);

  testWidgets('the completion badge fits "2/3" whole at 2.0x', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final exercise = Exercise(id: 'e1', name: 'Bench Press', slug: 'bench',
        muscleGroup: 'chest', compound: true, plateStepKg: 2.5,
        isTemplate: false);
    SetState s(String id, bool done) => SetState(id: id, weightKg: 60,
        reps: 8, rir: 1, isWarmup: false, done: done);
    final block = BlockState(
      exercise: exercise,
      resolved: ResolvedSlot(exercise: exercise, workSets: 3, warmupSets: 0,
          repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 2),
      warmupSets: [],
      workingSets: [s('s1', true), s('s2', true), s('s3', false)],
      expanded: false,
    );
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(412, 900), textScaler: TextScaler.linear(2.0)),
      child: wrapL10n(SingleChildScrollView(
        child: ExerciseBlock(
          block: block,
          unit: UnitService(),
          liveSetId: null,
          rirPromptSetId: null,
          onFocusSet: (_, __) {},
          onSetChanged: (_, __) {},
          onRir: (_, __, ___) {},
          onMarkNotDone: (_, __) {},
          onMenu: (_) {},
        ),
      )),
    ));
    final text = find.text('2/3');
    final p = tester.renderObject<RenderParagraph>(text);
    expect(p.size.width,
        greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.01),
        reason: 'the badge clips its count');
    expectOneLine(tester, text);
    final badge = tester.getSize(find.byKey(const ValueKey('block-badge-e1')));
    expect(badge.width, greaterThanOrEqualTo(40));
    expect(badge.height, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
  });
}
```

`app/test/session/session_summary_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final scale in [1.0, 2.0]) {
    testWidgets('the summary holds at 320dp and ${scale}x', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: 320, textScale: scale);
      await tester.pumpWidget(
          harness.wrap(const SessionSummaryScreen(sessionId: 's0')));
      await pumpUntilFound(tester, find.text(longExercise));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(tester,
          find.byType(SessionSummaryScreen), 'Summary 320dp ${scale}x');
      await harness.unmount(tester);
    });
  }
}
```
`find.text(longExercise)` still matches after the change, because `FitLabel` keeps a `Text`. The two top-set names are the long ones.

- [ ] **Step 2: Run them to verify they fail**

- Badge: `the badge clips its count` (paragraph width 36 < its intrinsic width).
- Summary 1.0×: `"Duration" breaks inside a word`, and/or `"Kurzhantel-Schrägbankdrücken…" breaks inside a word`.
- Summary 2.0×: the same, plus `"71m" breaks inside a word`.

- [ ] **Step 3: Implement**

**`exercise_block.dart`**

Replace `:141-156` (the badge `Container(…)`):
```dart
                  // Completion badge — sizes to its count (min 40dp), so
                  // "2/3" stays whole at large text.
                  Container(
                    key: ValueKey('block-badge-${ex.id}'),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: allDone ? tokens.accent : tokens.surface3,
                      borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
                    ),
                    alignment: Alignment.center,
                    child: allDone
                        ? Icon(Icons.check, size: 18, color: tokens.accentInk)
                        : Text(
                            '$doneWorking/${working.length}',
                            maxLines: 1,
                            softWrap: false,
                            style: WorkoutType.mono(
                                size: 13, weight: FontWeight.w700, color: tokens.dim),
                          ),
                  ),
```

**`session_summary_screen.dart`**: add `import '../widgets/fit_label.dart';` after `:15`.

Replace `:211-233` (the title `RichText`):
```dart
                    FitLabel.rich(
                      TextSpan(
                        style: WorkoutType.display(
                          size: 22,
                          weight: FontWeight.w700,
                          color: tokens.text,
                        ),
                        children: [
                          TextSpan(text: title),
                          if (focus.isNotEmpty) ...[
                            TextSpan(
                              text: ' · $focus',
                              style: WorkoutType.display(
                                size: 22,
                                weight: FontWeight.w600,
                                color: tokens.faint,
                              ),
                            ),
                          ],
                        ],
                      ),
                      maxLines: 3,
                      textAlign: TextAlign.center,
                    ),
```

Replace `:490-504` (the tile's value and label):
```dart
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: WorkoutType.display(
                  size: 20,
                  weight: FontWeight.w700,
                  color: highlight ? tokens.accent : tokens.text,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            FitLabel(
              label,
              textAlign: TextAlign.center,
              style: WorkoutType.mono(size: 9.5, color: tokens.faint),
            ),
```

Replace `:539-546` (the `Expanded` name `Text`):
```dart
            child: FitLabel(
              name,
              maxLines: 2,
              style: WorkoutType.body(
                size: 14,
                weight: FontWeight.w600,
                color: tokens.text,
              ),
            ),
```

- [ ] **Step 4: Run and verify pass**

- Both files → EXIT=0.
- Regressions: `TEST=test/session/exercise_block_accordion_test.dart`, `TEST=test/session/exercise_block_edit_test.dart`, `TEST=test/session/active_session_screen_test.dart` → EXIT=0.

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/lib/session/exercise_block.dart app/lib/session/session_summary_screen.dart app/test/session/exercise_block_badge_test.dart app/test/session/session_summary_layout_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "fix(app): keep the live completion badge and the workout summary whole at 320dp and large text"
```

---

### Task L7: Regression sweep, RIR stepper test, doc fix

**Files:**
- Create: `app/test/layout/shell_layout_test.dart`, `app/test/layout/profile_layout_test.dart`, `app/test/layout/live_layout_test.dart`, `app/test/layout/summary_layout_test.dart`. These are split out of the spec's single `screens_layout_test.dart` so each file stays well under the 400 s command timeout. There are 12 conditions per file.
- Create: `app/test/ui/exercise_editor_rir_test.dart`
- Modify: `app/AGENTS.md:60-61`. `app/CLAUDE.md` is only `@AGENTS.md`, and the root `AGENTS.md` has no such note.

**Interfaces:** consumes everything from L3; `lookupAppLocalizations` (`lib/l10n/app_localizations.dart:2211`).

- [ ] **Step 1: Write the tests**

`app/test/layout/shell_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/shell/app_shell.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/ui/plan_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';
import 'package:workout_tracker/ui/today_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('Today, Progress, History and Plan hold at $name',
        (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      final l = lookupAppLocalizations(c.locale);
      await tester.pumpWidget(harness.wrap(
          AppShell(onLogout: () async {}, auth: AuthStore()),
          locale: c.locale));
      await settleReal(tester);

      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(TodayScreen), 'Today $name');

      await openTab(tester, WIcons.chart);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProgressScreen), 'Progress $name');

      await openTab(tester, WIcons.history);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(HistoryScreen), 'History $name');
      final card = find
          .descendant(
              of: find.byType(HistoryScreen), matching: find.byType(SessionCard))
          .first;
      await tester.ensureVisible(card);
      await tester.tap(card, warnIfMissed: false);
      await settleReal(tester, ticks: 15);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(HistoryScreen), 'History expanded $name');

      await openTab(tester, WIcons.plan);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(PlanScreen), 'Plan split $name');
      for (final (label, where) in [
        (l.planTabExercises, 'Plan exercises'),
        (l.planTabTargets, 'Plan targets'),
      ]) {
        await tester.tap(find
            .descendant(of: find.byType(PlanScreen), matching: find.text(label))
            .first);
        await settleReal(tester, ticks: 15);
        await expectLayoutHoldsWhileScrolling(
            tester, find.byType(PlanScreen), '$where $name');
      }

      await harness.unmount(tester);
    });
  }
}
```

`app/test/layout/profile_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/ui/profile_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('Profile holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          ProfileScreen(onClose: () {}, onLogout: () async {}, auth: AuthStore()),
          locale: c.locale));
      await settleReal(tester);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ProfileScreen), 'Profile $name');
      await harness.unmount(tester);
    });
  }
}
```

`app/test/layout/live_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/active_session_screen.dart';

import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('the live workout holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      final controller = ActiveSessionController()..seedForTest(longDraft());
      await tester.pumpWidget(harness.wrap(
        const ActiveSessionScreen(),
        locale: c.locale,
        extra: [
          ChangeNotifierProvider<ActiveSessionController>.value(
              value: controller),
        ],
      ));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(ActiveSessionScreen), 'Live $name');
      await harness.unmount(tester);
    });
  }
}
```

`app/test/layout/summary_layout_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/session_summary_screen.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  for (final c in layoutConditions) {
    final name = describeCondition(c);
    testWidgets('the summary holds at $name', (tester) async {
      await harness.open(tester);
      setPhone(tester, width: c.width, textScale: c.textScale);
      await tester.pumpWidget(harness.wrap(
          const SessionSummaryScreen(sessionId: 's0'),
          locale: c.locale));
      await pumpUntilFound(tester, find.text(longExercise));
      await settleReal(tester, ticks: 10);
      await expectLayoutHoldsWhileScrolling(
          tester, find.byType(SessionSummaryScreen), 'Summary $name');
      await harness.unmount(tester);
    });
  }
}
```

`app/test/ui/exercise_editor_rir_test.dart`. This mirrors the assertion style of `test/ui/day_editor_slot_row_test.dart:188-212`. The seeded `ex3` ('Bench Press') has RIR 1–2.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/ui/exercise_editor.dart';
import 'package:workout_tracker/widgets/plan_form.dart';

import '../support/pump_until.dart';
import '../support/screen_harness.dart';

// Field renders its label upper-cased.
Finder _inField(String label, Finder matching) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Field)),
      matching: matching,
    );

void main() {
  final harness = ScreenHarness();
  tearDown(harness.close);

  testWidgets('RIR low and high stay ordered: each drags the other along',
      (tester) async {
    await harness.open(tester);
    setPhone(tester, width: 412);
    await tester.pumpWidget(harness.wrap(
        Scaffold(body: ExerciseEditor(id: 'ex3', onBack: () {}))));
    await pumpUntilFound(tester,
        find.descendant(of: find.byType(ExerciseEditor), matching: find.byType(ListView)));
    await scrollIntoView(
        tester, find.byType(ExerciseEditor), find.text('RIR HIGH'));

    expect(_inField('RIR LOW', find.text('1')), findsOneWidget);
    expect(_inField('RIR HIGH', find.text('2')), findsOneWidget);

    await tester.tap(_inField('RIR LOW', find.byKey(const Key('stepper-inc'))));
    await tester.pump();
    await tester.tap(_inField('RIR LOW', find.byKey(const Key('stepper-inc'))));
    await tester.pump();
    expect(_inField('RIR LOW', find.text('3')), findsOneWidget);
    expect(_inField('RIR HIGH', find.text('3')), findsOneWidget);

    await tester.tap(_inField('RIR HIGH', find.byKey(const Key('stepper-dec'))));
    await tester.pump();
    expect(_inField('RIR LOW', find.text('2')), findsOneWidget);
    expect(_inField('RIR HIGH', find.text('2')), findsOneWidget);

    await harness.unmount(tester);
  });
}
```

- [ ] **Step 2: Run them**

Run each of the five files with the test command.
- Expected: EXIT=0. The sweep runs after L4–L6. The RIR test pins existing behaviour, so it passes on its first run.
- Each sweep failure names the screen, the condition, whether it came during scrolling, and the paragraph, e.g. `Live 320dp 2.0x de, scrolled 1: words split across lines: "…"`. Such a failure is a break the critique didn't capture, most likely on the live screen's `SessionHeader`, `LiveSetCard` or `LogSetBar`, or the Progress `BigStat` labels.
- Fix each one with the same tools (`FitLabel` for labels, `Flexible`/`Wrap` for rows, `FittedBox` for short codes and numbers), in its own `fix(app): …` commit with a focused widget test. Continue only when all five files pass.

- [ ] **Step 3: Doc fix**

In `app/AGENTS.md`, replace lines 60–61 (both bullets, starting `- Mounting a screen that owns PowerSync watch-streams in a widget test leaves pending watch-throttle timers…` and `- A screen whose \`initState\` fires an unawaited one-shot database read…`) with:
```markdown
- Screens that own PowerSync watch-streams, and screens whose `initState` fires a one-shot database read, CAN be mounted in a widget test over a real database — use `test/support/screen_harness.dart`: `ScreenHarness.open` opens and seeds the DB with `dbForTests` inside `tester.runAsync`; advance frames with `settleReal` (real-async ticks), never `pumpAndSettle`; end every test body with `harness.unmount(tester)` and register `tearDown(harness.close)`, so the watch-throttle timers and subscriptions are released before the DB closes. Plain `pumpWidget` + fake time still hangs on them. `test/layout/` sweeps every main screen at {320, 412}dp × {1.0, 2.0}× × {en, de, it} with long names and fails on any overflow or word split (`expectNoSplitWords` in `test/support/layout_expect.dart`); a new label that can meet a narrow phone or large text uses `FitLabel` (`widgets/fit_label.dart`).
```

- [ ] **Step 4: Full suite**

`timeout 400 make -C app test TEST=test > /tmp/claude-1000/lls_test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/claude-1000/lls_test.log` → EXIT=0. Also check the wall time in the log; CI allows 15 min (`app-ci.yml` `timeout-minutes: 15`).

- [ ] **Step 5: Analyze and commit**

```bash
git -C /home/psy/Documents/personal/projects/workout-tracker add app/test/layout app/test/ui/exercise_editor_rir_test.dart
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "test(app): sweep every main screen for overflow and split words at 320/412dp, 1.0/2.0x, en/de/it"
git -C /home/psy/Documents/personal/projects/workout-tracker add app/AGENTS.md
git -C /home/psy/Documents/personal/projects/workout-tracker commit -m "docs(app): screens with watch-streams can be mounted via the screen harness"
```

---

