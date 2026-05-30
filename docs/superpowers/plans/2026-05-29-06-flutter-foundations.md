# Flutter Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running Flutter Linux-desktop app that logs in against the Go backend, downloads the synced exercise catalog via PowerSync, and round-trips a locally-written session+sets through `POST /sync/upload` into Postgres — proving the offline-first client foundations end-to-end.

**Architecture:** The app talks to two services: the Go API (`http://localhost:8080`) for auth + writes, and the self-hosted PowerSync service (`http://localhost:8090`) for the sync stream. `AuthStore` holds the rotating access/refresh tokens in `flutter_secure_storage`. `WorkoutConnector extends PowerSyncBackendConnector`: `fetchCredentials()` mints a PowerSync token via `/auth/powersync-token` (Bearer = ACCESS token); `uploadData()` drains the local CRUD queue and POSTs one batch to `/sync/upload` (also Bearer ACCESS token), completing the transaction on 2xx and throwing only on transient (network/5xx/401) so the SDK retries. A local PowerSync `Schema` mirrors the six synced tables. The UI in `lib/ui/` is intentionally minimal/throwaway — UX is deferred to a later design phase.

**Tech Stack:** Flutter 3.44.0 (Dart 3.12), pinned via **fvm** (`.fvmrc`); `powersync ^2.2.0` (consolidated SDK, native SQLite core via Dart build hooks); `flutter_secure_storage ^9.2.2`; `http ^1.2.2`; `path_provider` + `path`. Linux desktop is the validation target; Android is the eventual shipping target (out of scope here).

**Important context — the draft already exists.** During Plan 6 research, a subagent wrote a complete first draft of the app to disk (uncommitted): `app/lib/{main,auth/auth_store,sync/{schema,db,connector},ui/{login_screen,home_screen}}.dart` and `app/pubspec.yaml`. Ten further agents adversarially reviewed it against the live PowerSync 2.2.0 SDK source and the actual Go backend and found it **substantially correct** (right two-token flow, correct `{op,table,id,data}` batch shape, `getNextCrudTransaction` for one-tx-per-request atomicity, throw-only-on-transient, correct local schema). It has **never been compiled** (no Flutter SDK on the host until Task 7). This plan therefore **verifies and completes** that draft rather than writing it from scratch: it fixes the two known nits, reconciles the toolchain to fvm, adds the missing pieces (`.fvmrc`, `app/Makefile`, `.gitignore` entries, two unit tests, the `linux/` runner), and runs all gates.

**Drift being corrected (not asked — these are already-confirmed choices):** a research subagent wrote a root `.mise.toml` and a mise-flavoured `app/README.md`. The locked decision is **fvm** ("fvm installed"). This plan deletes `.mise.toml` and reconciles the README to fvm + the `make -C app` runbook convention.

---

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `.mise.toml` (root) | **delete** | Stray drift; conflicts with fvm. |
| `app/.fvmrc` | create | Pins Flutter `3.44.0` repo-wide (fvm reads it). |
| `.gitignore` (root) | modify | Add Flutter/fvm ignore entries; keep `pubspec.lock` committed. |
| `app/Makefile` | create | Thin fvm wrapper, mirrors `server/Makefile` house pattern. |
| `app/README.md` | modify | Reconcile to fvm + `make -C app` (currently mise + bare flutter + stale "24"). |
| `app/pubspec.yaml` | modify | Add `flutter_test` to `dev_dependencies`. |
| `app/lib/ui/home_screen.dart` | modify | Fix deprecated `ResultSet` import; reword stale "24 exercises" comment. |
| `app/lib/sync/connector.dart` | modify | Extract `buildUploadBatch` (pure) + `uploadBatch` (HTTP) so the upload path is unit-testable; no behaviour change. |
| `app/lib/sync/{schema,db}.dart`, `lib/auth/auth_store.dart`, `lib/main.dart`, `lib/ui/login_screen.dart` | keep as-is | Verified correct by review; only compiled/validated at the gates. |
| `app/test/sync/connector_test.dart` | create | Unit-tests batch serialization + upload status handling (no network). |
| `app/test/auth/auth_store_test.dart` | create | Unit-tests login/refresh rotation (no network, no real keyring). |
| `app/linux/` + `app/.metadata` + `app/analysis_options.yaml` + `app/pubspec.lock` | generate | Created by `flutter create` (Task 8); committed. |

