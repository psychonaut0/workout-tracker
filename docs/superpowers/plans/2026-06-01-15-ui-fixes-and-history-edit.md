# UI Fixes + History Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix seven reported issues — three logic/data bugs (Progress top-set shows 0, finishing saves un-done sets, history not editable) and four UI/UX bugs (status-bar overlap, FAB glow direction, uneven "This week" cards, a spurious Bodyweight row + non-draggable exercise sheet).

**Architecture:** Mostly localized fixes in existing widgets/repos. The one cross-cutting change: `is_top_set` (which drives Progress) is currently computed only by the server on sync, so local/offline data never gets it — we compute it client-side on save AND backfill existing local rows. History editing is purely client-side (server PATCH/DELETE + PR-recompute already exist).

**Tech Stack:** Flutter 3.44 (fvm), PowerSync, provider. Run via `make -C app <target>`. `uuid` = the singleton from `package:powersync/powersync.dart`.

**Branch:** `ui-fixes-and-history-edit` (off `main`).

**Grounding facts (verified — do not re-derive):**
- `is_top_set`/`is_pr` are server-only (`session_writer.dart:88` comment; server logic in `server/internal/api/sync_upload.go:583-622` — top set = heaviest non-warmup per (session,exercise), tie-break `weight_kg DESC, reps DESC, set_number ASC, id ASC`; `is_pr` = top set whose weight strictly exceeds the max non-warmup weight in strictly-earlier-dated sessions). Progress (`progress_repository.dart:18-28`) gates on `is_top_set=1` with NO fallback → 0 for unflagged local rows. History is fine because `groupIntoBlocks` (`session_repository.dart:147-152`) falls back to the heaviest set.
- `finish()` (`active_session_controller.dart:452-477`) persists ALL sets, ignoring each set's `done` flag (`SetState.done`, controller:99).
- `SetWrite` (`session_writer.dart:52-61`): `{id, exerciseId, setNumber, weightKg(String), reps, rir(int?), isWarmup}`. `persistSession` (`session_writer.dart:94-125`) inserts `sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup)`.
- Server PATCH/DELETE for sets/sessions already implemented (`sync_upload.go` `applySet` :334-429, `applySession` :174-214) and recomputes PRs. Client has NO update/delete methods yet.
- Plan screen already handles the status bar via `MediaQuery.paddingOf(context).top` (`plan_screen.dart:64-74`); Today/History/Progress do not.

---

## Task 1: Finish saves only done sets + stamps `is_top_set`/`is_pr` client-side

**Files:**
- Modify: `app/lib/data/session_writer.dart` (add `isTopSet`/`isPr` to `SetWrite`; add `topSetIndex` pure helper; extend the `sets` INSERT)
- Modify: `app/lib/session/active_session_controller.dart` (`finish()` — filter done sets, compute top set/PR)
- Test: `app/test/data/session_writer_top_set_test.dart`

- [ ] **Step 1: Write the failing test for `topSetIndex`**

Create `app/test/data/session_writer_top_set_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_writer.dart';

SetWrite _s(String id, int n, String w, int reps, {bool warm = false}) => SetWrite(
      id: id, exerciseId: 'e1', setNumber: n, weightKg: w, reps: reps,
      rir: warm ? null : 2, isWarmup: warm);

void main() {
  test('topSetIndex picks the heaviest non-warmup set', () {
    final sets = [_s('a', 1, '60.00', 8), _s('b', 2, '80.00', 5), _s('c', 3, '70.00', 6)];
    expect(topSetIndex(sets), 1); // '80.00' is heaviest
  });
  test('compares weight numerically, not lexically', () {
    final sets = [_s('a', 1, '100.00', 5), _s('b', 2, '90.00', 5)];
    expect(topSetIndex(sets), 0); // 100 > 90 (lexical would pick "90...")
  });
  test('tie on weight breaks by reps DESC then set_number ASC', () {
    final sets = [_s('a', 1, '80.00', 5), _s('b', 2, '80.00', 8), _s('c', 3, '80.00', 8)];
    expect(topSetIndex(sets), 1); // same weight; reps 8>5; b before c
  });
  test('ignores warm-up sets; returns -1 when none qualify', () {
    expect(topSetIndex([_s('a', 1, '99.00', 5, warm: true)]), -1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `topSetIndex` / `SetWrite(isTopSet:...)` undefined.

- [ ] **Step 3: Extend `SetWrite` + add `topSetIndex` + write the columns**

In `app/lib/data/session_writer.dart`:

(a) Add two fields to `SetWrite` (after `isWarmup`), defaulting false, and to its constructor:
```dart
  final bool isWarmup;
  final bool isTopSet;
  final bool isPr;

  const SetWrite({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.isWarmup,
    this.isTopSet = false,
    this.isPr = false,
  });
