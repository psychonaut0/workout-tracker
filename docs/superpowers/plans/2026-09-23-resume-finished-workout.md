# Resume a Just-Finished Workout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A workout finished by mistake can be resumed from History (same day, or within an hour of its last finish); finishing it again replaces the same session in place.

**Architecture:** `finish()` keeps a deep-copied snapshot of the draft (`FinishedSession`), which `SessionManager` adopts only after the write transaction commits and persists to a one-slot JSON file. Resume rebuilds the live draft from that snapshot, merged with the DB rows (the DB is the truth for logged sets), without writing anything. A resumed draft carries `sessionId`/`sessionDate`, so its finish goes through `replaceSession`, which UPDATEs the session row (never deletes it) and DELETE+INSERTs its sets with the same ids.

**Tech Stack:** Flutter 3.44.0 via fvm, Dart 3.12, provider, PowerSync 2.2.0 (local SQLite views), flutter_test only (no mocking package).

**Spec:** `docs/superpowers/specs/2026-09-23-resume-finished-workout-design.md`

## Global Constraints

- Run everything from the repo root with explicit paths; never `cd`. Flutter only through `make -C app <target>`.
- Test command shape (the harness backgrounds a bare `make -C app test`): `timeout 400 make -C app test TEST=<file> > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`. Full suite: same without `TEST=`.
- `make -C app analyze` must end at `No issues found!` after every task.
- Baseline before this plan: **293 tests, all passing**. Never finish a task with fewer passing tests.
- After editing any `.arb` file run `timeout 400 make -C app get > /tmp/reps-get.log 2>&1; echo "EXIT=$?"` so the gitignored localization classes regenerate.
- Commits: Conventional Commits, standard types, subject line only, no body. Stage only the files the task touched.
- Never reference this plan (task numbers, "plan") in code or comments — use descriptive language.
- Parse NUMERIC/TEXT weights with `double.tryParse`, never `double.parse`.
- Every new localization key goes into all four ARB files (`app_en`, `app_it`, `app_de`, `app_es`); simple strings get no `@` metadata.
- Confirm dialogs only via `showWConfirm`/`showWDialog`; never `AlertDialog`.
- Never create a `db.watch()`/`repo.watchX()` stream inside `build()`.
- The server (`server/`) is not changed.
- Do not touch `WStepper`'s `didUpdateWidget`.

## Review Focus

1. **Process death right after Resume** — relaunching must restore the resumed workout, and its Finish must still replace the same session. Pinned in Task 6 (the draft saved before `register` carries `sessionId`) and Task 1 (`sessionId` survives the JSON round trip).
2. **Midnight** — a workout resumed after midnight and finished again stays on its original date, and is not resumable for the whole next day. Pinned in Task 3 (resumed finish writes the original date) and Task 4 (`isResumable` for a re-finish after midnight).
3. **A second workout the same day** supersedes the first one's snapshot, so only the latest card offers Resume. Pinned in Task 4 (`resumeStateFor` returns `none` for the superseded session).
4. **A tap on an expired Resume button** must make the button disappear instead of doing nothing. Pinned in Task 5 (`forgetFinished` notifies and clears) and Task 8 (the History handler calls it for `none`).
5. **History edits between Finish and Resume** (an edited, a deleted and an added set) must all survive into the resumed workout. Pinned in Task 4 (pure merge) and Task 6 (end to end over a real DB).

---

## File Structure

- `app/lib/session/active_session_controller.dart` — `SessionDraft` gains `sessionId`/`sessionDate`/`deepCopy`; `BlockState` JSON keeps rest; `finish()` replaces a resumed session and records `lastFinished`; `addBlock` excludes the resumed session from baselines.
- `app/lib/data/active_session_draft.dart` — `DraftStore.tryDecode`, catch-all load.
- `app/lib/data/finished_session_store.dart` (new) — `FinishedSession` + `FinishedSessionStore`.
- `app/lib/data/session_writer.dart` — day bound through a subquery; new `replaceSession`.
- `app/lib/data/session_repository.dart` — `excludeSessionId`, `sessionById`, top-level `groupSetsIntoBlocks`.
- `app/lib/session/resume.dart` (new) — eligibility, card state, merge, restore, discard-dialog copy.
- `app/lib/session/session_manager.dart` — snapshot ownership, expiry timer, launch guard, `register` assert.
- `app/lib/shell/session_launcher.dart` — `prepareResume`, `resumeFinishedSession`, guarded `startSession`.
- `app/lib/session/active_session_screen.dart` — adopt after commit; discard copy.
- `app/lib/main.dart` — `loadLastFinished` at boot.
- `app/lib/theme/icons.dart` — `WIcons.resume`.
- `app/lib/l10n/app_{en,it,de,es}.arb` — five keys.
- `app/lib/ui/history_screen.dart` — resume state per card, `SessionCardBody`, keyed cards, quiet reload.
- Tests: `app/test/session/draft_json_test.dart`, `app/test/session/finish_resume_test.dart`, `app/test/session/resume_test.dart`, `app/test/session/session_manager_finished_test.dart`, `app/test/data/resume_integration_test.dart`, `app/test/ui/history_session_card_test.dart`, `app/test/support/fake_stores.dart`, additions to `app/test/data/session_writer_test.dart`.

---

### Task 1: Draft and snapshot serialization

**Files:**
- Modify: `app/lib/session/active_session_controller.dart` (`BlockState` :151-228, `SessionDraft` :231-264, imports)
- Modify: `app/lib/data/active_session_draft.dart:39-53`
- Create: `app/lib/data/finished_session_store.dart`
- Test: `app/test/session/draft_json_test.dart`

**Interfaces:**
- Produces:
  - `SessionDraft({required String? templateId, required String name, required String focus, required DateTime startedAt, required List<BlockState> blocks, String? sessionId, String? sessionDate})`, fields `sessionId`, `sessionDate`, method `SessionDraft deepCopy()`.
  - `static SessionDraft? DraftStore.tryDecode(String raw)`.
  - `class FinishedSession { final String sessionId; final String sessionDate; final DateTime finishedAt; final int elapsedSeconds; final SessionDraft draft; Map<String, dynamic> toJson(); factory FinishedSession.fromJson(Map<String, dynamic>); static FinishedSession? tryDecode(String raw); }`
  - `class FinishedSessionStore { Future<void> save(FinishedSession f); Future<FinishedSession?> load(); Future<void> clear(); }` (non-final methods, so tests can subclass it).

- [ ] **Step 1: Write the failing tests** — create `app/test/session/draft_json_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/active_session_draft.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

BlockState _block({int? restSeconds}) {
  final ex = Exercise(
    id: 'e1',
    name: 'Bench',
    slug: 'bench',
    muscleGroup: 'chest',
    compound: true,
    plateStepKg: 2.5,
    defaultRestSeconds: restSeconds,
    isTemplate: false,
  );
  return BlockState(
    exercise: ex,
    resolved: ResolvedSlot(
      exercise: ex,
      workSets: 2,
      warmupSets: 1,
      repLow: 5,
      repHigh: 8,
      rirLow: 1,
      rirHigh: 2,
    ),
    warmupSets: [
      SetState(id: 'w1', weightKg: 40, reps: 8, rir: null, isWarmup: true, done: true),
    ],
    workingSets: [
      SetState(id: 's1', weightKg: 60, reps: 5, rir: 1, isWarmup: false, done: true),
      SetState(id: 's2', weightKg: 60, reps: 5, rir: 1, isWarmup: false, done: false),
    ],
    expanded: true,
    bestKg: 57.5,
    lastTop: (weight: 57.5, reps: 5, date: '2026-09-20'),
  );
}

SessionDraft _draft({String? sessionId, String? sessionDate}) => SessionDraft(
      templateId: 'd1',
      name: 'Upper A',
      focus: 'Push',
      startedAt: DateTime(2026, 9, 23, 9, 0),
      blocks: [_block(restSeconds: 150)],
      sessionId: sessionId,
      sessionDate: sessionDate,
    );

void main() {
  group('SessionDraft JSON', () {
    test('sessionId and sessionDate round-trip', () {
      final back = SessionDraft.fromJson(
        jsonDecode(jsonEncode(_draft(sessionId: 'S', sessionDate: '2026-09-22').toJson()))
            as Map<String, dynamic>,
      );
      expect(back.sessionId, 'S');
      expect(back.sessionDate, '2026-09-22');
    });

    test('a draft written by an older build is a fresh workout', () {
      final json = _draft().toJson()
        ..remove('sessionId')
        ..remove('sessionDate');
      final back = SessionDraft.fromJson(json);
      expect(back.sessionId, isNull);
      expect(back.sessionDate, isNull);
      expect(back.name, 'Upper A');
    });

    test('per-exercise rest survives the round trip', () {
      final copy = _draft().deepCopy();
      expect(copy.blocks.single.exercise.defaultRestSeconds, 150);
    });

    test('deepCopy shares no mutable state with the original', () {
      final original = _draft(sessionId: 'S', sessionDate: '2026-09-22');
      final copy = original.deepCopy();
      copy.blocks.single.workingSets.first.weightKg = 99;
      copy.blocks.single.workingSets.last.done = true;
      expect(original.blocks.single.workingSets.first.weightKg, 60);
      expect(original.blocks.single.workingSets.last.done, isFalse);
      expect(copy.sessionId, 'S');
      expect(copy.startedAt, original.startedAt);
      expect(copy.blocks.single.allSets.map((s) => s.id), ['w1', 's1', 's2']);
      expect(copy.blocks.single.bestKg, 57.5);
      expect(copy.blocks.single.lastTop?.date, '2026-09-20');
    });
  });

  group('DraftStore.tryDecode', () {
    test('returns null for a mistyped draft instead of throwing', () {
      // A cast failure is a TypeError — an Error, not an Exception.
      expect(DraftStore.tryDecode('{"name": null}'), isNull);
      expect(DraftStore.tryDecode('not json'), isNull);
      expect(DraftStore.tryDecode('[]'), isNull);
    });

    test('decodes a valid draft', () {
      final d = DraftStore.tryDecode(jsonEncode(_draft(sessionId: 'S').toJson()));
      expect(d?.name, 'Upper A');
      expect(d?.sessionId, 'S');
    });
  });

  group('FinishedSession JSON', () {
    FinishedSession snapshot() => FinishedSession(
          sessionId: 'S',
          sessionDate: '2026-09-23',
          finishedAt: DateTime(2026, 9, 23, 10, 5),
          elapsedSeconds: 3900,
          draft: _draft(),
        );

    test('round-trips', () {
      final back = FinishedSession.tryDecode(jsonEncode(snapshot().toJson()))!;
      expect(back.sessionId, 'S');
      expect(back.sessionDate, '2026-09-23');
      expect(back.finishedAt, DateTime(2026, 9, 23, 10, 5));
      expect(back.elapsedSeconds, 3900);
      expect(back.draft.blocks.single.allSets.length, 3);
    });

    test('tryDecode returns null for malformed input', () {
      expect(FinishedSession.tryDecode('{}'), isNull);
      expect(FinishedSession.tryDecode('[]'), isNull);
      expect(FinishedSession.tryDecode('x'), isNull);
      expect(
        FinishedSession.tryDecode(jsonEncode({...snapshot().toJson(), 'draft': 3})),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 400 make -C app test TEST=test/session/draft_json_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`
Expected: compilation failure — `No named parameter with the name 'sessionId'`, `finished_session_store.dart` not found.

- [ ] **Step 3: Implement `SessionDraft` fields, `deepCopy`, and rest serialization**

In `app/lib/session/active_session_controller.dart`, add `import 'dart:convert';` as the first import (above `import 'dart:async';` is fine; keep `dart:` imports together and sorted: `dart:async`, `dart:convert`, `dart:math`).

In `BlockState.toJson`, add after `'exerciseDefaultRirHigh': exercise.defaultRirHigh,`:

```dart
        'exerciseDefaultRestSeconds': exercise.defaultRestSeconds,
```

In `BlockState.fromJson`'s `Exercise(...)`, add after `defaultRirHigh: json['exerciseDefaultRirHigh'] as int?,`:

```dart
      defaultRestSeconds: json['exerciseDefaultRestSeconds'] as int?,
```

Replace the whole `SessionDraft` class with:

```dart
/// The in-memory model for an ongoing session, held by [ActiveSessionController].
class SessionDraft {
  final String? templateId;
  final String name;
  final String focus;
  final DateTime startedAt;
  final List<BlockState> blocks;

  /// The `sessions.id` this draft was resumed from, or null for a fresh
  /// workout. When set, finishing replaces that session in place.
  final String? sessionId;

  /// The `sessions.date` of the resumed session, kept when it is finished
  /// again so the workout stays on the day it was done. Null for a fresh
  /// workout.
  final String? sessionDate;

  const SessionDraft({
    required this.templateId,
    required this.name,
    required this.focus,
    required this.startedAt,
    required this.blocks,
    this.sessionId,
    this.sessionDate,
  });

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'name': name,
        'focus': focus,
        'startedAt': startedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'sessionId': sessionId,
        'sessionDate': sessionDate,
      };

  factory SessionDraft.fromJson(Map<String, dynamic> json) => SessionDraft(
        templateId: json['templateId'] as String?,
        name: json['name'] as String,
        focus: json['focus'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        blocks: (json['blocks'] as List)
            .map((e) => BlockState.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Absent in drafts written by older builds → a fresh workout.
        sessionId: json['sessionId'] as String?,
        sessionDate: json['sessionDate'] as String?,
      );

  /// An independent copy made through the same JSON path the draft files use,
  /// so no [BlockState]/[SetState] is shared with this draft.
  SessionDraft deepCopy() => SessionDraft.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}
```

- [ ] **Step 4: Make `DraftStore.load` tolerant** — in `app/lib/data/active_session_draft.dart`, replace `load()` (:39-53) with:

```dart
  /// Decodes a draft file's contents, or returns null if it is not a valid
  /// draft. Catches everything: a missing or mistyped field is a `TypeError`
  /// (an Error, not an Exception), which would otherwise escape to `main()`
  /// before `runApp` and stop the app starting.
  static SessionDraft? tryDecode(String raw) {
    try {
      return SessionDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Reads and deserialises the draft, or returns null if no draft exists or
  /// the file is corrupt (a corrupt file is cleared).
  Future<SessionDraft?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    SessionDraft? draft;
    try {
      draft = tryDecode(await file.readAsString());
    } catch (_) {
      draft = null;
    }
    if (draft == null) await clear();
    return draft;
  }
```

- [ ] **Step 5: Create `app/lib/data/finished_session_store.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../session/active_session_controller.dart';

/// Snapshot of the last workout finished on this device, kept so an
/// accidental Finish can be undone from History.
class FinishedSession {
  /// The `sessions.id` the finish wrote.
  final String sessionId;

  /// The `sessions.date` the finish wrote (`YYYY-MM-DD`).
  final String sessionDate;

  /// Local wall clock at finish.
  final DateTime finishedAt;

  /// Workout time at finish (what `duration_min` rounds).
  final int elapsedSeconds;

  /// The draft exactly as it was when Finish was tapped.
  final SessionDraft draft;

  const FinishedSession({
    required this.sessionId,
    required this.sessionDate,
    required this.finishedAt,
    required this.elapsedSeconds,
    required this.draft,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'sessionDate': sessionDate,
        'finishedAt': finishedAt.toIso8601String(),
        'elapsedSeconds': elapsedSeconds,
        'draft': draft.toJson(),
      };

  factory FinishedSession.fromJson(Map<String, dynamic> json) => FinishedSession(
        sessionId: json['sessionId'] as String,
        sessionDate: json['sessionDate'] as String,
        finishedAt: DateTime.parse(json['finishedAt'] as String),
        elapsedSeconds: json['elapsedSeconds'] as int,
        draft: SessionDraft.fromJson(json['draft'] as Map<String, dynamic>),
      );

  /// Decodes a snapshot file's contents, or null if it is not a valid one.
  /// Catches everything, including the `TypeError` of a mistyped field.
  static FinishedSession? tryDecode(String raw) {
    try {
      return FinishedSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Single-slot, local-only store for the [FinishedSession] snapshot, at
/// `<applicationSupportDirectory>/workout-last-finished.json`. Never synced.
/// A later finish overwrites it.
class FinishedSessionStore {
  static const _filename = 'workout-last-finished.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _filename));
  }

  /// Writes [f] atomically via a temp file.
  Future<void> save(FinishedSession f) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(f.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// The stored snapshot, or null if there is none or it is unreadable (an
  /// unreadable file is cleared).
  Future<FinishedSession?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    FinishedSession? f;
    try {
      f = FinishedSession.tryDecode(await file.readAsString());
    } catch (_) {
      f = null;
    }
    if (f == null) await clear();
    return f;
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
```