---

## Execution notes

- **Branch first.** This work starts from uncommitted drift on `main`. Task 1 creates a feature branch; the uncommitted draft carries onto it.
- **Two execution modes.** Tasks 1–6 are pure file edits → well-suited to fresh subagents. Tasks 7 (user step), 8, 11, 12 run Flutter/Docker against the live environment → run these **inline** (the same way prior DB/Docker steps ran), not in subagents. Tasks 9–10 (write tests) can be subagents, but their red→green runs happen at Task 11 when the SDK exists.
- **Conventions:** every command runs from the repo root with explicit paths; never `cd`. `make -C app <target>` is the sanctioned way to run Flutter with the right CWD for `.fvmrc` resolution.
- **Commit messages:** Conventional Commits, standard types, subject line only (no body). No plan numbers in code/docs.

---

### Task 1: Branch, remove toolchain drift, pin Flutter via fvm

**Files:**
- Delete: `.mise.toml`
- Create: `app/.fvmrc`

- [ ] **Step 1: Create the feature branch**

Run: `git checkout -b flutter-foundations`
Expected: `Switched to a new branch 'flutter-foundations'` — the uncommitted `app/lib/`, `app/pubspec.yaml`, modified `app/README.md`, and `.mise.toml` come along.

- [ ] **Step 2: Delete the stray mise config**

Run: `git rm -f --ignore-unmatch .mise.toml 2>/dev/null; rm -f .mise.toml`
(`.mise.toml` is untracked, so `rm -f` is what actually removes it; the `git rm` is a no-op guard.)
Expected: `.mise.toml` no longer exists at repo root.

- [ ] **Step 3: Create the fvm pin**

Create `app/.fvmrc`:

```json
{
  "flutter": "3.44.0"
}
```

- [ ] **Step 4: Verify**

Run: `test ! -e .mise.toml && cat app/.fvmrc`
Expected: prints the JSON above; no error about `.mise.toml`.

- [ ] **Step 5: Commit**

```bash
git add app/.fvmrc
git commit -m "build(app): pin Flutter 3.44.0 via fvm"
```

---

### Task 2: Add Flutter/fvm ignore entries

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Append a Flutter/Dart section**

Append to `.gitignore` (root):

```gitignore

# --- Flutter / Dart (app/) ---
app/.dart_tool/
app/.fvm/
app/.flutter-plugins
app/.flutter-plugins-dependencies
# NOTE: app/build/ is already covered by the generic build/ rule above.
# NOTE: app/pubspec.lock is intentionally NOT ignored — committed for reproducible builds.
# NOTE: the local PowerSync DB lives outside the repo (app-support dir); *.db/*.sqlite already covered.
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "build(app): gitignore Flutter/fvm working dirs"
```

---

### Task 3: Add `flutter_test` to dev dependencies

**Files:**
- Modify: `app/pubspec.yaml`

The on-disk `dev_dependencies` has only `flutter_lints`; the unit tests need `flutter_test`. `http` is already a runtime dep, so `package:http/testing.dart` (MockClient) resolves without adding anything.

- [ ] **Step 1: Edit `dev_dependencies`**

Change:

```yaml
dev_dependencies:
  flutter_lints: ^5.0.0
```

to:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

- [ ] **Step 2: Commit** (`pub get` is deferred to Task 8 — no SDK yet)

```bash
git add app/pubspec.yaml
git commit -m "build(app): add flutter_test dev dependency"
```

---

### Task 4: Fix the two source nits in `home_screen.dart`