```

(b) Add the pure helper (top-level, e.g. above `persistSession`):
```dart
/// Index into [sets] of the top set for ONE exercise: the heaviest non-warmup
/// set, tie-break weight DESC, reps DESC, set_number ASC, id ASC — mirroring the
/// server's recomputeTopSet so a client value never disagrees after sync.
/// Returns -1 if there is no non-warmup set. weightKg is TEXT, so compare
/// numerically (parse to double).
int topSetIndex(List<SetWrite> sets) {
  var best = -1;
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];
    if (s.isWarmup) continue;
    if (best == -1) {
      best = i;
      continue;
    }
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
```

(c) Extend the `sets` INSERT in `persistSession` (`session_writer.dart:111-122`) to write the two columns. Update the comment that says it never writes them:
```dart
    await executor.execute(
      'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup, is_top_set, is_pr) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        s.id,
        write.id,
        s.exerciseId,
        s.setNumber,
        s.weightKg,
        s.reps,
        s.isWarmup ? null : s.rir,
        s.isWarmup ? 1 : 0,
        s.isTopSet ? 1 : 0,
        s.isPr ? 1 : 0,
      ],
    );
```
(Confirm `sets` in `app/lib/sync/schema.dart` declares `is_top_set` and `is_pr` — it does, since the server stamps them and they sync down. If a name differs, match it.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!" (112 = 108 + 4).

- [ ] **Step 5: Fix `finish()` — only done sets, and stamp top set/PR per exercise**

In `app/lib/session/active_session_controller.dart`, replace the collection loop (`:453-477`) so it (1) keeps only `done` sets, (2) marks the top working set via `topSetIndex`, and (3) sets `isPr` when that set's weight strictly exceeds the block's all-time best if the controller has one. First check how the block exposes its loaded all-time best top set (the investigation noted `bestTopSet`/`bestKg` is loaded per block around `:305`); use that field — call it `block.bestKg` below, and if the real field name differs, adapt (if there is no such field, set `isPr: false` and let the server recompute on sync):

```dart
    final sets = <SetWrite>[];
    for (final block in d.blocks) {
      var setNum = 1;
      final blockSets = <SetWrite>[];
      for (final s in block.warmupSets.where((s) => s.done)) {
        blockSets.add(SetWrite(
          id: s.id,
          exerciseId: block.exercise.id,
          setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2),
          reps: s.reps,
          rir: null,
          isWarmup: true,
        ));
      }
      for (final s in block.workingSets.where((s) => s.done)) {
        blockSets.add(SetWrite(
          id: s.id,
          exerciseId: block.exercise.id,
          setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2),
          reps: s.reps,
          rir: s.rir,
          isWarmup: false,
        ));
      }
      // Stamp the top set (and PR) for this exercise, client-side.
      final topIdx = topSetIndex(blockSets);
      if (topIdx >= 0) {
        final top = blockSets[topIdx];
        final topWeight = double.tryParse(top.weightKg) ?? 0;
        final isPr = block.bestKg != null && topWeight > block.bestKg!;
        blockSets[topIdx] = SetWrite(
          id: top.id,
          exerciseId: top.exerciseId,
          setNumber: top.setNumber,
          weightKg: top.weightKg,
          reps: top.reps,
          rir: top.rir,
          isWarmup: top.isWarmup,
          isTopSet: true,
          isPr: isPr,
        );
      }
      sets.addAll(blockSets);
    }