- [ ] **Step 6: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/session/draft_json_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`
Expected: `All tests passed!`
Run: `timeout 400 make -C app analyze > /tmp/reps-analyze.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/reps-analyze.log`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/session/active_session_controller.dart app/lib/data/active_session_draft.dart app/lib/data/finished_session_store.dart app/test/session/draft_json_test.dart
git commit -m "feat(app): serialize resumable session drafts and finished-workout snapshots"
```

---

### Task 2: Session writer and repository primitives

**Files:**
- Modify: `app/lib/data/session_writer.dart:89-156`
- Modify: `app/lib/data/session_repository.dart` (`lastTopSet` :62-109, `bestTopSet` :111-123, `groupIntoBlocks` :174-209, new `sessionById`)
- Test: `app/test/data/session_writer_test.dart` (append), `app/test/data/resume_integration_test.dart` (create)

**Interfaces:**
- Produces:
  - `Future<void> persistSession(SqlExecutor, SessionWrite)` (unchanged signature; session INSERT now binds the day through a subquery).
  - `Future<void> replaceSession(SqlExecutor executor, SessionWrite write)`.
  - `SessionRepository.lastTopSet(String exerciseId, {String? beforeDate, String? excludeSessionId})`.
  - `SessionRepository.bestTopSet(String exerciseId, {String? excludeSessionId})`.
  - `Future<SessionSummaryRow?> SessionRepository.sessionById(String id)`.
  - Top-level `List<ExerciseBlockData> groupSetsIntoBlocks(List<LoggedSet> sets)` in `session_repository.dart`; the method `groupIntoBlocks` delegates to it.

- [ ] **Step 1: Write the failing SQL-shape tests** — append inside `main()` of `app/test/data/session_writer_test.dart`:

```dart
  test('persistSession binds the training day through a subquery', () async {
    final exec = FakeExec();
    await persistSession(exec, const SessionWrite(
      id: 'sess1', dateIso: '2026-09-23', dayTemplateId: 'day1',
      splitLabel: 'Upper A', durationMin: 42, sets: [],
    ));
    expect(exec.calls.single.$1,
        contains('SELECT ?, ?, (SELECT id FROM day_templates WHERE id = ?), ?, ?'));
    expect(exec.calls.single.$2, ['sess1', '2026-09-23', 'day1', 'Upper A', 42]);
  });

  test('replaceSession updates the session row, never deletes it, and re-inserts the sets', () async {
    final exec = FakeExec();
    await replaceSession(exec, const SessionWrite(
      id: 'sess1', dateIso: '2026-09-20', dayTemplateId: 'day1',
      splitLabel: 'Upper A', durationMin: 55,
      sets: [
        SetWrite(id: 's1', exerciseId: 'e1', setNumber: 1, weightKg: '80.00', reps: 6, rir: 1, isWarmup: false, isTopSet: true),
      ],
    ));
    expect(exec.calls[0].$1, 'UPDATE sessions SET split_label = ?, duration_min = ? WHERE id = ?');
    expect(exec.calls[0].$2, ['Upper A', 55, 'sess1']);
    expect(exec.calls[1].$1, contains('WHERE NOT EXISTS (SELECT 1 FROM sessions WHERE id = ?)'));
    expect(exec.calls[1].$2, ['sess1', '2026-09-20', 'day1', 'Upper A', 55, 'sess1']);
    expect(exec.calls[2].$1, 'DELETE FROM sets WHERE session_id = ?');
    expect(exec.calls[2].$2, ['sess1']);
    expect(exec.calls[3].$1, startsWith('INSERT INTO sets'));
    expect(exec.calls.length, 4);
    expect(exec.calls.any((c) => c.$1.contains('DELETE FROM sessions')), isFalse);
  });
```

- [ ] **Step 2: Write the failing real-DB tests** — create `app/test/data/resume_integration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/sync/schema.dart';

/// Resume-a-finished-workout contracts against a REAL PowerSync database:
/// the replace-in-place write, the CRUD ops it uploads, and the baseline
/// lookups that must ignore the resumed session's own rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PowerSyncDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reps-resume');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/t.db');
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedDay(String id) => db.execute(
      'INSERT INTO day_templates (id, name, position, is_template) VALUES (?, ?, 0, 0)',
      [id, 'Upper A']);

  Future<void> seedSession(String id, String date, {String? day}) => db.execute(
      'INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, date, day, 'Upper A', 40]);

  Future<void> seedSet(String id, String sessionId, String exerciseId, int n,
          String weight,
          {bool top = false}) =>
      db.execute(
          'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, '
          'is_warmup, is_top_set, is_pr) VALUES (?, ?, ?, ?, ?, 5, 1, 0, ?, 0)',
          [id, sessionId, exerciseId, n, weight, top ? 1 : 0]);

  /// Completes every queued upload transaction so the next one is ours.
  Future<void> drainCrud() async {
    while (true) {
      final t = await db.getNextCrudTransaction();
      if (t == null) return;
      await t.complete();
    }
  }

  Future<List<CrudEntry>> nextCrud() async {
    final t = await db.getNextCrudTransaction();
    if (t == null) return [];
    await t.complete();
    return t.crud;
  }

  SessionWrite write(String id, {String? day, List<SetWrite>? sets}) => SessionWrite(
        id: id,
        dateIso: '2026-09-23',
        dayTemplateId: day,
        splitLabel: 'Upper A',
        durationMin: 55,
        sets: sets ??
            const [
              SetWrite(id: 'a', exerciseId: 'bench', setNumber: 1, weightKg: '102.50', reps: 5, rir: 1, isWarmup: false, isTopSet: true),
              SetWrite(id: 'b', exerciseId: 'bench', setNumber: 2, weightKg: '100.00', reps: 5, rir: 1, isWarmup: false),
            ],
      );

  group('writer (real DB)', () {
    test('persistSession stores NULL for a training day that no longer exists', () async {
      await db.writeTransaction(
          (tx) => persistSession(PowerSyncTxExecutor(tx), write('S', day: 'gone')));
      final row = await db.get('SELECT day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['day_template_id'], isNull);
    });

    test('persistSession keeps an existing training day', () async {
      await seedDay('d1');
      await db.writeTransaction(
          (tx) => persistSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));
      final row = await db.get('SELECT day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['day_template_id'], 'd1');
    });

    test('replaceSession keeps the row and uploads a PATCH, set DELETEs, then set PUTs', () async {
      await seedDay('d1');
      await seedSession('S', '2026-09-23', day: 'd1');
      await seedSet('a', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('old', 'S', 'bench', 2, '95.00');
      await drainCrud();

      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));

      final ops = await nextCrud();
      expect(ops.map((e) => '${e.op.name}:${e.table}').toList(), [
        'patch:sessions',
        'delete:sets',
        'delete:sets',
        'put:sets',
        'put:sets',
      ]);
      expect(ops.first.id, 'S');
      expect(ops.first.opData!.containsKey('day_template_id'), isFalse);
      expect(ops.first.opData!['duration_min'], 55);

      final sessions = await db.getAll('SELECT id, date FROM sessions');
      expect(sessions.single['id'], 'S');
      expect(sessions.single['date'], '2026-09-23');
      final sets = await db.getAll('SELECT id, weight_kg FROM sets ORDER BY id');
      expect(sets.map((r) => r['id']), ['a', 'b']);
      expect(sets.first['weight_kg'], '102.50');
    });

    test('replaceSession survives a training day deleted since the first finish', () async {
      await seedDay('d1');
      await seedSession('S', '2026-09-23', day: 'd1');
      await seedSet('a', 'S', 'bench', 1, '100.00', top: true);
      await db.execute('DELETE FROM day_templates WHERE id = ?', ['d1']);
      await drainCrud();

      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'd1')));

      final ops = await nextCrud();
      expect(ops.where((e) => e.table == 'sessions').map((e) => e.op), [UpdateType.patch]);
      expect(ops.first.opData!.containsKey('day_template_id'), isFalse);
      expect((await db.getAll('SELECT id FROM sessions')).single['id'], 'S');
    });

    test('replaceSession re-creates a vanished session row, with a deleted day as NULL', () async {
      await drainCrud();
      await db.writeTransaction(
          (tx) => replaceSession(PowerSyncTxExecutor(tx), write('S', day: 'gone')));

      final ops = await nextCrud();
      expect(ops.first.op, UpdateType.put);
      expect(ops.first.table, 'sessions');
      final row = await db.get('SELECT date, day_template_id FROM sessions WHERE id = ?', ['S']);
      expect(row['date'], '2026-09-23');
      expect(row['day_template_id'], isNull);
      expect((await db.getAll('SELECT id FROM sets')).length, 2);
    });
  });

  group('repository (real DB)', () {
    test('bestTopSet and lastTopSet can exclude one session', () async {
      await seedSession('Y', '2026-09-22');
      await seedSet('y1', 'Y', 'bench', 1, '90.00', top: true);
      await seedSession('T', '2026-09-23');
      await seedSet('t1', 'T', 'bench', 1, '100.00', top: true);
      final repo = SessionRepository(db);

      expect(await repo.bestTopSet('bench'), 100);
      expect(await repo.bestTopSet('bench', excludeSessionId: 'T'), 90);
      expect((await repo.lastTopSet('bench'))!.date, '2026-09-23');
      final last = (await repo.lastTopSet('bench', excludeSessionId: 'T'))!;
      expect(last.date, '2026-09-22');
      expect(last.weight, 90);
      final before = (await repo.lastTopSet('bench',
          beforeDate: '2026-09-24', excludeSessionId: 'T'))!;
      expect(before.date, '2026-09-22');
      expect(await repo.bestTopSet('bench', excludeSessionId: 'Y'), 100);
    });

    test('sessionById returns the row, or null once it is gone', () async {
      await seedSession('S', '2026-09-23', day: 'd1');
      final repo = SessionRepository(db);
      final row = (await repo.sessionById('S'))!;
      expect(row.date, '2026-09-23');
      expect(row.durationMin, 40);
      expect(await repo.sessionById('nope'), isNull);
    });
  });
}
```

- [ ] **Step 3: Run both files to verify they fail**

Run: `timeout 400 make -C app test TEST=test/data/session_writer_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — `replaceSession` isn't defined.
Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile errors (`replaceSession`, `excludeSessionId`, `sessionById`).

- [ ] **Step 4: Implement the writer** — in `app/lib/data/session_writer.dart`, replace everything from the `// ── persistSession ──` comment (:89) to the end of the file with:

```dart
// ── Top set ───────────────────────────────────────────────────────────────────

/// Index into [sets] of the top set for ONE exercise: heaviest non-warmup set,
/// tie-break weight DESC, reps DESC, set_number ASC, id ASC (mirrors the server).
/// Returns -1 if there is no non-warmup set. weightKg is TEXT → compare numerically.
int topSetIndex(List<SetWrite> sets) {
  var best = -1;
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];
    if (s.isWarmup) continue;
    if (best == -1) { best = i; continue; }
    final b = sets[best];
    final sw = double.tryParse(s.weightKg) ?? 0;
    final bw = double.tryParse(b.weightKg) ?? 0;
    if (sw > bw ||
        (sw == bw && s.reps > b.reps) ||
        (sw == bw && s.reps == b.reps && s.setNumber < b.setNumber) ||
        (sw == bw && s.reps == b.reps && s.setNumber == b.setNumber && s.id.compareTo(b.id) < 0)) {
      best = i;
    }
  }
  return best;
}

// ── persistSession / replaceSession ───────────────────────────────────────────

/// The session INSERT. The training day is bound through a subquery so a day
/// deleted locally (mid-workout, or while a finished workout was resumed)
/// becomes NULL instead of an id the server's day_templates foreign key would
/// reject — a rejected session PUT makes the server skip every set PUT of the
/// batch as an orphan, and the whole workout then vanishes on sync-down.
const _insertSessionSql =
    'INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) '
    'SELECT ?, ?, (SELECT id FROM day_templates WHERE id = ?), ?, ?';

List<Object?> _sessionArgs(SessionWrite w) =>
    [w.id, w.dateIso, w.dayTemplateId, w.splitLabel, w.durationMin];

Future<void> _insertSets(SqlExecutor executor, SessionWrite write) async {
  for (final s in write.sets) {
    await executor.execute(
      'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup, is_top_set, is_pr) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        s.id,
        write.id,
        s.exerciseId,
        s.setNumber,
        s.weightKg, // TEXT — never cast here; the schema maps NUMERIC → text
        s.reps,
        s.isWarmup ? null : s.rir, // warm-up RIR → null
        s.isWarmup ? 1 : 0,
        s.isTopSet ? 1 : 0,
        s.isPr ? 1 : 0,
      ],
    );
  }
}

/// Writes [write] to the database via [executor]: one `sessions` INSERT + one
/// `sets` INSERT per set.
///
/// The server stamps `user_id`; `is_top_set`/`is_pr` are stamped client-side
/// (see [topSetIndex]) so offline-logged data is correct before sync.
///
/// **Atomicity:** always call this inside `db.writeTransaction` via
/// [PowerSyncTxExecutor]; that ensures the session row and all set rows commit
/// as one local transaction and are uploaded as one CRUD batch.
Future<void> persistSession(SqlExecutor executor, SessionWrite write) async {
  await executor.execute(_insertSessionSql, _sessionArgs(write));
  await _insertSets(executor, write);
}

/// Replaces an already-finished session in place — finishing a resumed
/// workout: same session id and date, a new set of sets.
///
/// The session row is UPDATEd, never deleted. Uploaded as a PATCH of
/// `split_label`/`duration_min` only, it cannot be rejected by the server;
/// a DELETE + re-INSERT would instead lose the whole, already-synced workout
/// whenever the re-insert PUT is rejected (for example, its training day was
/// deleted since). The guarded INSERT re-creates the row only if it vanished
/// (deleted by a sync during the resumed workout) and otherwise inserts
/// nothing and uploads nothing. The sets are DELETE + INSERT with the same
/// ids, which PowerSync uploads as DELETE then PUT; the server recomputes the
/// top-set and PR flags for both.
///
/// Same atomicity rule as [persistSession].
Future<void> replaceSession(SqlExecutor executor, SessionWrite write) async {
  await executor.execute(
    'UPDATE sessions SET split_label = ?, duration_min = ? WHERE id = ?',
    [write.splitLabel, write.durationMin, write.id],
  );
  await executor.execute(
    '$_insertSessionSql WHERE NOT EXISTS (SELECT 1 FROM sessions WHERE id = ?)',
    [..._sessionArgs(write), write.id],
  );
  await executor.execute('DELETE FROM sets WHERE session_id = ?', [write.id]);
  await _insertSets(executor, write);
}
```