**Files:**
- Modify: `app/lib/ui/home_screen.dart`

Both are flagged by the review: a now-`@Deprecated` import (analyze would warn) and a comment hardcoding a stale exercise count (live DB has 25 template exercises, not 24).

- [ ] **Step 1: Replace the deprecated `ResultSet` import**

Change line 3:

```dart
import 'package:powersync/sqlite3_common.dart' show ResultSet;
```

to:

```dart
import 'package:sqlite3/common.dart' show ResultSet;
```

(`sqlite3` is a transitive dependency of `powersync`, so it resolves without a pubspec change.)

- [ ] **Step 2: Reword the stale comment**

Change the doc comment (around line 8–9):

```dart
/// - the list is a live db.watch() over `exercises` — it should show the 24
///   seeded template exercises once download completes (proves DOWNLOAD).
```

to:

```dart
/// - the list is a live db.watch() over `exercises` — it should populate with
///   the seeded template exercises once download completes (proves DOWNLOAD).
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/ui/home_screen.dart
git commit -m "fix(app): use non-deprecated ResultSet import; drop stale count"
```

---

### Task 5: Reconcile `app/README.md` to fvm + the runbook convention

**Files:**
- Modify: `app/README.md`

The draft README uses mise, bare `flutter` commands, and the stale "24" count. Reconcile it to fvm, the `make -C app` pattern, and repo-root explicit paths.

- [ ] **Step 1: Replace the file body**

Overwrite `app/README.md` with:

```markdown
# app/

Flutter (Dart) client for workout-tracker. Local-first: reads/writes a local
SQLite database that [PowerSync](https://www.powersync.com/) keeps in sync with
the Go API + Postgres backend. See
`docs/superpowers/specs/2026-05-24-workout-tracker-stack-design.md` for the
stack rationale.

The UI in `lib/ui/` is intentionally minimal/throwaway — UX is deferred to a
later design phase. These foundations exist to prove the sync round-trip
(download of seeded data + upload of local writes).

## Layout

- `lib/sync/schema.dart` — PowerSync local schema for the six synced tables.
- `lib/sync/db.dart` — opens the single `PowerSyncDatabase`, connect/disconnect.
- `lib/sync/connector.dart` — `PowerSyncBackendConnector`: `fetchCredentials`
  (POST `/auth/powersync-token`) and `uploadData` (POST `/sync/upload`).
- `lib/auth/auth_store.dart` — login / refresh / logout + secure token storage.
- `lib/ui/` — throwaway login + exercises-list/write screens.

## Toolchain

Flutter is pinned to 3.44.0 via [fvm](https://fvm.app) in `app/.fvmrc`. Install
the pinned SDK once (from the repo root):

```sh
make -C app install
make -C app doctor   # the Linux toolchain section should be all green
```

All Flutter/Dart commands run through `make -C app <target>`, which invokes
`fvm flutter`/`fvm dart` with the pinned SDK.

## First-time scaffold

`lib/` and `pubspec.yaml` are committed; the platform runner directory
(`linux/`) is generated once, in place (additive — it will not touch `lib/`):

```sh
make -C app scaffold-linux
make -C app get
```

## Run (Linux desktop — foundations validation target)

The backend must be up:

```sh
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
make -C app run
```

Dev credentials: `me@example.com` / `devpassword`.

- The exercises list should populate with the seeded template exercises
  (proves DOWNLOAD).
- "Log a quick session" inserts a session + two sets locally; the connector
  uploads them to `/sync/upload` → Postgres (proves UPLOAD).

## Analyze / test

```sh
make -C app analyze
make -C app test
```
```

- [ ] **Step 2: Commit**

```bash
git add app/README.md
git commit -m "docs(app): reconcile README to fvm and make runbook"
```

---

### Task 6: Add `app/Makefile` wrapping fvm

**Files:**
- Create: `app/Makefile`

Mirror `server/Makefile`'s header + target style. Invoked from repo root as `make -C app <target>` — and crucially, `make -C app` sets CWD to `app/`, so `fvm` resolves `app/.fvmrc`.