```
Leave the rest of `finish()` (the `SessionWrite` construction + `persistSession` call) unchanged. Import for `topSetIndex` is already satisfied (same `session_writer.dart` the controller already imports for `SetWrite`/`persistSession`).

> If `block` has no `bestKg`-style field, use `isPr: false` everywhere and add a one-line code comment that PR is recomputed on sync. Do NOT invent a query here.

- [ ] **Step 6: Verify analyze + tests**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "No issues found!" and "All tests passed!" (112).

- [ ] **Step 7: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/data/session_writer.dart app/lib/session/active_session_controller.dart app/test/data/session_writer_top_set_test.dart
git commit -m "fix(app): finish saves only done sets; stamp is_top_set/is_pr client-side"
```

---

## Task 2: Backfill `is_top_set` for existing local sessions

**Files:**
- Create: `app/lib/data/top_set_backfill.dart`
- Modify: `app/lib/main.dart` (run the backfill once at startup)
- Test: `app/test/data/top_set_backfill_test.dart`

> Task 1 fixes NEW sessions. Existing locally-logged sessions still have `is_top_set` unset → Progress still shows 0 for them. This task computes the top-set ids for groups that lack one and stamps them. Pure decision logic is unit-tested; the runner applies it.

- [ ] **Step 1: Write the failing test**

Create `app/test/data/top_set_backfill_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/top_set_backfill.dart';

Map<String, Object?> _row(String id, String sess, String ex, String w, int reps, int setNo,
        {int warm = 0, int top = 0}) =>
    {'id': id, 'session_id': sess, 'exercise_id': ex, 'weight_kg': w, 'reps': reps,
     'set_number': setNo, 'is_warmup': warm, 'is_top_set': top};

void main() {
  test('returns the heaviest non-warmup set id per group lacking a top set', () {
    final rows = [
      _row('a', 's1', 'e1', '60.00', 8, 1),
      _row('b', 's1', 'e1', '80.00', 5, 2),
      _row('c', 's1', 'e1', '70.00', 6, 3),
    ];
    expect(topSetIdsToStamp(rows), {'b'});
  });
  test('skips groups that already have a top set', () {
    final rows = [
      _row('a', 's1', 'e1', '60.00', 8, 1, top: 1),
      _row('b', 's1', 'e1', '80.00', 5, 2),
    ];
    expect(topSetIdsToStamp(rows), <String>{});
  });
  test('ignores warm-up-only groups', () {
    expect(topSetIdsToStamp([_row('a', 's1', 'e1', '99.00', 5, 1, warm: 1)]), <String>{});
  });
  test('handles multiple groups independently', () {
    final rows = [
      _row('a', 's1', 'e1', '50.00', 5, 1),
      _row('b', 's2', 'e1', '60.00', 5, 1),
    ];
    expect(topSetIdsToStamp(rows), {'a', 'b'});
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `top_set_backfill.dart` not found.

- [ ] **Step 3: Implement the pure decision + the runner**

Create `app/lib/data/top_set_backfill.dart`:
```dart
import 'package:powersync/powersync.dart';