(The old free-floating doc comment above `topSetIndex` moved onto `persistSession`; `topSetIndex`'s body is unchanged.)

- [ ] **Step 5: Implement the repository changes** — in `app/lib/data/session_repository.dart`:

Replace `lastTopSet` (:62-109) with:

```dart
  /// Returns the most-recent top set for [exerciseId], optionally restricted
  /// to sessions strictly before [beforeDate] (ISO-8601 date string), and
  /// optionally ignoring one session's rows ([excludeSessionId] — a resumed
  /// workout's own finished rows, which must not become its own baseline).
  ///
  /// The `created_at` DESC tie-break makes same-date results deterministic.
  Future<({double weight, int reps, String date})?> lastTopSet(
    String exerciseId, {
    String? beforeDate,
    String? excludeSessionId,
  }) async {
    final args = <Object?>[exerciseId];
    var filters = '';
    if (beforeDate != null) {
      filters += ' AND se.date < ?';
      args.add(beforeDate);
    }
    if (excludeSessionId != null) {
      filters += ' AND s.session_id != ?';
      args.add(excludeSessionId);
    }
    final row = await db.getOptional('''
        SELECT s.weight_kg, s.reps, se.date
          FROM sets s
          JOIN sessions se ON se.id = s.session_id
         WHERE s.exercise_id = ?
           AND s.is_top_set = 1
           AND s.is_warmup = 0$filters
         ORDER BY se.date DESC, se.created_at DESC
         LIMIT 1
      ''', args);
    if (row == null) return null;

    final wt = row['weight_kg'];
    return (
      weight: double.tryParse(wt?.toString() ?? '') ?? 0.0,
      reps: row['reps'] as int? ?? 0,
      date: row['date'] as String? ?? '',
    );
  }
```

Replace `bestTopSet` (:111-123) with:

```dart
  /// Returns the all-time best top-set weight (kg) for [exerciseId], or null
  /// if the exercise has never been logged. [excludeSessionId] ignores one
  /// session's rows (a resumed workout's own finished rows).
  Future<double?> bestTopSet(String exerciseId, {String? excludeSessionId}) async {
    final row = await db.getOptional(
      'SELECT MAX(CAST(weight_kg AS REAL)) AS best '
      'FROM sets WHERE exercise_id = ? AND is_top_set = 1 AND is_warmup = 0'
      '${excludeSessionId != null ? ' AND session_id != ?' : ''}',
      [exerciseId, if (excludeSessionId != null) excludeSessionId],
    );
    if (row == null) return null;
    final best = row['best'];
    if (best == null) return null;
    return (best as num).toDouble();
  }
```

Add after `watchRecentSessions` (inside the class, in the `// ── Session list ──` section):

```dart
  /// One session row, or null if it no longer exists.
  Future<SessionSummaryRow?> sessionById(String id) async {
    final row = await db.getOptional(
      'SELECT id, date, split_label, day_template_id, duration_min '
      'FROM sessions WHERE id = ?',
      [id],
    );
    return row == null ? null : SessionSummaryRow.fromRow(row);
  }
```

Move the body of `groupIntoBlocks` into a new top-level function placed just above `class SessionRepository` (after the mutation builders), and make the method delegate:

```dart
/// Groups a flat list of [LoggedSet]s into [ExerciseBlockData] records, one
/// per unique exercise, in the order they first appear. Pure — usable without
/// a repository (History's card body).
List<ExerciseBlockData> groupSetsIntoBlocks(List<LoggedSet> sets) {
  final order = <String>[];
  final byExercise = <String, List<LoggedSet>>{};

  for (final s in sets) {
    if (!byExercise.containsKey(s.exerciseId)) {
      order.add(s.exerciseId);
      byExercise[s.exerciseId] = [];
    }
    byExercise[s.exerciseId]!.add(s);
  }

  return order.map((exId) {
    final exSets = byExercise[exId]!;
    final workingSets = exSets.where((s) => !s.isWarmup).toList();

    // Top set: the one flagged is_top_set=true by the server; fall back to
    // the set with the highest weight if none is flagged.
    final topSet = workingSets.firstWhere(
      (s) => s.isTopSet,
      orElse: () => workingSets.isEmpty ? exSets.first : workingSets.reduce(
        (a, b) => a.weightKg >= b.weightKg ? a : b,
      ),
    );

    return ExerciseBlockData(
      exerciseId: exId,
      sets: exSets,
      topWeight: topSet.weightKg,
      topReps: topSet.reps,
      isPr: topSet.isPr,
    );
  }).toList();
}
```

and inside the class replace the old method with:

```dart
  /// See [groupSetsIntoBlocks].
  List<ExerciseBlockData> groupIntoBlocks(List<LoggedSet> sets) =>
      groupSetsIntoBlocks(sets);
```

- [ ] **Step 6: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/data/session_writer_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/session/build_model_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Expected: all three `All tests passed!`
Run: `timeout 400 make -C app analyze > /tmp/reps-analyze.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/reps-analyze.log` → `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/data/session_writer.dart app/lib/data/session_repository.dart app/test/data/session_writer_test.dart app/test/data/resume_integration_test.dart
git commit -m "feat(app): replace a finished session in place and exclude it from baselines"
```

---

### Task 3: Finish replaces a resumed session and records a snapshot

**Files:**
- Modify: `app/lib/session/active_session_controller.dart` (imports, `addBlock` :505-519, `finish` :521-591)
- Test: `app/test/session/finish_resume_test.dart` (create), `app/test/data/resume_integration_test.dart` (append a group)

**Interfaces:**
- Consumes: `SessionDraft.sessionId/sessionDate/deepCopy` (Task 1), `FinishedSession` (Task 1), `replaceSession`, `lastTopSet/bestTopSet(excludeSessionId:)` (Task 2).
- Produces: `FinishedSession? ActiveSessionController.lastFinished` (set by a successful `finish`, never by `discard`); `finish()` returns the draft's `sessionId` for a resumed draft.

- [ ] **Step 1: Write the failing unit tests** — create `app/test/session/finish_resume_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/util/dates.dart';

class FakeExec implements SqlExecutor {
  final calls = <(String, List<Object?>)>[];
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    calls.add((sql, params));
  }
}

SessionDraft draftWith({String? sessionId, String? sessionDate}) {
  final ex = Exercise(
    id: 'bench', name: 'Bench', slug: 'bench', muscleGroup: 'chest',
    compound: true, plateStepKg: 2.5, isTemplate: false,
  );
  return SessionDraft(
    templateId: 'd1',
    name: 'Upper A',
    focus: 'Push',
    startedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    sessionId: sessionId,
    sessionDate: sessionDate,
    blocks: [
      BlockState(
        exercise: ex,
        resolved: ResolvedSlot(
          exercise: ex, workSets: 2, warmupSets: 1,
          repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2,
        ),
        warmupSets: [
          SetState(id: 'w1', weightKg: 40, reps: 8, rir: null, isWarmup: true, done: true),
        ],
        workingSets: [
          SetState(id: 's1', weightKg: 100, reps: 5, rir: 1, isWarmup: false, done: true),
          SetState(id: 's2', weightKg: 100, reps: 5, rir: 1, isWarmup: false, done: false),
        ],
        expanded: true,
        bestKg: 90,
      ),
    ],
  );
}

void main() {
  test('a fresh finish records a snapshot of the finished workout', () async {
    final c = ActiveSessionController()..seedForTest(draftWith());
    final exec = FakeExec();
    final id = await c.finish(exec);

    final f = c.lastFinished!;
    expect(f.sessionId, id);
    expect(f.sessionDate, isoDate(DateTime.now()));
    expect(f.elapsedSeconds, inInclusiveRange(40 * 60, 40 * 60 + 5));
    expect(f.draft.sessionId, isNull);
    expect(f.draft.blocks.single.workingSets.map((s) => s.done), [true, false]);
    expect(exec.calls.first.$1, contains('(SELECT id FROM day_templates WHERE id = ?)'));
    expect(c.hasSession, isFalse);
  });

  test('the snapshot is a copy the finished draft cannot change', () async {
    final original = draftWith();
    final c = ActiveSessionController()..seedForTest(original);
    await c.finish(FakeExec());
    original.blocks.single.workingSets.first.weightKg = 1;
    expect(c.lastFinished!.draft.blocks.single.workingSets.first.weightKg, 100);
  });

  test('a resumed finish replaces its session in place, on its original date', () async {
    final c = ActiveSessionController()
      ..seedForTest(draftWith(sessionId: 'S', sessionDate: '2026-09-20'));
    final exec = FakeExec();
    final id = await c.finish(exec);

    expect(id, 'S');
    expect(exec.calls[0].$1, startsWith('UPDATE sessions SET'));
    expect(exec.calls[0].$2.last, 'S');
    expect(exec.calls[1].$1, contains('WHERE NOT EXISTS'));
    expect(exec.calls[1].$2.sublist(0, 2), ['S', '2026-09-20']);
    expect(exec.calls[2].$1, 'DELETE FROM sets WHERE session_id = ?');
    expect(exec.calls.any((call) => call.$1.contains('DELETE FROM sessions')), isFalse);
    final setInserts = exec.calls.where((call) => call.$1.startsWith('INSERT INTO sets')).toList();
    expect(setInserts.map((call) => call.$2[0]), ['w1', 's1']); // done sets only
    expect(setInserts.every((call) => call.$2[1] == 'S'), isTrue);
    expect(c.lastFinished!.sessionId, 'S');
    expect(c.lastFinished!.sessionDate, '2026-09-20');
  });

  test('a resumed finish flags a PR against the baseline the draft carries', () async {
    final c = ActiveSessionController()
      ..seedForTest(draftWith(sessionId: 'S', sessionDate: '2026-09-20'));
    final exec = FakeExec();
    await c.finish(exec);
    final top = exec.calls.firstWhere(
        (call) => call.$1.startsWith('INSERT INTO sets') && call.$2[0] == 's1');
    expect(top.$2.sublist(8, 10), [1, 1]); // is_top_set, is_pr: 100 > 90
  });

  test('discard records no snapshot', () {
    final c = ActiveSessionController()..seedForTest(draftWith());
    c.discard();
    expect(c.lastFinished, isNull);
  });
}
```

- [ ] **Step 2: Write the failing addBlock real-DB test** — in `app/test/data/resume_integration_test.dart` add these imports:

```dart
import 'package:workout_tracker/data/exercise_repository.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
```

and this helper next to the other seed helpers:

```dart
  Future<void> seedExercise(String id, String name) => db.execute(
      'INSERT INTO exercises (id, slug, name, muscle_group, equip, compound, '
      'base_weight_kg, plate_step_kg, is_template) VALUES (?, ?, ?, ?, ?, 1, ?, ?, 0)',
      [id, '$name-$id', name, 'chest', 'barbell', '60.00', '2.50']);
```

and this group at the end of `main()`:

```dart
  group('addBlock baseline (real DB)', () {
    Future<ActiveSessionController> controllerWithBench({String? sessionId}) async {
      await seedExercise('bench', 'Bench');
      await seedSession('Y', '2026-09-22');
      await seedSet('y1', 'Y', 'bench', 1, '90.00', top: true);
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      final c = ActiveSessionController()
        ..seedForTest(SessionDraft(
          templateId: null, name: 'Upper A', focus: '',
          startedAt: DateTime(2026, 9, 23, 9), blocks: [],
          sessionId: sessionId, sessionDate: sessionId == null ? null : '2026-09-23',
        ));
      final bench = (await ExerciseRepository(db).byId('bench'))!;
      await c.addBlock(bench, sessionRepo: SessionRepository(db));
      return c;
    }

    test('an exercise added to a resumed workout is baselined without its own rows', () async {
      final c = await controllerWithBench(sessionId: 'S');
      expect(c.draft.blocks.single.bestKg, 90);
      expect(c.draft.blocks.single.lastTop!.date, '2026-09-22');
    });

    test('a fresh workout still sees every logged session', () async {
      final c = await controllerWithBench();
      expect(c.draft.blocks.single.bestKg, 100);
      expect(c.draft.blocks.single.lastTop!.date, '2026-09-23');
    });
  });
```

- [ ] **Step 3: Run to verify failure**

Run: `timeout 400 make -C app test TEST=test/session/finish_resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -30 /tmp/reps-test.log`
Expected: compile error — the getter `lastFinished` isn't defined.

- [ ] **Step 4: Implement** — in `app/lib/session/active_session_controller.dart`:

Add imports (keep the relative imports alphabetical):

```dart
import '../data/finished_session_store.dart';
import '../util/dates.dart';
```

In `addBlock`, replace the two lookup lines with:

```dart
    // A resumed workout's own finished rows stay in the DB until it is
    // finished again; exclude them so the PR baseline and the "Last" row are
    // the pre-workout ones (a fresh workout has no sessionId: no filter).
    final lastTop = await sessionRepo.lastTopSet(exercise.id,
        excludeSessionId: draft.sessionId);
    final bestKg = await sessionRepo.bestTopSet(exercise.id,
        excludeSessionId: draft.sessionId);
```

Replace the `// ── Finish ──` section's doc comment and `finish` method (:521-591) with:

```dart
  // ── Finish ────────────────────────────────────────────────────────────────

  /// Snapshot of the last successful [finish]; null before one, and never set
  /// by [discard]. The caller hands it to `SessionManager.recordFinished` once
  /// the write transaction has COMMITTED — [finish] runs, and notifies,
  /// inside the transaction, before the commit.
  FinishedSession? get lastFinished => _lastFinished;
  FinishedSession? _lastFinished;

  /// Persists the session to the local PowerSync DB, clears the draft store,
  /// and clears the in-memory draft.
  ///
  /// A fresh draft gets a new session id; a resumed draft (non-null
  /// `sessionId`) replaces its own session in place, on its original date.
  /// Returns the session id. The caller must wrap this in
  /// `db.writeTransaction((tx) => controller.finish(PowerSyncTxExecutor(tx)))`
  /// to ensure atomicity. Pass [draftStore] to also clear the on-disk draft
  /// (call with the same [DraftStore] used to save the session while it was active).
  Future<String> finish(SqlExecutor executor, {DraftStore? draftStore}) async {
    final d = draft;
    final now = DateTime.now();
    final resumed = d.sessionId != null;
    final sessionId = d.sessionId ?? uuid.v4();
    final dateIso = d.sessionDate ?? isoDate(now);
    final splitLabel =
        d.focus.isEmpty ? d.name : '${d.name} · ${d.focus}'; // omit empty focus

    // Collect all sets: warm-ups (is_warmup=true) then working, per block,
    // with set_number restarting per exercise.
    final sets = <SetWrite>[];
    for (final block in d.blocks) {
      var setNum = 1;
      final blockSets = <SetWrite>[];
      for (final s in block.warmupSets.where((s) => s.done)) {
        blockSets.add(SetWrite(
          id: s.id, exerciseId: block.exercise.id, setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2), reps: s.reps, rir: null, isWarmup: true,
        ));
      }
      for (final s in block.workingSets.where((s) => s.done)) {
        blockSets.add(SetWrite(
          id: s.id, exerciseId: block.exercise.id, setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2), reps: s.reps, rir: s.rir, isWarmup: false,
        ));
      }
      final topIdx = topSetIndex(blockSets);
      if (topIdx >= 0) {
        final top = blockSets[topIdx];
        final topWeight = double.tryParse(top.weightKg) ?? 0;
        final isPr = block.bestKg != null && topWeight > block.bestKg!;
        blockSets[topIdx] = SetWrite(
          id: top.id, exerciseId: top.exerciseId, setNumber: top.setNumber,
          weightKg: top.weightKg, reps: top.reps, rir: top.rir, isWarmup: top.isWarmup,
          isTopSet: true, isPr: isPr,
        );
      }
      sets.addAll(blockSets);
    }

    final elapsedAtFinish = now.difference(d.startedAt);
    final write = SessionWrite(
      id: sessionId,
      dateIso: dateIso,
      dayTemplateId: d.templateId,
      splitLabel: splitLabel,
      durationMin: (elapsedAtFinish.inSeconds / 60).round(),
      sets: sets,
    );

    if (resumed) {
      await replaceSession(executor, write);
    } else {
      await persistSession(executor, write);
    }

    _lastFinished = FinishedSession(
      sessionId: sessionId,
      sessionDate: dateIso,
      finishedAt: now,
      elapsedSeconds: elapsedAtFinish.inSeconds,
      draft: d.deepCopy(),
    );

    // Clear the on-disk draft (if a store is provided) then the in-memory state.
    _saveDebounce?.cancel();
    await draftStore?.clear();
    _draft = null;
    restStart = null;
    restTotal = 0;
    notifyListeners();

    return sessionId;
  }
```

(`discard()` is unchanged; it never touches `_lastFinished`.)

- [ ] **Step 5: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/session/finish_resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -30 /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/session/build_model_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Expected: all `All tests passed!`
Run analyze → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/session/active_session_controller.dart app/test/session/finish_resume_test.dart app/test/data/resume_integration_test.dart
git commit -m "feat(app): finish a resumed workout in place and snapshot every finish"
```

---

### Task 4: Resume rules — eligibility, card state, merge and restore

**Files:**
- Create: `app/lib/session/resume.dart`
- Test: `app/test/session/resume_test.dart` (create), `app/test/data/resume_integration_test.dart` (append a group)

**Interfaces:**
- Consumes: `FinishedSession`, `SessionDraft.deepCopy` (Task 1); `lastTopSet/bestTopSet(excludeSessionId:)` (Task 2).
- Produces (all top-level in `resume.dart`):
  - `const Duration resumeGrace` (1 hour).
  - `bool isResumable(FinishedSession? f, String sessionId, DateTime now)`.
  - `DateTime resumableUntil(FinishedSession f)`.
  - `enum SessionResumeState { none, available, inProgress }`.
  - `SessionResumeState resumeStateFor({required String? activeSessionId, required FinishedSession? lastFinished, required String sessionId, required DateTime now})`.
  - `typedef UnmatchedRows = ({String exerciseId, List<LoggedSet> rows});`
  - `({SessionDraft draft, List<UnmatchedRows> unmatched}) mergeLoggedSets(SessionDraft source, List<LoggedSet> rows)`.
  - `SetState loggedToSetState(LoggedSet r)`.
  - `Future<SessionDraft> restoreFinishedDraft(FinishedSession f, List<LoggedSet> rows, {required int? durationMin, required ExerciseRepository exerciseRepo, required SessionRepository sessionRepo, required DateTime now})`.

- [ ] **Step 1: Write the failing pure tests** — create `app/test/session/resume_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/resume.dart';

FinishedSession fin({String id = 'S', String date = '2026-09-23', DateTime? at, SessionDraft? draft}) =>
    FinishedSession(
      sessionId: id,
      sessionDate: date,
      finishedAt: at ?? DateTime(2026, 9, 23, 10, 0),
      elapsedSeconds: 2400,
      draft: draft ??
          SessionDraft(
            templateId: null, name: 'Upper A', focus: '',
            startedAt: DateTime(2026, 9, 23, 9, 20), blocks: [],
          ),
    );

Exercise ex(String id) => Exercise(
      id: id, name: id, slug: id, muscleGroup: 'chest',
      compound: true, plateStepKg: 2.5, isTemplate: false,
    );

BlockState block(String exId, List<SetState> warm, List<SetState> work) => BlockState(
      exercise: ex(exId),
      resolved: ResolvedSlot(
        exercise: ex(exId), workSets: work.length, warmupSets: warm.length,
        repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2,
      ),
      warmupSets: warm,
      workingSets: work,
      expanded: true,
      bestKg: 90,
    );

SetState set(String id, {double w = 100, int reps = 5, bool done = true, bool warmup = false}) =>
    SetState(id: id, weightKg: w, reps: reps, rir: warmup ? null : 1, isWarmup: warmup, done: done);

LoggedSet row(String id, String exId, int n, {double w = 100, int reps = 5, int? rir = 1, bool warmup = false}) =>
    LoggedSet(
      id: id, exerciseId: exId, setNumber: n, weightKg: w, reps: reps,
      rir: warmup ? null : rir, isWarmup: warmup, isTopSet: false, isPr: false,
    );

/// Snapshot: row block first (t1 done, t2 planned), then bench (w1, s1, s2
/// done, s3 planned), then dips (d1 done only).
SessionDraft snapshot() => SessionDraft(
      templateId: 'd1', name: 'Upper A', focus: 'Push',
      startedAt: DateTime(2026, 9, 23, 9), sessionId: null,
      blocks: [
        block('row', [], [set('t1', w: 50), set('t2', w: 50, done: false)]),
        block('bench', [set('w1', w: 40, warmup: true)],
            [set('s1'), set('s2', w: 95), set('s3', w: 95, done: false)]),
        block('dips', [], [set('d1', w: 0, reps: 12)]),
      ],
    );

/// The DB rows matching [snapshot] exactly (ordered like setsForSession:
/// exercise_id, set_number).
List<LoggedSet> unchangedRows() => [
      row('w1', 'bench', 1, w: 40, warmup: true),
      row('s1', 'bench', 2),
      row('s2', 'bench', 3, w: 95),
      row('d1', 'dips', 1, w: 0, reps: 12),
      row('t1', 'row', 1, w: 50),
    ];

void main() {
  group('isResumable', () {
    test('same calendar day', () {
      expect(isResumable(fin(), 'S', DateTime(2026, 9, 23, 22, 0)), isTrue);
    });
    test('00:20 after a 23:50 finish', () {
      expect(isResumable(fin(date: '2026-09-22', at: DateTime(2026, 9, 22, 23, 50)), 'S',
          DateTime(2026, 9, 23, 0, 20)), isTrue);
    });
    test('61 minutes after a previous-day finish', () {
      expect(isResumable(fin(date: '2026-09-22', at: DateTime(2026, 9, 22, 23, 50)), 'S',
          DateTime(2026, 9, 23, 0, 51)), isFalse);
    });
    test('re-finished after midnight: only the grace hour, not the whole next day', () {
      final f = fin(date: '2026-09-22', at: DateTime(2026, 9, 23, 0, 30));
      expect(isResumable(f, 'S', DateTime(2026, 9, 23, 1, 15)), isTrue);
      expect(isResumable(f, 'S', DateTime(2026, 9, 23, 12, 0)), isFalse);
    });
    test('wrong session or no snapshot', () {
      expect(isResumable(fin(), 'other', DateTime(2026, 9, 23, 10, 5)), isFalse);
      expect(isResumable(null, 'S', DateTime(2026, 9, 23, 10, 5)), isFalse);
    });
    test('a clock moved back counts as within the hour', () {
      expect(isResumable(fin(), 'S', DateTime(2026, 9, 22, 23, 0)), isTrue);
    });
  });

  group('resumableUntil', () {
    test('a daytime finish lasts until the end of its day', () {
      expect(resumableUntil(fin()), DateTime(2026, 9, 24));
    });
    test('a late finish lasts its grace hour past midnight', () {
      expect(resumableUntil(fin(date: '2026-09-22', at: DateTime(2026, 9, 22, 23, 50))),
          DateTime(2026, 9, 23, 0, 50));
    });
    test('a re-finish after midnight lasts only its grace hour', () {
      expect(resumableUntil(fin(date: '2026-09-22', at: DateTime(2026, 9, 23, 0, 30))),
          DateTime(2026, 9, 23, 1, 30));
    });
  });

  group('resumeStateFor', () {
    final now = DateTime(2026, 9, 23, 10, 5);
    test('none without a snapshot or a running resume', () {
      expect(resumeStateFor(activeSessionId: null, lastFinished: null, sessionId: 'S', now: now),
          SessionResumeState.none);
    });
    test('available while the snapshot is resumable', () {
      expect(resumeStateFor(activeSessionId: null, lastFinished: fin(), sessionId: 'S', now: now),
          SessionResumeState.available);
    });
    test('available even while a fresh workout runs (the tap explains why not)', () {
      // A fresh live workout has no sessionId.
      expect(resumeStateFor(activeSessionId: null, lastFinished: fin(), sessionId: 'S', now: now),
          SessionResumeState.available);
    });
    test('inProgress for the resumed session', () {
      expect(resumeStateFor(activeSessionId: 'S', lastFinished: null, sessionId: 'S', now: now),
          SessionResumeState.inProgress);
    });
    test('inProgress wins when the kept snapshot matches too', () {
      expect(resumeStateFor(activeSessionId: 'S', lastFinished: fin(), sessionId: 'S', now: now),
          SessionResumeState.inProgress);
    });
    test('a later finish supersedes an earlier workout of the same day', () {
      expect(resumeStateFor(activeSessionId: null, lastFinished: fin(id: 'B'), sessionId: 'A', now: now),
          SessionResumeState.none);
    });
  });

  group('mergeLoggedSets', () {
    test('unchanged rows keep every set, the block order and planned sets', () {
      final m = mergeLoggedSets(snapshot(), unchangedRows());
      expect(m.unmatched, isEmpty);
      expect(m.draft.blocks.map((b) => b.exercise.id), ['row', 'bench', 'dips']);
      final bench = m.draft.blocks[1];
      expect(bench.warmupSets.map((s) => s.id), ['w1']);
      expect(bench.workingSets.map((s) => s.id), ['s1', 's2', 's3']);
      expect(bench.workingSets.map((s) => s.done), [true, true, false]);
      expect(m.draft.blocks[0].workingSets.map((s) => s.id), ['t1', 't2']);
    });

    test('a History edit wins over the snapshot', () {
      final rows = unchangedRows()
        ..removeWhere((r) => r.id == 's2')
        ..add(row('s2', 'bench', 3, w: 97.5, reps: 6, rir: 2));
      final s2 = mergeLoggedSets(snapshot(), rows).draft.blocks[1].workingSets[1];
      expect(s2.weightKg, 97.5);
      expect(s2.reps, 6);
      expect(s2.rir, 2);
      expect(s2.done, isTrue);
    });

    test('a set deleted in History is dropped', () {
      final rows = unchangedRows()..removeWhere((r) => r.id == 's2');
      expect(mergeLoggedSets(snapshot(), rows).draft.blocks[1].workingSets.map((s) => s.id),
          ['s1', 's3']);
    });

    test('sets added in History join their block in set order', () {
      final rows = unchangedRows()
        ..add(row('h2', 'bench', 6, w: 80, reps: 10))
        ..add(row('h1', 'bench', 5, w: 80, reps: 10));
      final bench = mergeLoggedSets(snapshot(), rows).draft.blocks[1];
      expect(bench.workingSets.map((s) => s.id), ['s1', 's2', 's3', 'h1', 'h2']);
      expect(bench.workingSets.last.done, isTrue);
    });

    test('a set added in History for another exercise is reported as unmatched', () {
      final rows = unchangedRows()..add(row('x1', 'curl', 1, w: 20));
      final m = mergeLoggedSets(snapshot(), rows);
      expect(m.unmatched.single.exerciseId, 'curl');
      expect(m.unmatched.single.rows.single.id, 'x1');
      expect(m.draft.blocks.map((b) => b.exercise.id), ['row', 'bench', 'dips']);
    });

    test('a block whose sets were all deleted is dropped; one with planned sets stays', () {
      final rows = unchangedRows()..removeWhere((r) => r.id == 'd1' || r.id == 't1');
      final m = mergeLoggedSets(snapshot(), rows);
      expect(m.draft.blocks.map((b) => b.exercise.id), ['row', 'bench']);
      expect(m.draft.blocks[0].workingSets.map((s) => s.id), ['t2']);
    });

    test('an unticked snapshot set that was logged later counts as done, once', () {
      final rows = unchangedRows()..add(row('s3', 'bench', 4, w: 100, reps: 4));
      final bench = mergeLoggedSets(snapshot(), rows).draft.blocks[1];
      expect(bench.workingSets.map((s) => s.id), ['s1', 's2', 's3']);
      expect(bench.workingSets.last.done, isTrue);
      expect(bench.workingSets.last.reps, 4);
    });

    test('merging leaves the snapshot untouched', () {
      final source = snapshot();
      final rows = unchangedRows()
        ..removeWhere((r) => r.id == 's2')
        ..add(row('s2', 'bench', 3, w: 97.5));
      mergeLoggedSets(source, rows);
      expect(source.blocks[1].workingSets[1].weightKg, 95);
    });
  });
}
```

- [ ] **Step 2: Write the failing restore real-DB tests** — in `app/test/data/resume_integration_test.dart` add imports:

```dart
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/resume.dart';
```

and this group at the end of `main()`:

```dart
  group('restoreFinishedDraft (real DB)', () {
    Exercise bench() => const Exercise(
          id: 'bench', name: 'Bench', slug: 'bench', muscleGroup: 'chest',
          compound: true, plateStepKg: 2.5, isTemplate: false,
        );

    BlockState benchBlock() => BlockState(
          exercise: bench(),
          resolved: ResolvedSlot(
            exercise: bench(), workSets: 3, warmupSets: 0,
            repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2,
          ),
          warmupSets: [],
          workingSets: [
            SetState(id: 's1', weightKg: 100, reps: 5, rir: 1, isWarmup: false, done: true),
            SetState(id: 's3', weightKg: 95, reps: 5, rir: 1, isWarmup: false, done: false),
          ],
          expanded: true,
          bestKg: 90,
        );

    FinishedSession finished(List<BlockState> blocks) => FinishedSession(
          sessionId: 'S',
          sessionDate: '2026-09-23',
          finishedAt: DateTime(2026, 9, 23, 10, 0),
          elapsedSeconds: 2400,
          draft: SessionDraft(
            templateId: null, name: 'Upper A', focus: '',
            startedAt: DateTime(2026, 9, 23, 9, 20), blocks: blocks,
          ),
        );

    test('restores the snapshot, baselines a History-added exercise without this session, continues the clock', () async {
      await seedExercise('bench', 'Bench');
      await seedExercise('curl', 'Curl');
      await seedSession('Y', '2026-09-22');
      await seedSet('y2', 'Y', 'curl', 1, '20.00', top: true);
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('x1', 'S', 'curl', 1, '22.50', top: true); // added in History
      final repo = SessionRepository(db);
      final now = DateTime(2026, 9, 23, 10, 10);

      final d = await restoreFinishedDraft(
        finished([benchBlock()]),
        await repo.setsForSession('S'),
        durationMin: 40,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: now,
      );

      expect(d.sessionId, 'S');
      expect(d.sessionDate, '2026-09-23');
      expect(d.startedAt, now.subtract(const Duration(seconds: 2400)));
      expect(d.blocks.map((b) => b.exercise.id), ['bench', 'curl']);
      expect(d.blocks[0].workingSets.map((s) => s.id), ['s1', 's3']);
      expect(d.blocks[0].bestKg, 90); // the snapshot's pre-workout baseline
      final curl = d.blocks[1];
      expect(curl.exercise.name, 'Curl');
      expect(curl.workingSets.single.id, 'x1');
      expect(curl.workingSets.single.done, isTrue);
      expect(curl.bestKg, 20); // not this session's own 22.5
      expect(curl.lastTop!.date, '2026-09-22');
    });

    test('drops a planned-only block whose exercise was deleted; keeps logged sets of a deleted exercise', () async {
      await seedExercise('bench', 'Bench');
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      await seedSet('z1', 'S', 'gone2', 1, '30.00', top: true);
      final ghost = Exercise(
        id: 'gone1', name: 'Ghost', slug: 'ghost', muscleGroup: 'chest',
        compound: false, plateStepKg: 2.5, isTemplate: false,
      );
      final planned = BlockState(
        exercise: ghost,
        resolved: ResolvedSlot(exercise: ghost, workSets: 1, warmupSets: 0,
            repLow: 8, repHigh: 12, rirLow: 1, rirHigh: 2),
        warmupSets: [],
        workingSets: [SetState(id: 'g1', weightKg: 10, reps: 10, rir: 1, isWarmup: false, done: false)],
        expanded: true,
      );
      final repo = SessionRepository(db);
      final d = await restoreFinishedDraft(
        finished([benchBlock(), planned]),
        await repo.setsForSession('S'),
        durationMin: 40,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: DateTime(2026, 9, 23, 10, 10),
      );
      expect(d.blocks.map((b) => b.exercise.id), ['bench', 'gone2']);
      expect(d.blocks[1].exercise.name, 'gone2'); // placeholder, rows kept
      expect(d.blocks[1].workingSets.single.id, 'z1');
    });

    test('a stale snapshot cannot roll the clock back', () async {
      await seedExercise('bench', 'Bench');
      await seedSession('S', '2026-09-23');
      await seedSet('s1', 'S', 'bench', 1, '100.00', top: true);
      final repo = SessionRepository(db);
      final now = DateTime(2026, 9, 23, 10, 10);
      final d = await restoreFinishedDraft(
        finished([benchBlock()]),
        await repo.setsForSession('S'),
        durationMin: 55,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: repo,
        now: now,
      );
      expect(d.startedAt, now.subtract(const Duration(minutes: 55)));
    });
  });
```

- [ ] **Step 3: Run to verify failure**

Run: `timeout 400 make -C app test TEST=test/session/resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — `resume.dart` not found.

- [ ] **Step 4: Implement** — create `app/lib/session/resume.dart`:

```dart
import 'dart:math' show max;

import '../data/day_template_repository.dart'; // resolveSlot
import '../data/exercise_repository.dart';
import '../data/finished_session_store.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../util/dates.dart';
import 'active_session_controller.dart';

// Resuming a just-finished workout: which finished session may be resumed,
// and how its live draft is rebuilt from the finish-time snapshot plus the
// rows now in the database.

/// How long after its last finish a workout stays resumable once the
/// calendar day has changed ("finished at 23:50, noticed at 00:20").
const resumeGrace = Duration(hours: 1);

/// Whether the finished session [sessionId] may be resumed at [now]: [f] is
/// its snapshot, and the session belongs to the current calendar day or was
/// finished within [resumeGrace].
///
/// The day branch uses the session's own date, not the finish time: a
/// workout re-finished just after midnight keeps its original date and must
/// not stay resumable for the whole next day. A negative difference (the
/// clock moved back) counts as within the grace period.
bool isResumable(FinishedSession? f, String sessionId, DateTime now) {
  if (f == null || f.sessionId != sessionId) return false;
  if (f.sessionDate == isoDate(now)) return true;
  return now.difference(f.finishedAt) <= resumeGrace;
}

/// The moment [f] stops being resumable: the later of the end of its
/// session's day and its grace period.
DateTime resumableUntil(FinishedSession f) {
  final day = DateTime.tryParse('${f.sessionDate}T00:00:00') ?? f.finishedAt;
  final endOfDay = DateTime(day.year, day.month, day.day + 1);
  final endOfGrace = f.finishedAt.add(resumeGrace);
  return endOfDay.isAfter(endOfGrace) ? endOfDay : endOfGrace;
}

/// What a History card offers for its session.
enum SessionResumeState {
  /// Nothing — the usual edit/add/delete actions.
  none,

  /// "Resume workout", plus the usual actions.
  available,

  /// The session is the running (resumed) workout: only "Resume workout",
  /// which reopens it.
  inProgress,
}

/// The [SessionResumeState] of the History card for [sessionId].
/// [activeSessionId] is the running workout's `sessionId` (null for none, or
/// for a fresh workout).
SessionResumeState resumeStateFor({
  required String? activeSessionId,
  required FinishedSession? lastFinished,
  required String sessionId,
  required DateTime now,
}) {
  // Checked first: during a resumed workout the kept snapshot matches too.
  if (activeSessionId != null && activeSessionId == sessionId) {
    return SessionResumeState.inProgress;
  }
  if (isResumable(lastFinished, sessionId, now)) return SessionResumeState.available;
  return SessionResumeState.none;
}

/// Logged rows no snapshot block could take (their exercise has no block).
typedef UnmatchedRows = ({String exerciseId, List<LoggedSet> rows});

/// A logged row as a done set of the live workout.
SetState loggedToSetState(LoggedSet r) => SetState(
      id: r.id,
      weightKg: r.weightKg,
      reps: r.reps,
      rir: r.isWarmup ? null : r.rir,
      isWarmup: r.isWarmup,
      done: true,
    );

/// Merges the finish-time [source] draft with the session's logged [rows].
/// The DB is the truth for what was logged; the snapshot supplies only what
/// the DB cannot hold (planned sets, order, targets, baselines).
///
/// Keyed on set id, never on the snapshot's `done` flag:
/// - a snapshot set whose id is in [rows] → done, with the row's weight,
///   reps and RIR (a History edit wins; a set logged after a newer, lost
///   snapshot is still recognised);
/// - a done snapshot set missing from [rows] → dropped (deleted in History);
/// - an undone snapshot set missing from [rows] → kept (planned);
/// - a row matching no snapshot set (added in History) → appended, done, to
///   the first block of its exercise in `set_number` order, or reported in
///   `unmatched` when no block has that exercise;
/// - a block left with no sets at all → dropped.
///
/// Pure: [source] is not modified.
({SessionDraft draft, List<UnmatchedRows> unmatched}) mergeLoggedSets(
  SessionDraft source,
  List<LoggedSet> rows,
) {
  final copy = source.deepCopy();
  final byId = {for (final r in rows) r.id: r};
  final matched = <String>{};

  List<SetState> reconcile(List<SetState> sets) {
    final out = <SetState>[];
    for (final s in sets) {
      final r = byId[s.id];
      if (r != null) {
        matched.add(s.id);
        s
          ..weightKg = r.weightKg
          ..reps = r.reps
          ..rir = s.isWarmup ? null : r.rir
          ..done = true;
        out.add(s);
      } else if (!s.done) {
        out.add(s);
      }
    }
    return out;
  }

  for (final b in copy.blocks) {
    b.warmupSets = reconcile(b.warmupSets);
    b.workingSets = reconcile(b.workingSets);
  }

  // Rows no snapshot set knows, grouped by exercise in first-appearance order.
  final extra = <String, List<LoggedSet>>{};
  for (final r in rows) {
    if (!matched.contains(r.id)) extra.putIfAbsent(r.exerciseId, () => []).add(r);
  }

  final unmatched = <UnmatchedRows>[];
  for (final entry in extra.entries) {
    final added = [...entry.value]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    BlockState? target;
    for (final b in copy.blocks) {
      if (b.exercise.id == entry.key) {
        target = b;
        break;
      }
    }
    if (target == null) {
      unmatched.add((exerciseId: entry.key, rows: added));
      continue;
    }
    for (final r in added) {
      (r.isWarmup ? target.warmupSets : target.workingSets).add(loggedToSetState(r));
    }
  }

  return (
    draft: SessionDraft(
      templateId: copy.templateId,
      name: copy.name,
      focus: copy.focus,
      startedAt: copy.startedAt,
      blocks: copy.blocks.where((b) => b.allSets.isNotEmpty).toList(),
      sessionId: copy.sessionId,
      sessionDate: copy.sessionDate,
    ),
    unmatched: unmatched,
  );
}

/// Rebuilds the live draft for resuming the finished session [f] from its
/// snapshot and its current [rows] (see [mergeLoggedSets]).
///
/// - A block with nothing logged whose exercise was deleted since is dropped:
///   its planned sets were never stored, and ticking them would upload set
///   PUTs the server's exercise foreign key rejects. (A block with logged
///   sets keeps its exercise: deleting an exercise is refused while logged
///   sets reference it.)
/// - Each unmatched group becomes a block of exactly its logged rows, with an
///   exercise placeholder named after its id if the exercise is gone (the
///   fallback History shows), and a baseline that ignores this session.
/// - The clock continues from the finish: `startedAt` is [now] minus the
///   longer of the snapshot's elapsed time and the row's [durationMin], so a
///   stale snapshot cannot roll it back.
Future<SessionDraft> restoreFinishedDraft(
  FinishedSession f,
  List<LoggedSet> rows, {
  required int? durationMin,
  required ExerciseRepository exerciseRepo,
  required SessionRepository sessionRepo,
  required DateTime now,
}) async {
  final merged = mergeLoggedSets(f.draft, rows);
  final blocks = <BlockState>[];
  for (final b in merged.draft.blocks) {
    final hasLogged = b.allSets.any((s) => s.done);
    if (!hasLogged && await exerciseRepo.byId(b.exercise.id) == null) continue;
    blocks.add(b);
  }

  for (final g in merged.unmatched) {
    final exercise =
        await exerciseRepo.byId(g.exerciseId) ?? _placeholderExercise(g.exerciseId);
    final resolved =
        resolveSlot(Slot(exerciseId: g.exerciseId, position: blocks.length), exercise);
    final bestKg = await sessionRepo.bestTopSet(g.exerciseId, excludeSessionId: f.sessionId);
    final lastTop = await sessionRepo.lastTopSet(g.exerciseId, excludeSessionId: f.sessionId);
    blocks.add(BlockState(
      exercise: exercise,
      resolved: resolved,
      warmupSets: [for (final r in g.rows) if (r.isWarmup) loggedToSetState(r)],
      workingSets: [for (final r in g.rows) if (!r.isWarmup) loggedToSetState(r)],
      expanded: true,
      bestKg: bestKg,
      lastTop: lastTop,
    ));
  }

  final elapsed = max(f.elapsedSeconds, (durationMin ?? 0) * 60);
  return SessionDraft(
    templateId: merged.draft.templateId,
    name: merged.draft.name,
    focus: merged.draft.focus,
    startedAt: now.subtract(Duration(seconds: elapsed)),
    blocks: blocks,
    sessionId: f.sessionId,
    sessionDate: f.sessionDate,
  );
}

Exercise _placeholderExercise(String id) => Exercise(
      id: id,
      name: id,
      slug: '',
      muscleGroup: '',
      compound: false,
      plateStepKg: 2.5,
      isTemplate: false,
    );
```

- [ ] **Step 5: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/session/resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -30 /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -30 /tmp/reps-test.log`
Expected: both `All tests passed!`. Analyze → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/session/resume.dart app/test/session/resume_test.dart app/test/data/resume_integration_test.dart
git commit -m "feat(app): rules for resuming a finished workout and rebuilding its draft"
```

---

### Task 5: SessionManager owns the snapshot and guards launches

**Files:**
- Modify: `app/lib/session/session_manager.dart`
- Create: `app/test/support/fake_stores.dart`
- Test: `app/test/session/session_manager_finished_test.dart` (create)

**Interfaces:**
- Consumes: `FinishedSession`, `FinishedSessionStore` (Task 1); `isResumable`, `resumableUntil` (Task 4).
- Produces:
  - `SessionManager({FinishedSessionStore? finishedStore})`.
  - `FinishedSession? get lastFinished`.
  - `Future<void> recordFinished(FinishedSession f, {DateTime? now})` — adopts synchronously (in-memory + notify) before its first await, then persists.
  - `Future<void> loadLastFinished({DateTime? now})`.
  - `void forgetFinished(String sessionId)`.
  - `bool tryBeginLaunch()`, `void endLaunch()`, `bool get launching`.
  - `register()` asserts no other controller is active.
  - Test support: `FakeDraftStore` (fields `SessionDraft? saved`, `int saveCount`, `int clearCount`) and `FakeFinishedSessionStore({FinishedSession? stored, bool failSave, bool failLoad})` (fields `stored`, `clearCount`) in `app/test/support/fake_stores.dart`.

- [ ] **Step 1: Create the fakes** — `app/test/support/fake_stores.dart`:

```dart
import 'dart:io';

import 'package:workout_tracker/data/active_session_draft.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

/// In-memory [DraftStore] that keeps the last saved draft.
class FakeDraftStore extends DraftStore {
  SessionDraft? saved;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<void> save(SessionDraft draft) async {
    saved = draft;
    saveCount++;
  }

  @override
  Future<SessionDraft?> load() async => saved;

  @override
  Future<void> clear() async {
    saved = null;
    clearCount++;
  }
}

/// In-memory [FinishedSessionStore] that can be told to fail.
class FakeFinishedSessionStore extends FinishedSessionStore {
  FakeFinishedSessionStore({this.stored, this.failSave = false, this.failLoad = false});

  FinishedSession? stored;
  bool failSave;
  bool failLoad;
  int clearCount = 0;

  @override
  Future<void> save(FinishedSession f) async {
    if (failSave) throw const FileSystemException('disk full');
    stored = f;
  }

  @override
  Future<FinishedSession?> load() async {
    if (failLoad) throw const FileSystemException('unreadable');
    return stored;
  }

  @override
  Future<void> clear() async {
    stored = null;
    clearCount++;
  }
}
```

- [ ] **Step 2: Write the failing tests** — `app/test/session/session_manager_finished_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/finished_session_store.dart';
import 'package:workout_tracker/data/session_writer.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_manager.dart';

import '../support/fake_stores.dart';

class _NoopExec implements SqlExecutor {
  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {}
}

FinishedSession fin({String id = 'S', String date = '2026-09-23', DateTime? at}) => FinishedSession(
      sessionId: id,
      sessionDate: date,
      finishedAt: at ?? DateTime(2026, 9, 23, 10, 0),
      elapsedSeconds: 2400,
      draft: SessionDraft(
        templateId: null, name: 'Upper A', focus: '',
        startedAt: DateTime(2026, 9, 23, 9, 20), blocks: [],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordFinished adopts, notifies and persists the snapshot', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    var notifies = 0;
    m.addListener(() => notifies++);
    final f = fin();

    final pending = m.recordFinished(f, now: f.finishedAt);
    expect(m.lastFinished, same(f)); // adopted before the first await
    await pending;
    expect(notifies, 1);
    expect(store.stored, same(f));
  });

  test('a failed save clears the store, so an older snapshot cannot survive', () async {
    final store = FakeFinishedSessionStore(stored: fin(at: DateTime(2026, 9, 23, 9, 0)), failSave: true);
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    final f = fin();
    await m.recordFinished(f, now: f.finishedAt);
    expect(store.stored, isNull);
    expect(store.clearCount, 1);
    expect(m.lastFinished, same(f)); // still resumable in this process
  });

  test('finishing a registered controller alone adopts nothing', () async {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    final c = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
    m.register(c);
    await c.finish(_NoopExec());
    expect(c.lastFinished, isNotNull);
    expect(m.lastFinished, isNull);
    expect(m.hasActive, isFalse);
  });

  test('loadLastFinished keeps a resumable snapshot', () async {
    final f = fin();
    final m = SessionManager(finishedStore: FakeFinishedSessionStore(stored: f));
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 23, 18, 0));
    expect(m.lastFinished?.sessionId, 'S');
  });

  test('loadLastFinished drops and deletes an expired snapshot', () async {
    final store = FakeFinishedSessionStore(stored: fin());
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 25, 8, 0));
    expect(m.lastFinished, isNull);
    expect(store.stored, isNull);
  });

  test('loadLastFinished survives a store that throws', () async {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore(failLoad: true));
    addTearDown(m.dispose);
    await m.loadLastFinished(now: DateTime(2026, 9, 23, 10, 5));
    expect(m.lastFinished, isNull);
  });

  test('forgetFinished drops only a matching session, and notifies', () async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    addTearDown(m.dispose);
    final f = fin();
    await m.recordFinished(f, now: f.finishedAt);
    var notifies = 0;
    m.addListener(() => notifies++);

    m.forgetFinished('other');
    expect(m.lastFinished, same(f));
    expect(notifies, 0);

    m.forgetFinished('S');
    await Future<void>.delayed(Duration.zero);
    expect(m.lastFinished, isNull);
    expect(notifies, 1);
    expect(store.stored, isNull);
  });

  testWidgets('the snapshot is forgotten when its window closes', (tester) async {
    final store = FakeFinishedSessionStore();
    final m = SessionManager(finishedStore: store);
    // Finished 23:50 → resumable until 00:50 (grace past midnight).
    final f = fin(date: '2026-09-23', at: DateTime(2026, 9, 23, 23, 50));
    await m.recordFinished(f, now: f.finishedAt);

    await tester.pump(const Duration(minutes: 59));
    expect(m.lastFinished, isNotNull);
    await tester.pump(const Duration(minutes: 2));
    expect(m.lastFinished, isNull);
    expect(store.stored, isNull);
    m.dispose();
  });

  test('tryBeginLaunch refuses a second launch until endLaunch', () {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    expect(m.tryBeginLaunch(), isTrue);
    expect(m.launching, isTrue);
    expect(m.tryBeginLaunch(), isFalse);
    m.endLaunch();
    expect(m.launching, isFalse);
    expect(m.tryBeginLaunch(), isTrue);
  });

  test('register refuses a second controller while one is active', () {
    final m = SessionManager(finishedStore: FakeFinishedSessionStore());
    addTearDown(m.dispose);
    final a = ActiveSessionController()..seedEmpty(name: 'A', focus: '');
    final b = ActiveSessionController()..seedEmpty(name: 'B', focus: '');
    m.register(a);
    m.register(a); // re-registering the same controller is harmless
    expect(() => m.register(b), throwsAssertionError);
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `timeout 400 make -C app test TEST=test/session/session_manager_finished_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — no named parameter `finishedStore`.

- [ ] **Step 4: Implement** — in `app/lib/session/session_manager.dart`:

Replace the imports with:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/active_session_draft.dart';
import '../data/finished_session_store.dart';
import 'active_session_controller.dart';
import 'resume.dart';
import 'workout_notification.dart';
```

Directly after `class SessionManager extends ChangeNotifier with WidgetsBindingObserver {` add:

```dart
  SessionManager({FinishedSessionStore? finishedStore})
      : _finishedStore = finishedStore ?? FinishedSessionStore();

```

Replace `register` with:

```dart
  void register(ActiveSessionController c) {
    assert(_active == null || identical(_active, c),
        'A workout is already active: check hasActive and take tryBeginLaunch first.');
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
```

Add, after `resumeFromDraft`:

```dart
  // ── Launch guard ────────────────────────────────────────────────────────

  bool _launching = false;

  /// True while a start or resume is building its controller.
  bool get launching => _launching;

  /// Claims the single launch slot; false if a start or resume is already in
  /// flight (a double tap). Pair with [endLaunch] in a `finally`. Take it
  /// synchronously, before the first await, or two taps both get through and
  /// register two workouts.
  bool tryBeginLaunch() {
    if (_launching) return false;
    _launching = true;
    return true;
  }

  void endLaunch() => _launching = false;

  // ── Finished-workout snapshot ───────────────────────────────────────────

  final FinishedSessionStore _finishedStore;
  FinishedSession? _lastFinished;
  Timer? _expiry;

  /// The last workout finished on this device while it may still be resumed
  /// from History (see `resume.dart`); null otherwise.
  FinishedSession? get lastFinished => _lastFinished;

  /// Adopts [f] as the resumable snapshot and persists it.
  ///
  /// Call ONLY after the finish's write transaction has committed: `finish()`
  /// runs and notifies inside the transaction, before the commit, and
  /// adopting then would let a failed commit replace a good snapshot with one
  /// describing writes that never happened. A failed save clears the file, so
  /// an older snapshot of the same session cannot be resumed after a restart.
  Future<void> recordFinished(FinishedSession f, {DateTime? now}) async {
    _adopt(f, now ?? DateTime.now());
    notifyListeners();
    try {
      await _finishedStore.save(f);
    } catch (_) {
      await _clearFinishedStore();
    }
  }

  /// Boot path: restores the persisted snapshot if it is still resumable, and
  /// deletes it otherwise (or if it cannot be read).
  Future<void> loadLastFinished({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final FinishedSession? f;
    try {
      f = await _finishedStore.load();
    } catch (_) {
      return;
    }
    if (f == null) return;
    if (!isResumable(f, f.sessionId, t)) {
      await _clearFinishedStore();
      return;
    }
    _adopt(f, t);
    notifyListeners();
  }

  /// Drops the snapshot if it belongs to [sessionId] — the session was
  /// deleted, or its resume window closed.
  void forgetFinished(String sessionId) {
    if (_lastFinished?.sessionId != sessionId) return;
    _expiry?.cancel();
    _expiry = null;
    _lastFinished = null;
    notifyListeners();
    unawaited(_clearFinishedStore());
  }

  /// Holds [f] and arms a one-shot timer for when it stops being resumable,
  /// so the Resume action disappears on its own.
  void _adopt(FinishedSession f, DateTime now) {
    _lastFinished = f;
    _expiry?.cancel();
    final wait = resumableUntil(f).difference(now);
    _expiry = Timer(wait.isNegative ? Duration.zero : wait,
        () => forgetFinished(f.sessionId));
  }

  Future<void> _clearFinishedStore() async {
    try {
      await _finishedStore.clear();
    } catch (_) {
      // Best effort: an undeletable stale file is dropped again at next boot.
    }
  }
```

In `dispose()`, add `_expiry?.cancel();` as the first line.

- [ ] **Step 5: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/session/session_manager_finished_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -30 /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/session/session_manager_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Expected: both `All tests passed!`. Analyze → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/session/session_manager.dart app/test/support/fake_stores.dart app/test/session/session_manager_finished_test.dart
git commit -m "feat(app): keep the last finished workout resumable and guard session launches"
```

---

### Task 6: Launching a resume, and guarding Start

**Files:**
- Modify: `app/lib/shell/session_launcher.dart`
- Test: `app/test/data/resume_integration_test.dart` (append a group)

**Interfaces:**
- Consumes: `restoreFinishedDraft`, `isResumable` (Task 4); `SessionManager.lastFinished/tryBeginLaunch/endLaunch/forgetFinished/register` (Task 5); `SessionRepository.sessionById/setsForSession` (Task 2).
- Produces:
  - `Future<ActiveSessionController?> prepareResume(SessionManager manager, String sessionId, {required SessionRepository sessionRepo, required ExerciseRepository exerciseRepo, required DraftStore draftStore, DateTime? now})`.
  - `Future<void> resumeFinishedSession(BuildContext context, String sessionId)`.

- [ ] **Step 1: Write the failing end-to-end tests** — in `app/test/data/resume_integration_test.dart` add imports:

```dart
import 'package:workout_tracker/session/session_manager.dart';
import 'package:workout_tracker/shell/session_launcher.dart';
import 'package:workout_tracker/util/dates.dart';

import '../support/fake_stores.dart';
```

and this group at the end of `main()`:

```dart
  group('resume end to end (real DB)', () {
    final today = isoDate(DateTime.now());
    final yesterday = isoDate(DateTime.now().subtract(const Duration(days: 1)));

    Exercise exercise(String id, String name) => Exercise(
          id: id, name: name, slug: '$name-$id', muscleGroup: 'chest',
          compound: true, baseWeightKg: 60, plateStepKg: 2.5, isTemplate: false,
        );

    BlockState block(Exercise e, List<SetState> warm, List<SetState> work, double best) => BlockState(
          exercise: e,
          resolved: ResolvedSlot(
            exercise: e, workSets: work.length, warmupSets: warm.length,
            repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2,
          ),
          warmupSets: warm,
          workingSets: work,
          expanded: true,
          bestKg: best,
          lastTop: (weight: best, reps: 5, date: yesterday),
        );

    SetState set(String id, double w, {bool done = true, bool warmup = false}) => SetState(
        id: id, weightKg: w, reps: warmup ? 8 : 5, rir: warmup ? null : 1, isWarmup: warmup, done: done);

    /// Row block FIRST — 'row' sorts after 'bench', so a restore that took its
    /// order from the DB (exercise_id order) would put bench first.
    SessionDraft freshDraft() => SessionDraft(
          templateId: 'd1', name: 'Upper A', focus: 'Push',
          startedAt: DateTime.now().subtract(const Duration(minutes: 40)),
          blocks: [
            block(exercise('row', 'Row'), [], [set('t1', 52.5), set('t2', 52.5, done: false)], 50),
            block(exercise('bench', 'Bench'), [set('w1', 40, warmup: true)],
                [set('s1', 100), set('s2', 95), set('s3', 95, done: false)], 90),
          ],
        );

    late SessionManager m;
    late FakeDraftStore drafts;

    setUp(() async {
      await seedDay('d1');
      await seedExercise('bench', 'Bench');
      await seedExercise('row', 'Row');
      await seedSession('Y', yesterday, day: 'd1');
      await seedSet('y1', 'Y', 'bench', 1, '90.00', top: true);
      await seedSet('y2', 'Y', 'row', 1, '50.00', top: true);
      m = SessionManager(finishedStore: FakeFinishedSessionStore());
      drafts = FakeDraftStore();
    });

    tearDown(() => m.dispose());

    Future<FinishedSession> finish(ActiveSessionController c) async {
      await db.writeTransaction((tx) => c.finish(PowerSyncTxExecutor(tx)));
      final f = c.lastFinished!;
      await m.recordFinished(f, now: f.finishedAt);
      return f;
    }

    Future<FinishedSession> finishFresh() {
      final c = ActiveSessionController()..seedForTest(freshDraft());
      m.register(c);
      return finish(c);
    }

    Future<ActiveSessionController?> resume(FinishedSession f, {DateTime? now}) => prepareResume(
          m, f.sessionId,
          sessionRepo: SessionRepository(db),
          exerciseRepo: ExerciseRepository(db),
          draftStore: drafts,
          now: now ?? f.finishedAt.add(const Duration(minutes: 5)),
        );

    test('finish → resume → finish again leaves one session with the original id and date', () async {
      final f = await finishFresh();
      final c = (await resume(f))!;

      expect(m.active, same(c));
      final d = c.draft;
      expect(d.sessionId, f.sessionId);
      expect(d.blocks.map((b) => b.exercise.id), ['row', 'bench']);
      expect(drafts.saved?.sessionId, f.sessionId); // persisted before register
      // The clock continues from the finish: resumed 5 minutes later, the
      // workout time is still the elapsed time at finish.
      expect(d.startedAt,
          f.finishedAt.add(const Duration(minutes: 5)).subtract(Duration(seconds: f.elapsedSeconds)));
      final s3 = d.blocks[1].workingSets.last;
      expect(s3.id, 's3');
      expect(s3.done, isFalse);

      c.toggleDone(d.blocks[1], s3);
      await finish(c);

      final sessions = await db.getAll('SELECT id, date FROM sessions WHERE id != ?', ['Y']);
      expect(sessions.single['id'], f.sessionId);
      expect(sessions.single['date'], today);
      final sets = await db.getAll(
          'SELECT id, is_top_set, is_pr FROM sets WHERE session_id = ? ORDER BY id', [f.sessionId]);
      expect(sets.map((r) => r['id']), ['s1', 's2', 's3', 't1', 'w1']);
      final s1 = sets.firstWhere((r) => r['id'] == 's1');
      expect(s1['is_top_set'], 1);
      expect(s1['is_pr'], 1); // 100 > the pre-workout 90
      expect(m.hasActive, isFalse);
      expect(m.lastFinished!.sessionId, f.sessionId);
    });

    test('the re-finish uploads a session PATCH, set DELETEs, set PUTs — never a session DELETE', () async {
      final f = await finishFresh();
      final c = (await resume(f))!;
      await drainCrud();
      await finish(c);

      final ops = await nextCrud();
      expect(ops.map((e) => '${e.op.name}:${e.table}').toList(), [
        'patch:sessions',
        ...List.filled(4, 'delete:sets'), // w1 s1 s2 t1
        ...List.filled(4, 'put:sets'),
      ]);
      expect(ops.first.opData!.containsKey('day_template_id'), isFalse);
    });

    test('a training day deleted before the re-finish does not cost the session', () async {
      final f = await finishFresh();
      await db.execute('DELETE FROM day_templates WHERE id = ?', ['d1']);
      final c = (await resume(f))!;
      await drainCrud();
      await finish(c);

      final ops = await nextCrud();
      expect(ops.where((e) => e.table == 'sessions').map((e) => e.op), [UpdateType.patch]);
      expect((await db.getAll('SELECT id FROM sessions WHERE id = ?', [f.sessionId])).length, 1);
    });

    test('a session row that vanished during the resumed workout is re-created', () async {
      final f = await finishFresh();
      final c = (await resume(f))!;
      await db.writeTransaction((tx) async {
        await tx.execute('DELETE FROM sets WHERE session_id = ?', [f.sessionId]);
        await tx.execute('DELETE FROM sessions WHERE id = ?', [f.sessionId]);
      });
      await finish(c);

      final row = await db.get('SELECT date FROM sessions WHERE id = ?', [f.sessionId]);
      expect(row['date'], today);
      expect((await db.getAll('SELECT id FROM sets WHERE session_id = ?', [f.sessionId])).length, 4);
    });

    test('History edits between finish and resume survive', () async {
      final f = await finishFresh();
      final repo = SessionRepository(db);
      await repo.updateSet('s2', weightKg: '97.50', reps: 6, rir: 2);
      await repo.deleteSet('t1');
      final added = await repo.addSet(f.sessionId, 'bench',
          weightKg: '80.00', reps: 10, rir: null, isWarmup: false);

      final d = (await resume(f))!.draft;
      final bench = d.blocks.firstWhere((b) => b.exercise.id == 'bench');
      expect(bench.workingSets.map((s) => s.id), ['s1', 's2', 's3', added]);
      expect(bench.workingSets[1].weightKg, 97.5);
      expect(bench.workingSets[1].reps, 6);
      expect(bench.workingSets.last.done, isTrue);
      final row = d.blocks.firstWhere((b) => b.exercise.id == 'row');
      expect(row.workingSets.map((s) => s.id), ['t2']); // t1 deleted, t2 planned
    });

    test('discarding a resumed workout leaves the finished rows untouched and resumable', () async {
      final f = await finishFresh();
      Future<List<Map<String, Object?>>> rows() async => [
            for (final r in await db.getAll('SELECT * FROM sessions ORDER BY id')) Map.of(r),
            for (final r in await db.getAll('SELECT * FROM sets ORDER BY id')) Map.of(r),
          ];
      final before = await rows();

      final c = (await resume(f))!;
      final bench = c.draft.blocks[1];
      c.toggleDone(bench, bench.workingSets.last);
      c.discard();

      expect(await rows(), before);
      expect(m.hasActive, isFalse);
      expect(m.lastFinished, same(f));
      expect(await resume(f), isNotNull);
    });

    test('two overlapping resume calls register exactly one controller', () async {
      final f = await finishFresh();
      final results = await Future.wait([resume(f), resume(f)]);
      final controllers = results.whereType<ActiveSessionController>().toList();
      expect(controllers.length, 1);
      expect(m.active, same(controllers.single));
      expect(m.launching, isFalse);
    });

    test('an expired snapshot, a running workout or a vanished session is not resumed', () async {
      final f = await finishFresh();
      expect(await resume(f, now: f.finishedAt.add(const Duration(days: 2))), isNull);

      final other = ActiveSessionController()..seedEmpty(name: 'Custom', focus: '');
      m.register(other);
      expect(await resume(f), isNull);
      other.discard();

      await SessionRepository(db).deleteSession(f.sessionId);
      expect(await resume(f), isNull);
      expect(m.lastFinished, isNull); // forgotten once its session is gone
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — `prepareResume` isn't defined.

- [ ] **Step 3: Implement** — in `app/lib/shell/session_launcher.dart`:

Add the import:

```dart
import '../session/resume.dart';
```

Replace the body of `startSession` from `// A workout is already running → resume it instead of starting a new one.` to the end of the function with:

```dart
  // A workout is already running → resume it instead of starting a new one.
  if (manager.hasActive) {
    await openActiveSession(context, manager);
    return;
  }

  // A second tap while this one is still building must not register a second
  // workout.
  if (!manager.tryBeginLaunch()) return;
  try {
    final controller = ActiveSessionController(draftStore: DraftStore());

    if (template != null) {
      await controller.buildFromTemplate(
        template,
        exerciseRepo: ExerciseRepository(db),
        sessionRepo: SessionRepository(db),
      );
    } else {
      controller.seedEmpty(name: customName, focus: '');
    }

    if (manager.hasActive) {
      controller.dispose(); // cancels its pending autosave
      return;
    }
    manager.register(controller);
  } finally {
    manager.endLaunch();
  }

  if (!context.mounted) return;
  await openActiveSession(context, manager);
}
```

Add after `openActiveSession`:

```dart
/// Restores the finished workout [sessionId] as the live workout, without
/// navigating, and returns its controller — or null when it cannot be resumed
/// right now: another workout is active, a launch is already running (a
/// double tap), its snapshot is no longer resumable, or the session is gone.
///
/// Writes nothing to the database: the finished rows are replaced only when
/// the resumed workout is finished again (see `replaceSession`).
Future<ActiveSessionController?> prepareResume(
  SessionManager manager,
  String sessionId, {
  required SessionRepository sessionRepo,
  required ExerciseRepository exerciseRepo,
  required DraftStore draftStore,
  DateTime? now,
}) async {
  final t = now ?? DateTime.now();
  final f = manager.lastFinished;
  // Every guard runs synchronously, before the first await: two taps must not
  // both get through and register two copies of the same session.
  if (manager.hasActive || f == null || !isResumable(f, sessionId, t)) return null;
  if (!manager.tryBeginLaunch()) return null;
  try {
    final session = await sessionRepo.sessionById(sessionId);
    if (session == null) {
      manager.forgetFinished(sessionId); // deleted (or synced away) since
      return null;
    }
    final rows = await sessionRepo.setsForSession(sessionId);
    final draft = await restoreFinishedDraft(
      f,
      rows,
      durationMin: session.durationMin,
      exerciseRepo: exerciseRepo,
      sessionRepo: sessionRepo,
      now: t,
    );
    if (manager.hasActive) return null;
    // Persist before registering, so process death right after Resume boots
    // straight back into the resumed workout.
    await draftStore.save(draft);
    final controller = ActiveSessionController.fromDraft(draft, draftStore: draftStore);
    manager.register(controller);
    return controller;
  } finally {
    manager.endLaunch();
  }
}

/// History's Resume action: restores the finished workout [sessionId] and
/// opens it. Callers handle "another workout is running" themselves (it needs
/// a dialog); here that case, like every other refusal, is a silent no-op.
Future<void> resumeFinishedSession(BuildContext context, String sessionId) async {
  final manager = context.read<SessionManager>();
  final controller = await prepareResume(
    manager,
    sessionId,
    sessionRepo: SessionRepository(db),
    exerciseRepo: ExerciseRepository(db),
    draftStore: DraftStore(),
  );
  if (controller == null || !context.mounted) return;
  await openActiveSession(context, manager);
}
```

- [ ] **Step 4: Run the tests and analyze**

Run: `timeout 400 make -C app test TEST=test/data/resume_integration_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`
Expected: `All tests passed!`. Analyze → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/shell/session_launcher.dart app/test/data/resume_integration_test.dart
git commit -m "feat(app): resume a finished workout as the live workout without a double launch"
```

---

### Task 7: Strings, icon, finish/discard wiring and boot

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app_it.arb`, `app_de.arb`, `app_es.arb`
- Modify: `app/lib/theme/icons.dart`
- Modify: `app/lib/session/resume.dart` (add `discardDialogCopy`)
- Modify: `app/lib/session/active_session_screen.dart` (`_handleClose` :123-148, `_handleFinish` :152-180)
- Modify: `app/lib/main.dart:88`
- Test: `app/test/session/resume_test.dart` (append a group)

**Interfaces:**
- Consumes: `ActiveSessionController.lastFinished` (Task 3), `SessionManager.recordFinished/loadLastFinished` (Task 5).
- Produces: `({String title, String message}) discardDialogCopy(AppLocalizations l, SessionDraft draft)`; `WIcons.resume`; l10n getters `historyResumeWorkout`, `historyResumeBlockedTitle`, `historyResumeBlockedMessage`, `sessionDiscardChangesTitle`, `sessionDiscardChangesMessage`.

- [ ] **Step 1: Add the strings.** In each ARB file insert the three `history*` keys directly after its `historyDeleteSetMessage` line, and the two `session*` keys directly after its `sessionKeepGoing` line (mind the trailing commas):

`app_en.arb`:
```json
  "historyResumeWorkout": "Resume workout",
  "historyResumeBlockedTitle": "Workout in progress",
  "historyResumeBlockedMessage": "Finish or discard your current workout before resuming another.",
```
```json
  "sessionDiscardChangesTitle": "Discard changes?",
  "sessionDiscardChangesMessage": "The workout stays in History as it was when you finished it.",
```

`app_it.arb`:
```json
  "historyResumeWorkout": "Riprendi allenamento",
  "historyResumeBlockedTitle": "Allenamento in corso",
  "historyResumeBlockedMessage": "Termina o scarta l'allenamento in corso prima di riprenderne un altro.",
```
```json
  "sessionDiscardChangesTitle": "Scartare le modifiche?",
  "sessionDiscardChangesMessage": "L'allenamento resta nella cronologia com'era quando l'hai terminato.",
```

`app_de.arb`:
```json
  "historyResumeWorkout": "Training fortsetzen",
  "historyResumeBlockedTitle": "Training läuft",
  "historyResumeBlockedMessage": "Beende oder verwirf dein laufendes Training, bevor du ein anderes fortsetzt.",
```
```json
  "sessionDiscardChangesTitle": "Änderungen verwerfen?",
  "sessionDiscardChangesMessage": "Das Training bleibt im Verlauf so, wie es beim Beenden war.",
```

`app_es.arb`:
```json
  "historyResumeWorkout": "Reanudar entrenamiento",
  "historyResumeBlockedTitle": "Entrenamiento en curso",
  "historyResumeBlockedMessage": "Termina o descarta tu entrenamiento actual antes de reanudar otro.",
```
```json
  "sessionDiscardChangesTitle": "¿Descartar los cambios?",
  "sessionDiscardChangesMessage": "El entrenamiento queda en el historial tal como estaba al terminarlo.",
```

Then regenerate: `timeout 400 make -C app get > /tmp/reps-get.log 2>&1; echo "EXIT=$?"`

- [ ] **Step 2: Write the failing copy test** — append to `app/test/session/resume_test.dart` (add `import 'package:flutter/widgets.dart' show Locale;` and `import 'package:workout_tracker/l10n/app_localizations.dart';` at the top), inside `main()`:

```dart
  group('discardDialogCopy', () {
    final en = lookupAppLocalizations(const Locale('en'));
    SessionDraft d({String? sessionId}) => SessionDraft(
          templateId: null, name: 'Upper A', focus: '',
          startedAt: DateTime(2026, 9, 23, 9), blocks: [], sessionId: sessionId,
        );

    test('a fresh workout warns that its logged sets will be lost', () {
      final copy = discardDialogCopy(en, d());
      expect(copy.title, 'Discard workout?');
      expect(copy.message, 'Your logged sets will be lost.');
    });

    test('a resumed workout says History keeps the finished version', () {
      final copy = discardDialogCopy(en, d(sessionId: 'S'));
      expect(copy.title, 'Discard changes?');
      expect(copy.message, 'The workout stays in History as it was when you finished it.');
    });

    test('Italian', () {
      final copy = discardDialogCopy(lookupAppLocalizations(const Locale('it')), d(sessionId: 'S'));
      expect(copy.title, 'Scartare le modifiche?');
    });
  });
```

Run: `timeout 400 make -C app test TEST=test/session/resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — `discardDialogCopy` isn't defined.

- [ ] **Step 3: Implement the helper and icon.** In `app/lib/session/resume.dart` add `import '../l10n/app_localizations.dart';` and append:

```dart
/// Title and message of the discard confirm. Discarding a resumed workout is
/// not destructive — its finished session stays in History untouched — so it
/// must not warn that the logged sets will be lost.
({String title, String message}) discardDialogCopy(
        AppLocalizations l, SessionDraft draft) =>
    draft.sessionId != null
        ? (title: l.sessionDiscardChangesTitle, message: l.sessionDiscardChangesMessage)
        : (title: l.sessionDiscardTitle, message: l.sessionDiscardMessage);
```

In `app/lib/theme/icons.dart` add after `refresh`:

```dart
  static const IconData resume = Icons.play_arrow_rounded;
```

- [ ] **Step 4: Wire the session screen.** In `app/lib/session/active_session_screen.dart` add `import 'resume.dart';` (with the other relative imports). In `_handleClose`, replace the `showWConfirm` call's title/message lines so the block reads:

```dart
    final l = AppLocalizations.of(context);
    final copy = discardDialogCopy(l, controller.draft);
    final confirmed = await showWConfirm(
      context,
      title: copy.title,
      message: copy.message,
      cancelLabel: l.sessionKeepGoing,
      confirmLabel: l.commonDiscard,
      destructive: true,
    );
```

In `_handleFinish`, directly after the `final sessionId = await db.writeTransaction(...);` statement, insert:

```dart
      // Only now, after the COMMIT, may this finish become resumable:
      // finish() notified inside the transaction, before it committed.
      final finished = controller.lastFinished;
      final manager = _manager;
      if (finished != null && manager != null) {
        unawaited(manager.recordFinished(finished));
      }
```

(`dart:async` is already imported in this file for `Timer`; `unawaited` comes from it.)

- [ ] **Step 5: Boot.** In `app/lib/main.dart`, directly after `await sessionManager.resumeFromDraft();` add:

```dart
  await sessionManager.loadLastFinished();
```

- [ ] **Step 6: Run and analyze**

Run: `timeout 400 make -C app test TEST=test/session/resume_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Run: `timeout 400 make -C app test TEST=test/l10n/arb_parity_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log`
Expected: both `All tests passed!`. Analyze → `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/l10n/app_en.arb app/lib/l10n/app_it.arb app/lib/l10n/app_de.arb app/lib/l10n/app_es.arb app/lib/theme/icons.dart app/lib/session/resume.dart app/lib/session/active_session_screen.dart app/lib/main.dart app/test/session/resume_test.dart
git commit -m "feat(app): adopt the finish snapshot after commit and soften discard for resumed workouts"
```

---

### Task 8: History — Resume action, in-progress card, keyed cards, quiet reload

**Files:**
- Modify: `app/lib/ui/history_screen.dart` (imports, `HistoryScreen` build/_buildBody :52-158, `SessionCard` :347-554, `_ExerciseBlocks` :556-748)
- Test: `app/test/ui/history_session_card_test.dart` (create)

**Interfaces:**
- Consumes: `resumeStateFor`, `SessionResumeState` (Task 4); `SessionManager.lastFinished/forgetFinished/hasActive/active` (Task 5); `resumeFinishedSession`, `openActiveSession` (Task 6); `groupSetsIntoBlocks` (Task 2); l10n keys and `WIcons.resume` (Task 7).
- Produces: `SessionCard({Key? key, required HistorySessionRow session, required Map<String, Exercise> catalogMap, required SessionRepository sessionRepo, required UnitService units, SessionResumeState resumeState = SessionResumeState.none, VoidCallback? onResume, VoidCallback? onDeleted})`; public stateless `SessionCardBody`. Action keys: `ValueKey('history-resume')`, `ValueKey('history-add-exercise')`, `ValueKey('history-delete-session')`.

- [ ] **Step 1: Write the failing widget tests** — `app/test/ui/history_session_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/data/session_repository.dart';
import 'package:workout_tracker/session/resume.dart';
import 'package:workout_tracker/theme/icons.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

/// Only `setsForSession` is real, and it completes at once: the card's body
/// has no database to deadlock `pumpWidget` on.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository(this.sets);
  List<LoggedSet> sets;
  int loads = 0;

  @override
  Future<List<LoggedSet>> setsForSession(String sessionId) {
    loads++;
    return Future.value(sets);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HistorySessionRow sessionRow() => HistorySessionRow(
      id: 'S', date: '2026-09-23', splitLabel: 'Upper A · Push', durationMin: 40,
      exerciseCount: 1, prCount: 0, tonnageKg: 500,
    );

LoggedSet logged(double w) => LoggedSet(
      id: 's1', exerciseId: 'bench', setNumber: 1, weightKg: w, reps: 5, rir: 1,
      isWarmup: false, isTopSet: true, isPr: false,
    );

final catalog = {
  'bench': const Exercise(
    id: 'bench', name: 'Bench', slug: 'bench', muscleGroup: 'chest',
    compound: true, plateStepKg: 2.5, isTemplate: false,
  ),
};

final resumeAction = find.byKey(const ValueKey('history-resume'));
final addAction = find.byKey(const ValueKey('history-add-exercise'));
final deleteAction = find.byKey(const ValueKey('history-delete-session'));

Widget card(FakeSessionRepository repo,
        {HistorySessionRow? session,
        SessionResumeState state = SessionResumeState.none,
        VoidCallback? onResume}) =>
    wrapL10n(SessionCard(
      session: session ?? sessionRow(),
      catalogMap: catalog,
      sessionRepo: repo,
      units: UnitService(),
      resumeState: state,
      onResume: onResume,
    ));

Future<void> expand(WidgetTester tester) async {
  await tester.tap(find.byIcon(WIcons.chevron).first); // the header chevron
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('an available session offers Resume first, then Add exercise and Delete', (tester) async {
    var resumed = 0;
    await tester.pumpWidget(card(FakeSessionRepository([logged(100)]),
        state: SessionResumeState.available, onResume: () => resumed++));
    await expand(tester);

    expect(resumeAction, findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);
    expect(addAction, findsOneWidget);
    expect(deleteAction, findsOneWidget);
    expect(tester.getTopLeft(resumeAction).dy, lessThan(tester.getTopLeft(addAction).dy));

    await tester.tap(resumeAction);
    expect(resumed, 1);
  });

  testWidgets('an in-progress session offers only Resume, and its rows are not editable', (tester) async {
    await tester.pumpWidget(card(FakeSessionRepository([logged(100)]),
        state: SessionResumeState.inProgress, onResume: () {}));
    await expand(tester);

    expect(resumeAction, findsOneWidget);
    expect(addAction, findsNothing);
    expect(deleteAction, findsNothing);
    expect(find.text('Bench'), findsOneWidget);
    // Only the header chevron: tappable exercise rows carry their own.
    expect(find.byIcon(WIcons.chevron), findsOneWidget);
  });

  testWidgets('without a resume state the card keeps its usual actions', (tester) async {
    await tester.pumpWidget(card(FakeSessionRepository([logged(100)])));
    await expand(tester);

    expect(resumeAction, findsNothing);
    expect(addAction, findsOneWidget);
    expect(deleteAction, findsOneWidget);
    expect(find.byIcon(WIcons.chevron), findsNWidgets(2));
  });

  testWidgets('a session with no sets still shows its actions', (tester) async {
    await tester.pumpWidget(card(FakeSessionRepository([]), state: SessionResumeState.available));
    await expand(tester);

    expect(resumeAction, findsOneWidget);
    expect(deleteAction, findsOneWidget);
  });

  testWidgets('a new row object reloads the sets without blanking the card', (tester) async {
    final repo = FakeSessionRepository([logged(100)]);
    await tester.pumpWidget(card(repo));
    await expand(tester);
    expect(find.textContaining('100', findRichText: true), findsOneWidget);

    repo.sets = [logged(102.5)];
    await tester.pumpWidget(card(repo, session: sessionRow())); // a NEW row object
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(repo.loads, 2);
    expect(find.textContaining('102.5', findRichText: true), findsOneWidget);
  });

  testWidgets('the same row object does not reload', (tester) async {
    final repo = FakeSessionRepository([logged(100)]);
    final row = sessionRow();
    await tester.pumpWidget(card(repo, session: row));
    await expand(tester);
    await tester.pumpWidget(card(repo, session: row, state: SessionResumeState.available));
    await tester.pumpAndSettle();
    expect(repo.loads, 1);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `timeout 400 make -C app test TEST=test/ui/history_session_card_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/reps-test.log`
Expected: compile error — no named parameter `resumeState`.

- [ ] **Step 3: Implement.** In `app/lib/ui/history_screen.dart`:

Add imports (keep them grouped with the existing relative imports):

```dart
import '../data/finished_session_store.dart';
import '../session/resume.dart';
import '../session/session_manager.dart';
import '../shell/session_launcher.dart';
```

In `_HistoryScreenState.build`, after `final tokens = context.tokens;` add, and pass both values on to `_buildBody`:

```dart
    // Only what the cards need: the manager also notifies on every set tick
    // and rest change of a running workout.
    final (activeSessionId, lastFinished) =
        context.select<SessionManager, (String?, FinishedSession?)>(
            (m) => (m.active?.draftOrNull?.sessionId, m.lastFinished));
```

so the innermost builder returns `_buildBody(context, tokens, units, sessions, catalogMap, activeSessionId, lastFinished)`, and `_buildBody` gains the parameters `String? activeSessionId, FinishedSession? lastFinished` after `catalogMap`.

In `_buildBody`, replace the per-session `Padding(...)` with (keyed on the list's direct child, which is where `ListView` matches children by key):

```dart
          for (final session in groups[wk]!)
            Padding(
              key: ValueKey(session.id),
              padding: const EdgeInsets.only(bottom: 9),
              child: SessionCard(
                session: session,
                catalogMap: catalogMap,
                sessionRepo: _sessionRepo,
                units: units,
                resumeState: resumeStateFor(
                  activeSessionId: activeSessionId,
                  lastFinished: lastFinished,
                  sessionId: session.id,
                  now: now,
                ),
                onResume: () => _onResume(session.id),
                onDeleted: () =>
                    context.read<SessionManager>().forgetFinished(session.id),
              ),
            ),
```

Add to `_HistoryScreenState`:

```dart
  /// The card's Resume action. The state is re-derived at tap time: the card
  /// may have been built before the resume window closed.
  Future<void> _onResume(String sessionId) async {
    final manager = context.read<SessionManager>();
    final state = resumeStateFor(
      activeSessionId: manager.active?.draftOrNull?.sessionId,
      lastFinished: manager.lastFinished,
      sessionId: sessionId,
      now: DateTime.now(),
    );
    switch (state) {
      case SessionResumeState.inProgress:
        await openActiveSession(context, manager);
      case SessionResumeState.none:
        // Expired since the card was built: forgetting it notifies, and this
        // screen rebuilds without the button.
        manager.forgetFinished(sessionId);
      case SessionResumeState.available:
        if (manager.hasActive) {
          final l = AppLocalizations.of(context);
          await showWDialog<void>(
            context,
            title: l.historyResumeBlockedTitle,
            message: l.historyResumeBlockedMessage,
            actions: [WDialogAction(label: l.commonOk, value: null)],
          );
          return;
        }
        await resumeFinishedSession(context, sessionId);
    }
  }
```

`SessionCard`: add the constructor parameters `this.resumeState = SessionResumeState.none, this.onResume, this.onDeleted,` and fields:

```dart
  /// What the expanded footer offers (see [SessionResumeState]).
  final SessionResumeState resumeState;
  final VoidCallback? onResume;

  /// Called after the session was deleted from this card.
  final VoidCallback? onDeleted;
```

and construct the expanded body as:

```dart
                  ? _ExerciseBlocks(
                      session: widget.session,
                      catalogMap: widget.catalogMap,
                      sessionRepo: widget.sessionRepo,
                      units: widget.units,
                      resumeState: widget.resumeState,
                      onResume: widget.onResume,
                      onDeleted: widget.onDeleted,
                    )
```

Replace `_ExerciseBlocks` and `_ExerciseBlocksState` entirely with:

```dart
class _ExerciseBlocks extends StatefulWidget {
  const _ExerciseBlocks({
    required this.session,
    required this.catalogMap,
    required this.sessionRepo,
    required this.units,
    required this.resumeState,
    this.onResume,
    this.onDeleted,
  });

  final HistorySessionRow session;
  final Map<String, Exercise> catalogMap;
  final SessionRepository sessionRepo;
  final UnitService units;
  final SessionResumeState resumeState;
  final VoidCallback? onResume;
  final VoidCallback? onDeleted;

  @override
  State<_ExerciseBlocks> createState() => _ExerciseBlocksState();
}

class _ExerciseBlocksState extends State<_ExerciseBlocks> {
  late Future<List<ExerciseBlockData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ExerciseBlocks oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every watchSessionStats emission follows a commit on sessions/sets and
    // builds NEW row objects (reListenable does not dedupe), so a new object
    // means this session's sets may have changed — including RIR or warm-up
    // changes no aggregate reflects, like a resumed workout finished again.
    if (!identical(oldWidget.session, widget.session)) _future = _load();
  }

  Future<List<ExerciseBlockData>> _load() => widget.sessionRepo
      .setsForSession(widget.session.id)
      .then(groupSetsIntoBlocks);

  /// Quiet reload: the FutureBuilder keeps showing the previous blocks until
  /// the new ones arrive, so the card never blanks to a spinner or replays
  /// its Reveal rows.
  void _reload() => setState(() => _future = _load());

  /// Opens the per-exercise set editor, then reloads.
  Future<void> _editExercise(ExerciseBlockData block) async {
    final exercise = widget.catalogMap[block.exerciseId];
    if (exercise == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SetEditorSheet(
        block: block,
        exercise: exercise,
        sessionId: widget.session.id,
        sessionRepo: widget.sessionRepo,
        units: widget.units,
      ),
    );
    if (mounted) _reload();
  }

  /// Picks an exercise and seeds one working set so it appears in the session.
  /// The user then taps the new block to edit/add more sets.
  Future<void> _addExercise() async {
    final exId = await showExerciseSheet(
      context,
      exercises: widget.catalogMap.values.toList(),
      current: null,
      showBodyweight: false,
    );
    if (exId == null || exId == kBodyweightSentinel) return;
    final ex = widget.catalogMap[exId];
    await widget.sessionRepo.addSet(
      widget.session.id,
      exId,
      weightKg: '0.00',
      reps: ex?.defaultRepLow ?? 8,
      rir: null,
      isWarmup: false,
    );
    if (mounted) _reload();
  }

  Future<void> _deleteSession() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.historyDeleteSessionTitle,
      message: l.historyDeleteSessionMessage,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    // The watchSessionStats stream updates the list automatically afterwards.
    await widget.sessionRepo.deleteSession(widget.session.id);
    widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FutureBuilder<List<ExerciseBlockData>>(
      future: _future,
      builder: (context, snap) {
        final blocks = snap.data;
        // Spinner only for the very first load; a reload keeps the old data.
        if (blocks == null && snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.faint,
                ),
              ),
            ),
          );
        }
        final inProgress = widget.resumeState == SessionResumeState.inProgress;
        return SessionCardBody(
          blocks: blocks ?? const [],
          catalogMap: widget.catalogMap,
          units: widget.units,
          resumeState: widget.resumeState,
          onResume: widget.onResume,
          // The running workout is where an in-progress session is edited; a
          // History edit here would be overwritten by its next finish.
          onEditExercise: inProgress ? null : _editExercise,
          onAddExercise: _addExercise,
          onDeleteSession: _deleteSession,
        );
      },
    );
  }
}