- [ ] **Step 1: Create the Makefile**

```makefile
# All targets are meant to be invoked from the repo root via `make -C app <target>`.
# Every target runs Flutter/Dart through fvm so the pinned SDK in .fvmrc is used.

FLUTTER := fvm flutter
DART := fvm dart

.PHONY: help install get scaffold-linux analyze test fmt format run doctor devices clean

help:
	@echo "Targets (run from repo root as 'make -C app <target>'):"
	@echo "  install        Install the pinned Flutter SDK (reads .fvmrc)"
	@echo "  get            flutter pub get"
	@echo "  scaffold-linux Generate the linux/ desktop runner (additive)"
	@echo "  analyze        Static analysis (flutter analyze)"
	@echo "  test           Run all Flutter tests"
	@echo "  fmt            Format Dart sources in place (dart format)"
	@echo "  format         Verify formatting, fail if changes needed (CI)"
	@echo "  run            Run on the Linux desktop target"
	@echo "  doctor         flutter doctor -v"
	@echo "  devices        List devices (expect a linux device)"
	@echo "  clean          flutter clean"

install:
	fvm install

get:
	$(FLUTTER) pub get

scaffold-linux:
	$(FLUTTER) create --platforms=linux --org io.github.psychonaut0 --project-name workout_tracker .

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

fmt:
	$(DART) format .

format:
	$(DART) format --output=none --set-exit-if-changed .

run:
	$(FLUTTER) run -d linux

doctor:
	$(FLUTTER) doctor -v

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean
```

- [ ] **Step 2: Commit**

```bash
git add app/Makefile
git commit -m "build(app): add Makefile wrapping fvm"
```

---

### Task 7: USER STEP — materialize the Flutter SDK (BLOCKING)

**This is a human step.** It downloads ~1GB SDK and may prompt; every later task is blocked on it. fvm (4.1.0) is already installed.

- [ ] **Step 1: Install the pinned SDK**

Run from repo root (in the session, prefix with `!` to run it yourself):

```sh
make -C app install
```

Expected: fvm reads `app/.fvmrc`, downloads Flutter 3.44.0 into its cache. (`make -C app` runs with CWD `app/`, so `.fvmrc` resolves.)

- [ ] **Step 2: Verify the toolchain**

```sh
make -C app doctor
```

Expected: `flutter doctor -v` shows Flutter 3.44.0 / Dart 3.12, and the **"Linux toolchain — develop for Linux desktop"** section is all green (the host already has clang/cmake/ninja/pkgconf/gtk3).

- [ ] **Step 3: If no Linux device / desktop disabled**

If `make -C app devices` shows no `linux` device, run once:

```sh
fvm flutter config --enable-linux-desktop
```

(Linux desktop is on by default in recent Flutter; this is a safety net.)

**Do not proceed until `make -C app doctor` shows the Linux toolchain green.**

---

### Task 8: Generate the Linux runner + resolve dependencies

**Files:**
- Generate: `app/linux/`, `app/.metadata`, `app/analysis_options.yaml`, `app/pubspec.lock`
- Delete (if generated): `app/test/widget_test.dart`, `app/.gitignore`

**Blocked on Task 7.** Run inline.

- [ ] **Step 1: Scaffold the Linux runner (additive)**

```sh
make -C app scaffold-linux
```

Expected: creates `app/linux/` (CMake + GTK runner), `app/.metadata`, `app/analysis_options.yaml`. It will NOT delete `lib/`, `pubspec.yaml`, or `README.md`.

- [ ] **Step 2: Verify `flutter create` did not clobber our pubspec**

Run: `git diff app/pubspec.yaml`
Expected: **no changes** to our deps. If `flutter create` re-added default deps or altered `dependencies`/`environment`, restore the Task-3 version of `app/pubspec.yaml` (keep `powersync`, `flutter_secure_storage ^9.2.2`, `http ^1.2.2`, `path_provider`, `path`, and the `flutter_test` dev dep).