/// Given raw `sets` rows (each a map with id, session_id, exercise_id,
/// weight_kg, reps, set_number, is_warmup, is_top_set), return the ids of the
/// sets that SHOULD be stamped is_top_set=1: for each (session, exercise) group
/// that currently has NO non-warmup set flagged, the heaviest non-warmup set
/// (tie-break weight DESC, reps DESC, set_number ASC, id ASC). Mirrors the
/// server + [session_writer.topSetIndex].
Set<String> topSetIdsToStamp(List<Map<String, Object?>> rows) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final key = '${r['session_id']}|${r['exercise_id']}';
    (groups[key] ??= []).add(r);
  }
  final out = <String>{};
  for (final g in groups.values) {
    final working = g.where((r) => (r['is_warmup'] as int? ?? 0) == 0).toList();
    if (working.isEmpty) continue;
    if (working.any((r) => (r['is_top_set'] as int? ?? 0) == 1)) continue; // already has one
    Map<String, Object?>? best;
    for (final r in working) {
      if (best == null) { best = r; continue; }
      final rw = double.tryParse(r['weight_kg']?.toString() ?? '') ?? 0;
      final bw = double.tryParse(best['weight_kg']?.toString() ?? '') ?? 0;
      final rr = r['reps'] as int? ?? 0, br = best['reps'] as int? ?? 0;
      final rn = r['set_number'] as int? ?? 0, bn = best['set_number'] as int? ?? 0;
      final rid = r['id'] as String, bid = best['id'] as String;
      if (rw > bw ||
          (rw == bw && rr > br) ||
          (rw == bw && rr == br && rn < bn) ||
          (rw == bw && rr == br && rn == bn && rid.compareTo(bid) < 0)) {
        best = r;
      }
    }
    out.add(best!['id'] as String);
  }
  return out;
}