/// The expanded body of a [SessionCard]: the per-exercise rows plus the
/// footer actions. Stateless and database-free. The footer renders even for a
/// session with no sets, so it can still be resumed or deleted.
class SessionCardBody extends StatelessWidget {
  const SessionCardBody({
    super.key,
    required this.blocks,
    required this.catalogMap,
    required this.units,
    this.resumeState = SessionResumeState.none,
    this.onResume,
    this.onEditExercise,
    this.onAddExercise,
    this.onDeleteSession,
  });

  final List<ExerciseBlockData> blocks;
  final Map<String, Exercise> catalogMap;
  final UnitService units;
  final SessionResumeState resumeState;
  final VoidCallback? onResume;

  /// Null makes the exercise rows read-only.
  final ValueChanged<ExerciseBlockData>? onEditExercise;
  final VoidCallback? onAddExercise;
  final VoidCallback? onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final edit = onEditExercise;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        children: [
          Divider(color: tokens.line, height: 1, thickness: 1),
          const SizedBox(height: 8),
          for (final block in blocks)
            Reveal(
              key: ValueKey(block.exerciseId),
              child: _BlockRow(
                block: block,
                catalogMap: catalogMap,
                units: units,
                onTap: edit == null ? null : () => edit(block),
              ),
            ),
          const SizedBox(height: 6),
          if (resumeState != SessionResumeState.none)
            _InlineAction(
              key: const ValueKey('history-resume'),
              icon: WIcons.resume,
              label: l.historyResumeWorkout,
              color: tokens.accent,
              onTap: onResume,
            ),
          if (resumeState != SessionResumeState.inProgress) ...[
            _InlineAction(
              key: const ValueKey('history-add-exercise'),
              icon: WIcons.plus,
              label: l.sessionAddExercise,
              color: tokens.accent,
              onTap: onAddExercise,
            ),
            const SizedBox(height: 8),
            Divider(color: tokens.line, height: 1, thickness: 1),
            const SizedBox(height: 8),
            _InlineAction(
              key: const ValueKey('history-delete-session'),
              icon: WIcons.trash,
              label: l.historyDeleteSession,
              color: tokens.danger,
              onTap: onDeleteSession,
              verticalPadding: 0,
            ),
          ],
        ],
      ),
    );
  }
}