- [ ] **Step 3: Remove the generated default test and duplicate gitignore**

`flutter create` generates a counter-app `test/widget_test.dart` that references a `MyApp` we don't have (it would fail analyze/test), and an `app/.gitignore` that duplicates the root one.

```sh
rm -f app/test/widget_test.dart app/.gitignore
```

- [ ] **Step 4: Resolve dependencies**

```sh
make -C app get
```

Expected: `pub get` resolves; PowerSync's native SQLite core is fetched/built via Dart build hooks. Produces `app/pubspec.lock`.

> **If the native build hook fails to download** (host blocks `pub.dev` / `FLUTTER_STORAGE_BASE_URL`), run `fvm flutter config --enable-native-assets` and retry; confirm network egress is open.

- [ ] **Step 5: Commit the generated runner + lockfile**

```bash
git add app/linux app/.metadata app/analysis_options.yaml app/pubspec.lock
git commit -m "build(app): generate Linux desktop runner and lockfile"
```

---

### Task 9: Connector upload unit test (TDD: red → refactor → green)

**Files:**
- Test: `app/test/sync/connector_test.dart`
- Modify: `app/lib/sync/connector.dart`

The current `uploadData()` inlines the batch building and HTTP handling, entangled with `database.getNextCrudTransaction()` — untestable without a live DB. We extract two seams: a pure `buildUploadBatch(List<CrudEntry>)` and a DB-free `uploadBatch(List<CrudEntry>)` that does the POST + status handling. `uploadData()` becomes a thin wrapper. This is behaviour-preserving.

- [ ] **Step 1: Write the failing test**