/// One-time, idempotent backfill: stamps is_top_set on existing local sessions
/// whose (session,exercise) groups never got a server-computed top set. Safe to
/// run on every launch (no-op once all groups have a top set).
Future<void> backfillTopSets(PowerSyncDatabase db) async {
  final rows = await db.getAll(
    'SELECT id, session_id, exercise_id, weight_kg, reps, set_number, is_warmup, is_top_set FROM sets');
  final ids = topSetIdsToStamp(rows.map((r) => Map<String, Object?>.from(r)).toList());
  if (ids.isEmpty) return;
  await db.writeTransaction((tx) async {
    for (final id in ids) {
      await tx.execute('UPDATE sets SET is_top_set = 1 WHERE id = ?', [id]);
    }
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!" (116 = 112 + 4).

- [ ] **Step 5: Run the backfill once at startup**

In `app/lib/main.dart`, after `await openDatabase();` and the identity init, before `runApp`, add:
```dart
  await backfillTopSets(db);
```
and import it: `import 'data/top_set_backfill.dart';`. (`db` is the global from `sync/db.dart`, already imported.)

- [ ] **Step 6: Verify analyze + tests**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "No issues found!" and "All tests passed!" (116).

- [ ] **Step 7: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/data/top_set_backfill.dart app/lib/main.dart app/test/data/top_set_backfill_test.dart
git commit -m "fix(app): backfill is_top_set for existing local sessions so Progress works offline"
```

---

## Task 3: UI fixes — status-bar inset, FAB glow, even cards

**Files:**
- Modify: `app/lib/ui/today_screen.dart`, `app/lib/ui/history_screen.dart`, `app/lib/ui/progress_screen.dart` (status bar)
- Modify: `app/lib/shell/w_tab_bar.dart` (FAB glow)
- Modify: `app/lib/ui/today_screen.dart` (even "This week" cards)

> Pure UI; no unit tests (validated by analyze + build + on-device). Make all changes, then verify once.

- [ ] **Step 1: Add the status-bar top inset to the three scrolling screens**

These three `ListView`s hardcode `top: 8` and ignore the Android status bar (Plan screen already does it right with `MediaQuery.paddingOf(context).top`):
- `today_screen.dart:177` — change the padding's `top: 8` to `top: 8 + MediaQuery.paddingOf(context).top`.
- `history_screen.dart:98` — change `EdgeInsets.fromLTRB(16, 8, 16, 96)` to `EdgeInsets.fromLTRB(16, 8 + MediaQuery.paddingOf(context).top, 16, 96)`.
- `progress_screen.dart:194` — same change as history.

(Confirm each is the outermost scroll padding for that screen's header. Do NOT also wrap the shell in SafeArea — that would double-pad against Plan screen.)

- [ ] **Step 2: Make the center FAB glow bottom-only**

In `app/lib/shell/w_tab_bar.dart` (the `_FabButton` `BoxDecoration.boxShadow`, ~`:174-184`), replace the symmetric shadow:
```dart
    boxShadow: [
      BoxShadow(
        color: t.accent.withValues(alpha: 0.45),
        blurRadius: 16,
        spreadRadius: -2,
        offset: const Offset(0, 8),
      ),
    ],
```

- [ ] **Step 3: Equalize the "This week" cards**

In `app/lib/ui/today_screen.dart` (`_buildStatTiles`, ~`:285`), wrap the `Row` in `IntrinsicHeight` and stretch children:
```dart
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, // was .start
        children: [
          // ... the three Expanded(StatTile/StreamBuilder) children unchanged ...
        ],
      ),
    );
```

- [ ] **Step 4: Verify analyze + build + tests**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "No issues found!" and "All tests passed!" (116 — no new tests).

- [ ] **Step 5: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/ui/today_screen.dart app/lib/ui/history_screen.dart app/lib/ui/progress_screen.dart app/lib/shell/w_tab_bar.dart
git commit -m "fix(app): status-bar inset on scroll screens, bottom-only FAB glow, even This-week cards"
```

---

## Task 4: Exercise sheet — hide Bodyweight in day editor + drag-to-close

**Files:**
- Modify: `app/lib/ui/exercise_sheet.dart` (add `showBodyweight` flag; convert to draggable)
- Modify: `app/lib/ui/day_editor.dart` (pass `showBodyweight: false`)

- [ ] **Step 1: Add a `showBodyweight` flag to suppress the Tracking row**

The shared `exercise_sheet.dart` pins a hardcoded "Bodyweight" Tracking row (sentinel `kBodyweightSentinel`), which is meaningful on Progress but a dead entry in the day editor. In `app/lib/ui/exercise_sheet.dart`:
- Add `bool showBodyweight = true` param to `showExerciseSheet(...)` (`:22-33`) and thread it into `_ExerciseSheet`.
- Gate the pinned Bodyweight block (`:128`) on `widget.showBodyweight && _showBodyweight`, and include `widget.showBodyweight` in the `hasResults` calc (`:90`) so an empty search with bodyweight hidden behaves correctly.

In `app/lib/ui/day_editor.dart:192` (the `showExerciseSheet(...)` call), pass `showBodyweight: false`. Leave `progress_screen.dart:56` defaulting to true.

- [ ] **Step 2: Convert the sheet to drag-to-close**

`exercise_sheet.dart` opens via `showModalBottomSheet(isScrollControlled: true)` with a fixed `Container` (no drag at all). Convert the body (`:95`) to a `DraggableScrollableSheet` and thread its controller into the body `ListView` (`:121`), mirroring the working pattern in `exercise_picker_sheet.dart:72-77`:
```dart
    return DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          // ... existing decoration ...
          child: Column(
            children: [
              const _SheetHeader(...), // unchanged, stays fixed at top
              Flexible(
                child: ListView(
                  controller: scrollController, // <-- thread it in
                  // ... existing children ...
                ),
              ),
            ],
          ),
        );
      },
    );
```
With the inner `ListView` driven by the sheet's `scrollController`, a downward drag while the list is at offset 0 propagates to the sheet and dismisses it (native behavior) — closing from anywhere on the body, not only the Done button. Keep the existing "Done" button.

- [ ] **Step 3: Verify analyze + tests**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "No issues found!" and "All tests passed!" (116).

- [ ] **Step 4: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/ui/exercise_sheet.dart app/lib/ui/day_editor.dart
git commit -m "fix(app): hide Bodyweight row in day-editor picker; make exercise sheet drag-to-close"
```

---

## Task 5: Edit history — edit sets + delete (sets & sessions)

**Files:**
- Modify: `app/lib/data/session_repository.dart` (add `updateSet`, `deleteSet`, `deleteSession`)
- Modify: `app/lib/ui/history_screen.dart` (edit affordances on the expanded session)
- Test: `app/test/data/session_repository_edit_test.dart`

> Server PATCH/DELETE + PR-recompute already exist; this is purely client-side. NEVER write `is_top_set`/`is_pr` from the edit path — the server recomputes on sync, and locally Task 2's backfill + Task 1's stamping keep them current for new/edited data. (After an edit changes weights, the local top-set flag may be stale until re-derived; acceptable — History uses its own fallback, and a future sync recomputes. Out of scope to re-derive on edit here.)

- [ ] **Step 1: Write the failing test for the repo mutations**

Create `app/test/data/session_repository_edit_test.dart`. The repo methods run SQL via the `db`; to test without a real DB, the methods must accept a write executor. Add testable mutation builders (pure SQL+args) alongside the repo methods and test those:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_repository.dart';

void main() {
  test('updateSetOp builds a PATCH-style UPDATE with weight/reps/rir', () {
    final op = updateSetOp('set-1', weightKg: '82.50', reps: 5, rir: 1);
    expect(op.sql, contains('UPDATE sets SET'));
    expect(op.sql, contains('weight_kg'));
    expect(op.sql, contains('WHERE id = ?'));
    expect(op.args, ['82.50', 5, 1, 'set-1']);
  });
  test('deleteSetOp targets the id', () {
    final op = deleteSetOp('set-9');
    expect(op.sql, 'DELETE FROM sets WHERE id = ?');
    expect(op.args, ['set-9']);
  });
  test('deleteSessionOp targets the id', () {
    final op = deleteSessionOp('sess-3');
    expect(op.sql, 'DELETE FROM sessions WHERE id = ?');
    expect(op.args, ['sess-3']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `updateSetOp`/`deleteSetOp`/`deleteSessionOp` undefined.

- [ ] **Step 3: Implement the ops + repo methods**

In `app/lib/data/session_repository.dart`, add the pure builders (top-level) and the repo methods that run them in a `writeTransaction`:
```dart
({String sql, List<Object?> args}) updateSetOp(String id,
    {required String weightKg, required int reps, required int? rir}) {
  return (
    sql: 'UPDATE sets SET weight_kg = ?, reps = ?, rir = ? WHERE id = ?',
    args: [weightKg, reps, rir, id],
  );
}

({String sql, List<Object?> args}) deleteSetOp(String id) =>
    (sql: 'DELETE FROM sets WHERE id = ?', args: [id]);

({String sql, List<Object?> args}) deleteSessionOp(String id) =>
    (sql: 'DELETE FROM sessions WHERE id = ?', args: [id]);
```
And add methods on `SessionRepository` (it holds `db`):
```dart
  Future<void> updateSet(String id, {required String weightKg, required int reps, required int? rir}) async {
    final op = updateSetOp(id, weightKg: weightKg, reps: reps, rir: rir);
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }

  Future<void> deleteSet(String id) async {
    final op = deleteSetOp(id);
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }

  Future<void> deleteSession(String id) async {
    final op = deleteSessionOp(id);
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }
```
(Deleting a session: PowerSync issues a DELETE crud op; the server cascades to sets. Locally, the `sets` rows for that session may linger until sync — acceptable; History reads sets via `setsForSession(sessionId)` joined to the session, so an orphaned-but-unsynced set set is an edge case. If History shows orphan sets locally after a session delete, also delete the session's sets in the same transaction: add `tx.execute('DELETE FROM sets WHERE session_id = ?', [id])` before the session delete.)

> Decision: include the local `DELETE FROM sets WHERE session_id = ?` in `deleteSession` (belt-and-suspenders so the local view is immediately clean):
```dart
  Future<void> deleteSession(String id) async {
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM sets WHERE session_id = ?', [id]);
      await tx.execute('DELETE FROM sessions WHERE id = ?', [id]);
    });
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!" (119 = 116 + 3).