/// A centred inline text action (icon + mono label) in the card footer.
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.verticalPadding = 6,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: WorkoutType.mono(size: 11, weight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
```

Also update the stale doc comment on `_SetEditorSheet` — replace `/// Never writes is_top_set / is_pr — the server recomputes those on sync.` with `/// Re-derives is_top_set locally on every write (see SessionRepository.updateSet); is_pr is left to the server.`

- [ ] **Step 4: Run and analyze**

Run: `timeout 400 make -C app test TEST=test/ui/history_session_card_test.dart > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -40 /tmp/reps-test.log`
Expected: `All tests passed!`. Analyze → `No issues found!`

- [ ] **Step 5: Full suite**

Run: `timeout 600 make -C app test > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -5 /tmp/reps-test.log`
Expected: `All tests passed!` with more than 293 tests.

- [ ] **Step 6: Commit**

```bash
git add app/lib/ui/history_screen.dart app/test/ui/history_session_card_test.dart
git commit -m "feat(app): resume a just-finished workout from its History card"
```

---

### Task 9: Documentation, version and whole-branch verification

**Files:**
- Modify: `app/AGENTS.md` (Hard-won rules → Data; Tests)
- Modify: `app/pubspec.yaml:4`

- [ ] **Step 1: Record the new rules** — in `app/AGENTS.md`, append to the **Data** list:

```markdown
- **Resumed workouts** (`SessionDraft.sessionId != null`): `finish()` goes through `replaceSession`, which UPDATEs the session row and DELETE+INSERTs its sets with the same ids — it must NEVER delete and re-insert the session row: a re-insert PUT the server rejects (e.g. a training day deleted since fails the `day_template_id` FK) after a DELETE it accepted loses the whole already-synced workout. The finish snapshot (`FinishedSession`) is adopted by `SessionManager.recordFinished` only AFTER the write transaction commits — `finish()` notifies inside the transaction, before COMMIT. Every `lastTopSet`/`bestTopSet` lookup made while a resumed draft is live passes `excludeSessionId`, or the workout becomes its own PR baseline. Session inserts bind `day_template_id` through `(SELECT id FROM day_templates WHERE id = ?)`.
- `SessionManager.register` asserts that no other controller is active; every start/resume takes `tryBeginLaunch()` synchronously before its first await and releases it in `finally`.
```

and to the **Tests** list:

```markdown
- `SessionCard`/`SessionCardBody` ARE widget-testable: the deadlock is the real database, not the widget. Inject a `FakeSessionRepository implements SessionRepository` whose `setsForSession` returns a completed future (`noSuchMethod` covers the rest) — see `test/ui/history_session_card_test.dart`.
```

- [ ] **Step 2: Commit the docs**

```bash
git add app/AGENTS.md
git commit -m "docs(app): record the resume-in-place and snapshot-after-commit rules"
```

- [ ] **Step 3: Bump the version** — in `app/pubspec.yaml` change `version: 0.13.0+29` to `version: 0.14.0+30`, then:

```bash
git add app/pubspec.yaml
git commit -m "chore(app): bump version to 0.14.0"
```

- [ ] **Step 4: Final verification**

Run: `timeout 400 make -C app analyze > /tmp/reps-analyze.log 2>&1; echo "EXIT=$?"; tail -3 /tmp/reps-analyze.log` → `No issues found!`
Run: `timeout 600 make -C app test > /tmp/reps-test.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/reps-test.log; tail -3 /tmp/reps-test.log` → `All tests passed!`
Run: `timeout 900 make -C app build > /tmp/reps-build.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/reps-build.log` → the Linux bundle builds.

- [ ] **Step 5: Whole-branch adversarial review** of `git diff main...HEAD` against the spec, then fix what survives verification (each fix its own commit, TDD).

- [ ] **Step 6: Ask the user before merging, pushing or tagging.** When approved: `git checkout main && git merge --no-ff feat/resume-finished-workout -m "feat(app): resume a just-finished workout from History (v0.14.0)"`, then `git tag v0.14.0` and push `main` and the tag (the release skill automates this). Device checks before tagging: spec §15.

---

## Self-Review

**Spec coverage:**
- §2 snapshot (record/adopt-after-commit/own/expiry/failed-save clear) → Tasks 1, 3, 5, 7.
- §3 eligibility + expiry mechanism → Task 4 (`isResumable`, `resumableUntil`), Task 5 (timer), Task 8 (tap → `forgetFinished`).
- §4 guard, restore, merge, baselines, deleted-exercise rules, clock floor → Tasks 2, 3, 4, 6.
- §5 replace in place, original date, upstream ops → Tasks 2, 3, 6.
- §6 discard copy → Task 7; discard leaves rows → Task 6.
- §7 History states, handler order, keyed cards, `SessionCardBody`, quiet identity reload, `groupSetsIntoBlocks` → Task 8 (+ Task 2).
- §8 boot → Task 7.
- §9.1 rest round trip → Task 1; §9.2 draft tolerant load → Task 1; §9.3 keys → Task 8; §9.4 empty footer → Task 8; §9.5 quiet reload → Task 8; §9.6 day subquery → Task 2; §9.7 Start guard → Task 6.
- §11 strings → Task 7. §12 tests → every task. §15 release → Task 9.

**Type consistency:** `FinishedSession` fields (`sessionId`, `sessionDate`, `finishedAt`, `elapsedSeconds`, `draft`) are identical in Tasks 1, 3, 4, 5, 6. `SessionResumeState {none, available, inProgress}` in Tasks 4 and 8. `groupSetsIntoBlocks` in Tasks 2 and 8. `prepareResume(manager, sessionId, {sessionRepo, exerciseRepo, draftStore, now})` in Task 6 and its test. `excludeSessionId` named parameter in Tasks 2, 3, 4.

**Known weak points:** `HistoryScreen` itself (the `context.select`, `_onResume` switch, the key on the list child) is not widget-tested — mounting it over a real DB hangs the binding; it is covered by review and device checks 1-5, 8 and 11. The notification chronometer after resume is device-only (check 9).