Create `app/test/sync/connector_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/sync/connector.dart';

/// An AuthStore already holding a known access token, backed by a MockClient
/// for /auth/login + /auth/refresh so no real socket is opened.
Future<AuthStore> _loggedInAuth(String access, String refresh) async {
  FlutterSecureStorage.setMockInitialValues({});
  final auth = AuthStore(
    client: MockClient((req) async => http.Response(
          jsonEncode({'access_token': access, 'refresh_token': refresh}),
          200,
        )),
  );
  await auth.login('me@example.com', 'devpassword');
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutConnector.buildUploadBatch', () {
    test('emits {op,table,id,data} with uppercase op and table under "table"', () {
      // NOTE: CrudEntry's positional constructor is
      //   CrudEntry(clientId, op, table, id, transactionId, opData, {previousValues, metadata}).
      // If the installed SDK differs, the red run will fail to compile here —
      // adjust the constructor call; the OUTPUT-shape assertions are the point.
      final crud = <CrudEntry>[
        CrudEntry(1, UpdateType.put, 'sessions', 'sess-1', 1,
            {'date': '2026-05-29', 'split_label': 'Quick test'}),
        CrudEntry(2, UpdateType.patch, 'sets', 'set-1', 1, {'reps': 9}),
        CrudEntry(3, UpdateType.delete, 'sets', 'set-1', 1, null),
      ];

      final batch = WorkoutConnector.buildUploadBatch(crud);

      expect(batch[0]['op'], 'PUT');
      expect(batch[1]['op'], 'PATCH');
      expect(batch[2]['op'], 'DELETE');
      // Table name travels under "table" (the connector hand-builds this key;
      // the Go handler accepts both "table" and "type").
      expect(batch[0]['table'], 'sessions');
      expect(batch[0].containsKey('type'), isFalse);
      expect(batch[0]['id'], 'sess-1');
      expect(batch[0]['data'],
          {'date': '2026-05-29', 'split_label': 'Quick test'});
      // DELETE has no opData -> data defaults to {} (never null on the wire).
      expect(batch[2]['data'], <String, dynamic>{});
    });
  });

  group('WorkoutConnector.uploadBatch', () {
    test('POSTs {"batch":...} to /sync/upload with Bearer ACCESS token; 2xx returns',
        () async {
      late http.Request captured;
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((req) async {
          captured = req;
          return http.Response('{}', 200);
        }),
      );

      await connector.uploadBatch(const []); // no throw on 2xx

      expect(captured.url.path, '/sync/upload');
      expect(captured.headers['authorization'], 'Bearer ACCESS_1');
      expect((jsonDecode(captured.body) as Map).containsKey('batch'), isTrue);
    });

    test('throws on 5xx so the SDK retries the same batch', () async {
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((_) async => http.Response('db down', 503)),
      );
      expect(() => connector.uploadBatch(const []), throwsA(isA<Exception>()));
    });

    test('throws on 401 (triggers a refresh) so the SDK retries', () async {
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      expect(() => connector.uploadBatch(const []), throwsA(isA<Exception>()));
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails (red)**

Run: `make -C app test`
Expected: compile error — `buildUploadBatch` / `uploadBatch` are not defined on `WorkoutConnector`.

- [ ] **Step 3: Refactor the connector to expose the testable seams**

Replace the `uploadData` method in `app/lib/sync/connector.dart` (lines 58–106) with:

```dart
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final tx = await database.getNextCrudTransaction();
    if (tx == null) return;
    // Throws on transient (network / 5xx / 401) -> tx is NOT completed and the
    // SDK retries the same batch. Returns normally on 2xx (or an unexpected
    // 4xx, treated as accepted) so we then clear the queue.
    await uploadBatch(tx.crud);
    await tx.complete();
  }

  /// Visible for testing: POST one batch of CRUD ops to /sync/upload with the
  /// ACCESS token. Throws ONLY on transient failures (the server always returns
  /// 2xx for bad data; a throw here would permanently block the upload queue).
  Future<void> uploadBatch(List<CrudEntry> crud) async {
    final access = await auth.ensureAccessToken();
    if (access == null) {
      // No way to authenticate right now; throw so the SDK retries later
      // (transient from the queue's perspective — nothing is dropped).
      throw Exception('no access token for upload');
    }
    final res = await _http.post(
      Uri.parse('$apiBaseUrl/sync/upload'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $access',
      },
      body: jsonEncode({'batch': buildUploadBatch(crud)}),
    );
    if (res.statusCode == 401) {
      // Access token expired mid-upload: refresh and let the SDK retry.
      await auth.refresh();
      throw Exception('upload unauthorized; refreshed, will retry');
    }
    if (res.statusCode >= 500) {
      // Transient server error: do not complete -> SDK retries the same batch.
      throw Exception('upload transient error (${res.statusCode})');
    }
    // Any 2xx (including silently-skipped bad ops) => accepted; the caller
    // completes the transaction so these ops leave the queue.
  }

  /// Visible for testing: pure CrudEntry -> wire shape. `op.toJson()` yields the
  /// uppercase "PUT"/"PATCH"/"DELETE" the Go handler switches on; the table name
  /// is sent under `table` (the handler also accepts `type`). `opData` is null
  /// for DELETE and only the changed columns for PATCH.
  static List<Map<String, dynamic>> buildUploadBatch(List<CrudEntry> crud) {
    return crud
        .map((op) => {
              'op': op.op.toJson(),
              'table': op.table,
              'id': op.id,
              'data': op.opData ?? <String, dynamic>{},
            })
        .toList();
  }