- [ ] **Step 5: Add the edit UI to the expanded session in History**

In `app/lib/ui/history_screen.dart`, the expanded `SessionCard` shows read-only `_BlockRow`s. Add:
- A **delete-session** action on the expanded card (an icon button or a long-press → confirm dialog → `SessionRepository(db).deleteSession(session.id)`). Match the existing confirm-dialog style used elsewhere (e.g. the sign-out/server-switch dialogs in `profile_screen.dart`).
- Make each set within the expanded view editable: tapping an exercise's row opens a small editor (reuse `WStepper`/`RirPicker` from `widgets/`) listing that exercise's sets (`setsForSession(session.id)` already loads them); each set row allows editing weight/reps/rir (→ `updateSet(...)`) and deleting the set (→ `deleteSet(...)` → confirm). On save/delete, the History stream (`watchSessionStats`/the expand's `setsForSession` future) refreshes; trigger a rebuild of the expanded section.

Keep it consistent with the existing History visual language (the `_BlockRow`, `WCard`, `Tag` widgets). This is the largest UI piece — follow existing patterns; do not introduce a new design system.

- [ ] **Step 6: Verify analyze + tests + build**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'`, `make -C app test 2>&1 | grep -E 'All tests passed|failed'`, `make -C app build 2>&1 | tail -2`
Expected: 0 issues; all tests pass (119); Linux bundle links.

- [ ] **Step 7: Commit**

```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/data/session_repository.dart app/lib/ui/history_screen.dart app/test/data/session_repository_edit_test.dart
git commit -m "feat(app): edit/delete sets and delete sessions from History"
```

---

## Task 6: Verify (INLINE — controller runs this)

- [ ] **Step 1: Full gates**
```bash
make -C app analyze 2>&1 | grep -iE 'no issues|error'
make -C app test 2>&1 | grep -E 'All tests passed|failed'
make -C app build 2>&1 | tail -3
```
Expected: 0 issues; ~119 tests pass; Linux bundle links.

- [ ] **Step 2: Headless smoke (fresh profile)**
```bash
cd app/build/linux/x64/release/bundle
rm -rf /tmp/wt_uifix && XDG_DATA_HOME=/tmp/wt_uifix XDG_CONFIG_HOME=/tmp/wt_uifix timeout 22 ./workout_tracker > /tmp/wt_uifix.log 2>&1; echo "EXIT=$? (124=ok)"
grep -iE 'exception|error|overflow|assert|providernotfound' /tmp/wt_uifix.log | head
```
Expected: EXIT=124, no crash lines. (The backfill runs at startup; confirm it doesn't throw on an empty DB.)

- [ ] **Step 3: Build + install the APK on the connected phone for visual verification** (the UI bugs #1/#2/#3/#5/#6 can only be eyeballed on Android):
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk; export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/platform-tools:$PATH"
make -C app build-apk 2>&1 | tail -2
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk 2>&1 | tail -1
```
Then report; the user verifies the visuals on-device.

---

## Verification summary

1. analyze 0 issues; ~119 tests pass; Linux build + APK build link.
2. Logic: finishing saves only done sets (#7); Progress shows correct top set/est-1RM for new AND existing local sessions (#4, Tasks 1+2).
3. UI: no status-bar overlap (#1), bottom-only FAB glow (#2), even This-week cards (#3), no Bodyweight row in day-editor picker (#5), exercise sheet drags to close (#6) — verified on-device.
4. History: edit set weight/reps/rir, delete sets, delete sessions (#8).