```

- [ ] **Step 4: Run it to confirm it passes (green)**

Run: `make -C app test`
Expected: all connector tests PASS. If the `CrudEntry(...)` constructor in the test failed to compile, adjust the positional args to match the installed SDK, then re-run.

- [ ] **Step 5: Commit**

```bash
git add app/lib/sync/connector.dart app/test/sync/connector_test.dart
git commit -m "test(app): unit-test connector batch upload; extract testable seams"
```

---

### Task 10: AuthStore token-rotation unit test

**Files:**
- Test: `app/test/auth/auth_store_test.dart`

`AuthStore` already injects `http.Client` and `FlutterSecureStorage`. Tests use a `MockClient` (no network) and `FlutterSecureStorage.setMockInitialValues({})` (in-memory store, no real OS keyring).

- [ ] **Step 1: Write the test**

Create `app/test/auth/auth_store_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:workout_tracker/auth/auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // In-memory secure storage so tests never touch a real OS keyring.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login stores access + refresh tokens', () async {
    final auth = AuthStore(
      client: MockClient((req) async {
        expect(req.url.path, '/auth/login');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'me@example.com');
        return http.Response(
          jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
          200,
        );
      }),
    );

    await auth.login('me@example.com', 'devpassword');

    expect(auth.accessToken, 'A1');
    // A fresh load() reads the persisted refresh token back -> "remembered".
    expect(await auth.load(), isTrue);
  });

  test('refresh rotates BOTH tokens and persists the new pair', () async {
    final auth = AuthStore(
      client: MockClient((req) async {
        if (req.url.path == '/auth/login') {
          return http.Response(
            jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
            200,
          );
        }
        // /auth/refresh — must send the current refresh token.
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'R1');
        return http.Response(
          jsonEncode({'access_token': 'A2', 'refresh_token': 'R2'}),
          200,
        );
      }),
    );

    await auth.login('me@example.com', 'devpassword');
    final fresh = await auth.refresh();

    expect(fresh, 'A2');
    expect(auth.accessToken, 'A2');
  });

  test('ensureAccessToken returns the cached token without a network call',
      () async {
    var calls = 0;
    final auth = AuthStore(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({'access_token': 'A1', 'refresh_token': 'R1'}),
          200,
        );
      }),
    );
    await auth.login('me@example.com', 'devpassword');
    final callsAfterLogin = calls;

    final token = await auth.ensureAccessToken();

    expect(token, 'A1');
    expect(calls, callsAfterLogin); // no extra round-trip when cached
  });
}
```

- [ ] **Step 2: Run it (green)**

Run: `make -C app test`
Expected: all AuthStore tests PASS. (If `setMockInitialValues` is unavailable in the installed `flutter_secure_storage`, fall back to mocking the `plugins.it_nomads.com/flutter_secure_storage` method channel via `TestDefaultBinaryMessengerBinding`.)

- [ ] **Step 3: Commit**

```bash
git add app/test/auth/auth_store_test.dart
git commit -m "test(app): unit-test AuthStore login and token rotation"
```

---

### Task 11: GATE 1 + GATE 2 — analyze clean, tests green

**Blocked on Task 7.** Run inline. This is the first time the whole `lib/` tree is compiled, so expect to fix small issues the static draft could not catch (unused imports, lints).

- [ ] **Step 1: GATE 1 — static analysis**

Run: `make -C app analyze`
Expected: **No issues found.** Fix anything reported (the deprecated import is already handled in Task 4; watch for unused imports / lint nits in the draft files).

- [ ] **Step 2: GATE 2 — unit tests**

Run: `make -C app test`
Expected: all tests in `test/sync/connector_test.dart` and `test/auth/auth_store_test.dart` PASS, with no network.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A app
git commit -m "fix(app): resolve analyzer findings for foundations"
```

(Skip the commit if analyze was already clean and no files changed.)

---

### Task 12: GATE 3 — end-to-end Linux-desktop round-trip

**Blocked on Task 7 + Task 8.** Manual, human-in-the-loop (it's a GUI app). Run inline.

- [ ] **Step 1: Bring up the backend stack**

```sh
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d
docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env ps
```

Expected: `postgres` (5433), `server` (8080), `powersync` (8090), `powersync-storage` all healthy/up.

- [ ] **Step 2: Capture the expected seeded counts (do NOT hardcode)**

```sh
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -tAc \
  "SELECT count(*) FROM exercises WHERE is_template=true;"
```

Expected: a number (currently 25). The app's rendered exercise list is compared against this live count, not a literal.

- [ ] **Step 3: Launch the app on Linux desktop**

```sh
make -C app run
```

Expected: the app window opens to the Login screen (prefilled `me@example.com` / `devpassword`).

> **Runtime risk — keyring.** `flutter_secure_storage` on Linux needs `libsecret` + a running Secret Service keyring (gnome-keyring / KWallet / keepassxc). If login throws a secure-storage error, start/unlock a keyring daemon in the session. If none is available, temporarily back `AuthStore` with an in-memory map behind the same method surface for this validation only (revert before any Android build) — note it in the commit if done.

- [ ] **Step 4: Log in and verify DOWNLOAD**

Tap **Log in**. Expected: the exercises list populates; its row count equals the Step-2 count (proves the PowerSync download path).

- [ ] **Step 5: Write locally and verify UPLOAD**

Tap **"Log a quick session"** (FAB). Expected: a snackbar confirms a queued session; the connector POSTs to `/sync/upload`.

- [ ] **Step 6: Verify the round-trip in Postgres**

```sh
docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -tAc \
  "SELECT id FROM users WHERE email='me@example.com';"

docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -c \
  "SELECT s.set_number, s.weight_kg, s.reps, s.is_warmup, s.is_top_set, s.is_pr, s.user_id
     FROM sets s
     JOIN sessions se ON se.id = s.session_id
    WHERE se.user_id = (SELECT id FROM users WHERE email='me@example.com')
      AND se.created_at = (SELECT max(created_at) FROM sessions
                            WHERE user_id = (SELECT id FROM users WHERE email='me@example.com'))
    ORDER BY s.set_number;"
```

Acceptance — the round-trip is OK if:
- two `sets` rows exist with `weight_kg` `60.00` / `80.00` and `reps` `8` / `6` as written;
- `user_id` on every set equals the dev user's UUID (server-stamped — the client never sends it);
- the heavier non-warmup set has `is_top_set = true` (server recompute ran);
- `is_pr = true` on that set (first-ever session for this exercise ⇒ PR).

- [ ] **Step 7: Record the result**

Note the outcome in the Task-13 memory update (counts observed, round-trip confirmed, any keyring workaround used).

---

### Task 13: Update memory + finish the branch

**Files:**
- Modify: the Claude Code project memory (`project_status_and_dev_setup.md`)

- [ ] **Step 1: Update the project-status memory**

Record: Flutter foundations done & merged; fvm-pinned Flutter 3.44.0; app entrypoints (`AuthStore`, `WorkoutConnector`, local `schema`, throwaway login/home); GATE results from Task 12; the keyring requirement; and the still-deferred items (below).

- [ ] **Step 2: Finish the branch**

Use **superpowers:finishing-a-development-branch**: verify tests (`make -C app test`), then present merge/PR/keep/discard options.

---

## Deferred (explicitly out of scope for foundations)

- **Real UX/screens** — log-a-set flow, trends, PR views, Rive animations (next phase: UX design brainstorm).
- **User-configurable server URL** — `apiBaseUrl` is currently a hardcoded `const` in `auth_store.dart`; the user wants it to become a settable setting. Wire this when real settings UI lands.
- **Drift read layer** — defer until reactive read queries beyond the throwaway `db.watch` are needed.
- **Android target** — `10.0.2.2` base URL remap + cleartext-traffic manifest; re-add secure storage assumptions for device.
- **Web platform** — `kIsWeb` guard for the DB-file path.
- **Proactive access-token refresh** — `ensureAccessToken()` doesn't check the 15m expiry; the 401-then-refresh paths cover it for now.

## Open questions to confirm during execution

- Keep `flutter_secure_storage ^9.2.2`, or bump to `^10.x` (current 10.3.1, rewritten ciphers/biometrics)? Recommend staying on 9.2.2 unless GATE 3 surfaces a storage problem.
- Confirm the 25 template-exercise seed count is intended (the old brief said 24) so acceptance compares against the live query, not a literal. (Already wired to a live query in Task 12.)
