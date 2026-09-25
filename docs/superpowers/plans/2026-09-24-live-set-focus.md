# Live Set Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the live workout screen so that one set is "live" at a time. A pinned lime bar logs it in one tap, RIR is corrected afterwards on a short-lived strip, rest moves into the header, and per-block and per-workout actions move into `⋯` sheets. Every target is at least 48dp.

**Architecture:**
- **Focus lives in the controller.** `ActiveSessionController` gains in-memory focus state: the focused set id and the RIR-prompt set id with its expiry. Pure getters and mutators derive the live set, log it, and advance. The widgets stay dumb.
- **New widgets:** `SetLine` (compact row), `LiveSetCard` (big steppers), `LogSetBar` (the pinned action), `SessionHeader` (with a rest row) and `showWActionSheet` (the sheets).
- **The screen wires them up.** `ActiveSessionScreen` combines the new widgets and deletes the floating `RestTimerCard` and the in-list Finish button.
- **No schema change.** Nothing about the draft persistence changes.

**Tech Stack:** Flutter (via fvm, always `make -C app …`), provider, flutter_test, gen-l10n ARB files (en/it/de/es).

**Spec:** `docs/superpowers/specs/2026-09-24-live-set-focus-design.md`

## Global Constraints

- Every command runs from the repo root with an explicit path, `make -C app …`. Never `cd`, and never call `flutter` directly.
- `make -C app analyze` must report "No issues found". Deprecation warnings count as failures.
- Every new tappable on the live workout screen is at least 48dp on both axes, and every icon-only tappable has a `Semantics` label.
- The log bar is 56dp tall and each action-sheet row is at least 56dp tall.
- The RIR prompt lasts exactly 4 seconds and restarts on a chip tap.
- The large stepper has 56×56dp buttons and a 30pt Space Grotesk tabular value.
- Before acting, the log bar calls `FocusManager.instance.primaryFocus?.unfocus()` and then `FocusManager.instance.applyFocusChangesIfNeeded()`.
- Every new user-visible string goes into all four ARB files (`app/lib/l10n/app_{en,it,de,es}.arb`); `app/test/l10n/arb_parity_test.dart` enforces it.
- Confirm dialogs use `showWConfirm`/`showWDialog` only, never `AlertDialog`.
- Every duration goes through `Motion.of(context, …)`.
- `late final AnimationController` fields are constructed in `initState`, never with `..forward()` in the initializer.
- `Expanded` must be a direct child of its `Row`/`Column`.
- Don't create `db.watch()` streams in `build()`. This plan adds none.
- `WStepper` weight steppers in the session hold **kg** and keep `parseDisplay: (v) => UnitService.toKg(v, unit.unit)`.
- Commits follow Conventional Commits: subject line only, no body, no plan numbers in code or comments.
- The draft JSON schema (`SetState`/`BlockState`/`SessionDraft.toJson`) does not change.

## Review Focus

1. **Typing a weight, then tapping the log bar without pressing Done.** The typed value must be what gets logged. This is covered in Task 7 (`typed weight commits before the bar logs`).
2. **Correcting a logged set.** Tap a done set, change its weight, tap "Update set 1": the set stays done with the new weight and focus moves on. This is covered in Task 1 (`logging a focused done set keeps it done and clears focus`) and Task 7 (the `Update` label).
3. **Removing the live set, or undoing a removal after the block was removed.** Focus must fall back without a crash, and undo must be a no-op when the block is gone. This is covered in Task 1 (`removing the focused set clears focus`, `restoreSet on a removed block is a no-op`).
4. **Narrow phone with large text in Italian or German.** Neither the live card, the compact line, the header rest row nor the bar may overflow at 320dp and 1.3× scale. This is covered in Tasks 4, 5, 6 and 8 (`no overflow at 320dp / 1.3× (it)`).
5. **Logging a set in one block while another block still has pending sets.** Only a fully-done block collapses. This is covered in Task 1 (`a block with pending sets stays expanded when focus leaves it`).

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `app/lib/session/active_session_controller.dart` | modify | the `LiveSet` typedef, `liveTopOf`, `expandOnlyFirst`, focus / log / RIR-prompt / undo mutators |
| `app/lib/l10n/app_{en,it,de,es}.arb` | modify | new strings; delete 3 dead keys |
| `app/lib/widgets/stepper.dart` | modify | `large` variant |
| `app/lib/widgets/rir_picker.dart` | modify | `height` parameter |
| `app/lib/theme/icons.dart` | modify | `WIcons.more` |
| `app/lib/widgets/w_action_sheet.dart` | create | `showWActionSheet` + `WSheetAction` |
| `app/lib/session/set_line.dart` | create | compact set row + RIR strip |
| `app/lib/session/set_row.dart` | delete | replaced by `set_line.dart` |
| `app/lib/session/live_set_card.dart` | create | focused set card |
| `app/lib/session/log_set_bar.dart` | create | pinned primary action + label matrix |
| `app/lib/session/session_header.dart` | create | title row, ⋯, progress/rest bar, rest row, `restNextLabel` |
| `app/lib/session/rest_timer.dart` | delete | replaced by the header rest row |
| `app/lib/session/exercise_block.dart` | modify | renders lines/card, header ⋯, footer removed |
| `app/lib/session/active_session_screen.dart` | modify | wiring, sheets, undo snackbar, scroll-to-live |
| `app/test/session/controller_live_set_test.dart` | create | |
| `app/test/widgets/stepper_large_test.dart` | create | |
| `app/test/widgets/w_action_sheet_test.dart` | create | |
| `app/test/session/set_line_test.dart` | create | |
| `app/test/session/set_row_overflow_test.dart` | delete | |
| `app/test/session/live_set_card_test.dart` | create | |
| `app/test/session/log_set_bar_test.dart` | create | |
| `app/test/session/session_header_test.dart` | create | |
| `app/test/session/exercise_block_edit_test.dart` | rewrite | |
| `app/test/session/exercise_block_accordion_test.dart` | modify | |
| `app/AGENTS.md`, `docs/design_handoff_workout_tracker/README.md` | modify | docs |

---

### Task 1: Live-set model in the controller

**Files:**
- Modify: `app/lib/session/active_session_controller.dart`
- Test: `app/test/session/controller_live_set_test.dart`

**Interfaces:**
- Produces:
  - `typedef LiveSet = ({BlockState block, SetState set});`
  - `({double topKg, bool isPr}) liveTopOf(BlockState block)`
  - `void expandOnlyFirst(List<BlockState> blocks)`
  - `ActiveSessionController` members:
    - `LiveSet? get liveSet`
    - `void focusSet(SetState set)`
    - `({BlockState block, SetState set, bool newlyDone})? logLiveSet({DateTime? now})`
    - `void markNotDone(SetState set)`
    - `String? get rirPromptSetId`
    - `void setRirFromPrompt(SetState set, int rir, {DateTime? now})`
    - `void expireRirPrompt(DateTime now)`
    - `static const rirPromptWindow = Duration(seconds: 4)`
  - `removeSet(BlockState, SetState)` now **returns `int`** (the index in its own list, or -1).
  - `void restoreSet(BlockState block, SetState set, int index)`

- [ ] **Step 1: Write the failing tests**

Create `app/test/session/controller_live_set_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';

Exercise _ex(String id) => Exercise(
      id: id, name: id, slug: id, muscleGroup: 'chest',
      compound: true, plateStepKg: 2.5, isTemplate: false,
    );

SetState _s(String id, {bool warmup = false, bool done = false, double w = 100, int reps = 5}) =>
    SetState(id: id, weightKg: w, reps: reps, rir: warmup ? null : 1, isWarmup: warmup, done: done);

BlockState _b(String id, {List<SetState> warm = const [], List<SetState> work = const [], bool expanded = true, double? bestKg}) {
  final e = _ex(id);
  return BlockState(
    exercise: e,
    resolved: ResolvedSlot(exercise: e, workSets: work.length, warmupSets: warm.length,
        repLow: 5, repHigh: 8, rirLow: 1, rirHigh: 2),
    warmupSets: [...warm],
    workingSets: [...work],
    expanded: expanded,
    bestKg: bestKg,
  );
}

ActiveSessionController _c(List<BlockState> blocks) => ActiveSessionController()
  ..seedForTest(SessionDraft(
    templateId: null, name: 'W', focus: '',
    startedAt: DateTime(2026, 9, 24, 10), blocks: blocks,
  ));

final _t0 = DateTime(2026, 9, 24, 10, 30);

void main() {
  group('liveSet', () {
    test('is the first not-done set in on-screen order, warm-ups first', () {
      final a = _b('a', warm: [_s('w1', warmup: true, done: true), _s('w2', warmup: true)], work: [_s('a1')]);
      final c = _c([a]);
      expect(c.liveSet!.set.id, 'w2');
      expect(identical(c.liveSet!.block, a), isTrue);
    });

    test('skips fully done blocks', () {
      final c = _c([
        _b('a', work: [_s('a1', done: true)]),
        _b('b', work: [_s('b1'), _s('b2')]),
      ]);
      expect(c.liveSet!.set.id, 'b1');
    });

    test('is null when every set is done or there are no blocks', () {
      expect(_c([_b('a', work: [_s('a1', done: true)])]).liveSet, isNull);
      expect(_c([]).liveSet, isNull);
    });

    test('a focused set is live until it is logged, then focus falls back', () {
      final a = _b('a', work: [_s('a1'), _s('a2'), _s('a3')]);
      final c = _c([a]);
      c.focusSet(a.workingSets[2]);
      expect(c.liveSet!.set.id, 'a3');
      c.logLiveSet(now: _t0);
      expect(a.workingSets[2].done, isTrue);
      expect(c.liveSet!.set.id, 'a1');
    });
  });

  group('logLiveSet', () {
    test('marks the live set done and reports it as newly done', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      var notifies = 0;
      c.addListener(() => notifies++);
      final r = c.logLiveSet(now: _t0)!;
      expect(r.set.id, 'a1');
      expect(r.newlyDone, isTrue);
      expect(a.workingSets[0].done, isTrue);
      expect(c.liveSet!.set.id, 'a2');
      expect(notifies, 1);
    });

    test('returns null when there is no live set', () {
      expect(_c([_b('a', work: [_s('a1', done: true)])]).logLiveSet(now: _t0), isNull);
    });

    test('logging a focused done set keeps it done and clears focus', () {
      final a = _b('a', work: [_s('a1', done: true), _s('a2')]);
      final c = _c([a]);
      c.focusSet(a.workingSets[0]);
      a.workingSets[0].weightKg = 102.5; // corrected in the live card
      final r = c.logLiveSet(now: _t0)!;
      expect(r.newlyDone, isFalse);
      expect(a.workingSets[0].done, isTrue);
      expect(a.workingSets[0].weightKg, 102.5);
      expect(c.liveSet!.set.id, 'a2');
      expect(c.rirPromptSetId, isNull);
    });

    test('moving into the next block collapses the finished block and expands the next', () {
      final a = _b('a', work: [_s('a1')]);
      final b = _b('b', work: [_s('b1')], expanded: false);
      final c = _c([a, b]);
      c.logLiveSet(now: _t0);
      expect(a.expanded, isFalse);
      expect(b.expanded, isTrue);
    });

    test('staying inside the same block keeps its expansion', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      c.logLiveSet(now: _t0);
      expect(a.expanded, isTrue);
    });

    test('a block with pending sets stays expanded when focus leaves it', () {
      final a = _b('a', work: [_s('a1')], expanded: false);
      final b = _b('b', work: [_s('b1'), _s('b2')]);
      final c = _c([a, b]);
      c.focusSet(b.workingSets[0]);
      c.logLiveSet(now: _t0); // next live is a1, in another block
      expect(b.expanded, isTrue);
      expect(a.expanded, isTrue);
    });
  });

  group('RIR prompt', () {
    test('logging a working set opens the prompt for exactly the window', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      c.logLiveSet(now: _t0);
      expect(c.rirPromptSetId, 'a1');
      c.expireRirPrompt(_t0.add(const Duration(seconds: 3)));
      expect(c.rirPromptSetId, 'a1');
      c.expireRirPrompt(_t0.add(ActiveSessionController.rirPromptWindow));
      expect(c.rirPromptSetId, isNull);
    });

    test('logging a warm-up opens no prompt and closes an open one', () {
      final a = _b('a', work: [_s('a1')]);
      final b = _b('b', warm: [_s('bw', warmup: true)], work: [_s('b1')]);
      final c = _c([a, b]);
      c.logLiveSet(now: _t0);
      expect(c.rirPromptSetId, 'a1');
      c.logLiveSet(now: _t0); // logs the warm-up bw
      expect(c.rirPromptSetId, isNull);
    });

    test('a chip tap sets RIR and restarts the window', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      c.logLiveSet(now: _t0);
      final later = _t0.add(const Duration(seconds: 3));
      c.setRirFromPrompt(a.workingSets[0], 3, now: later);
      expect(a.workingSets[0].rir, 3);
      c.expireRirPrompt(_t0.add(const Duration(seconds: 5)));
      expect(c.rirPromptSetId, 'a1');
      c.expireRirPrompt(later.add(ActiveSessionController.rirPromptWindow));
      expect(c.rirPromptSetId, isNull);
    });

    test('expiring with nothing open does not notify', () {
      final c = _c([_b('a', work: [_s('a1')])]);
      var notifies = 0;
      c.addListener(() => notifies++);
      c.expireRirPrompt(_t0);
      expect(notifies, 0);
    });
  });

  group('markNotDone', () {
    test('un-logs the set, makes it live and closes its prompt', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      c.logLiveSet(now: _t0);
      c.markNotDone(a.workingSets[0]);
      expect(a.workingSets[0].done, isFalse);
      expect(c.liveSet!.set.id, 'a1');
      expect(c.rirPromptSetId, isNull);
    });
  });

  group('remove and restore', () {
    test('removeSet returns the index and restoreSet puts it back there', () {
      final a = _b('a', work: [_s('a1'), _s('a2'), _s('a3')]);
      final c = _c([a]);
      final s = a.workingSets[1];
      final idx = c.removeSet(a, s);
      expect(idx, 1);
      expect(a.workingSets.map((x) => x.id), ['a1', 'a3']);
      c.restoreSet(a, s, idx);
      expect(a.workingSets.map((x) => x.id), ['a1', 'a2', 'a3']);
    });

    test('restores a warm-up into the warm-up list', () {
      final a = _b('a', warm: [_s('w1', warmup: true)], work: [_s('a1')]);
      final c = _c([a]);
      final w = a.warmupSets.single;
      final idx = c.removeSet(a, w);
      c.restoreSet(a, w, idx);
      expect(a.warmupSets.single.id, 'w1');
      expect(a.workingSets.single.id, 'a1');
    });

    test('removing the focused set clears focus', () {
      final a = _b('a', work: [_s('a1'), _s('a2')]);
      final c = _c([a]);
      c.focusSet(a.workingSets[1]);
      c.removeSet(a, a.workingSets[1]);
      expect(c.liveSet!.set.id, 'a1');
    });

    test('restoreSet on a removed block is a no-op', () {
      final a = _b('a', work: [_s('a1')]);
      final c = _c([a]);
      final s = a.workingSets.single;
      final idx = c.removeSet(a, s);
      c.removeBlock(a);
      c.restoreSet(a, s, idx);
      expect(c.draft.blocks, isEmpty);
      expect(a.workingSets, isEmpty);
    });

    test('restoreSet clamps an index past the end', () {
      final a = _b('a', work: [_s('a1')]);
      final c = _c([a]);
      c.restoreSet(a, _s('x'), 99);
      expect(a.workingSets.map((x) => x.id), ['a1', 'x']);
    });
  });

  group('helpers', () {
    test('liveTopOf reports the heaviest done working set and PR status', () {
      final a = _b('a', warm: [_s('w', warmup: true, done: true, w: 200)],
          work: [_s('a1', done: true, w: 100), _s('a2', done: true, w: 105), _s('a3', w: 120)],
          bestKg: 102.5);
      expect(liveTopOf(a), (topKg: 105.0, isPr: true));
      a.bestKg = 110;
      expect(liveTopOf(a).isPr, isFalse);
      expect(liveTopOf(_b('b', work: [_s('b1')])), (topKg: 0.0, isPr: false));
      expect(liveTopOf(_b('c', work: [_s('c1', done: true)])).isPr, isTrue); // no history
    });

    test('expandOnlyFirst expands the first block and collapses the rest', () {
      final blocks = [_b('a', expanded: false), _b('b'), _b('c')];
      expandOnlyFirst(blocks);
      expect(blocks.map((b) => b.expanded), [true, false, false]);
      expandOnlyFirst([]); // no throw
    });
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `make -C app test TEST=test/session/controller_live_set_test.dart`
Expected: FAIL at compile time. `liveSet`, `logLiveSet`, `liveTopOf` and the rest are not defined.

- [ ] **Step 3: Implement**

In `app/lib/session/active_session_controller.dart`:

(a) Under `// ── Pure helpers`, after `buildBlock`, add:

```dart
/// A set together with the block it belongs to.
typedef LiveSet = ({BlockState block, SetState set});

/// The heaviest done working set in [block] and whether it beats the
/// block's all-time best (no history counts as a PR). The same rule the
/// block header and the finish-time PR flag use.
({double topKg, bool isPr}) liveTopOf(BlockState block) {
  final top = block.workingSets
      .where((s) => s.done)
      .fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
  final best = block.bestKg;
  return (topKg: top, isPr: top > 0 && (best == null || top > best));
}

/// A fresh workout opens with only its first exercise expanded; the live set
/// expands the others as the workout reaches them.
void expandOnlyFirst(List<BlockState> blocks) {
  for (var i = 0; i < blocks.length; i++) {
    blocks[i].expanded = i == 0;
  }
}
```

(b) In `buildFromTemplate`, just before `_draft = SessionDraft(`, add `expandOnlyFirst(blocks);`.

(c) After the `// ── Rest timer` section's `setRestRaw`, add:

```dart
  // ── Live set (in-memory focus; never persisted — recomputed on resume) ──

  String? _focusedSetId;
  String? _rirPromptSetId;
  DateTime? _rirPromptUntil;

  /// How long the RIR correction strip stays open after a set is logged.
  static const rirPromptWindow = Duration(seconds: 4);

  /// The set the log bar acts on: the tapped set while it still exists,
  /// otherwise the first not-done set in on-screen order (blocks top to
  /// bottom, warm-ups before working sets). Null when every set is done.
  LiveSet? get liveSet {
    final d = _draft;
    if (d == null) return null;
    final focused = _focusedSetId;
    if (focused != null) {
      for (final b in d.blocks) {
        for (final s in b.allSets) {
          if (s.id == focused) return (block: b, set: s);
        }
      }
    }
    for (final b in d.blocks) {
      for (final s in b.allSets) {
        if (!s.done) return (block: b, set: s);
      }
    }
    return null;
  }

  /// The logged set whose RIR strip is open, or null.
  String? get rirPromptSetId => _rirPromptSetId;

  /// Makes [set] the live set (a tap on its row).
  void focusSet(SetState set) {
    if (_focusedSetId == set.id) return;
    _focusedSetId = set.id;
    notifyListeners();
  }

  /// Logs the live set, or — when it is already logged — confirms the
  /// correction made in the live card. Focus then falls back to the first
  /// not-done set; when that is in another block, the block just finished
  /// collapses (only if every set in it is done) and the next one expands.
  /// A newly logged working set opens the RIR strip; anything else closes it.
  /// Returns null when there is no live set.
  ({BlockState block, SetState set, bool newlyDone})? logLiveSet(
      {DateTime? now}) {
    final live = liveSet;
    if (live == null) return null;
    final newlyDone = !live.set.done;
    live.set.done = true;
    _focusedSetId = null;
    if (newlyDone && !live.set.isWarmup) {
      _rirPromptSetId = live.set.id;
      _rirPromptUntil = (now ?? DateTime.now()).add(rirPromptWindow);
    } else {
      _rirPromptSetId = null;
      _rirPromptUntil = null;
    }
    final next = liveSet;
    if (next != null && !identical(next.block, live.block)) {
      if (live.block.allSets.every((s) => s.done)) live.block.expanded = false;
      next.block.expanded = true;
    }
    notifyListeners();
    return (block: live.block, set: live.set, newlyDone: newlyDone);
  }

  /// Un-logs [set] and makes it the live set.
  void markNotDone(SetState set) {
    set.done = false;
    _focusedSetId = set.id;
    if (_rirPromptSetId == set.id) {
      _rirPromptSetId = null;
      _rirPromptUntil = null;
    }
    notifyListeners();
  }

  /// A tap on the RIR strip: stores [rir] and restarts the strip's window.
  void setRirFromPrompt(SetState set, int rir, {DateTime? now}) {
    set.rir = rir;
    _rirPromptSetId = set.id;
    _rirPromptUntil = (now ?? DateTime.now()).add(rirPromptWindow);
    notifyListeners();
  }

  /// Closes the RIR strip once its window has passed. Called by the
  /// screen's one-second ticker; notifies only when it actually closes.
  void expireRirPrompt(DateTime now) {
    final until = _rirPromptUntil;
    if (_rirPromptSetId == null || until == null || now.isBefore(until)) {
      return;
    }
    _rirPromptSetId = null;
    _rirPromptUntil = null;
    notifyListeners();
  }
```

(d) Replace `removeSet` with the following, and add `restoreSet` after it:

```dart
  /// Removes [set] (warm-up or working) from [block] and returns its index in
  /// its own list (-1 if it was not there), for [restoreSet].
  int removeSet(BlockState block, SetState set) {
    final list = set.isWarmup ? block.warmupSets : block.workingSets;
    final index = list.indexOf(set);
    list.remove(set);
    if (_focusedSetId == set.id) _focusedSetId = null;
    if (_rirPromptSetId == set.id) {
      _rirPromptSetId = null;
      _rirPromptUntil = null;
    }
    notifyListeners();
    return index;
  }

  /// Undo for [removeSet]: puts [set] back at [index] (clamped) in its own
  /// list. A no-op when [block] has since left the workout.
  void restoreSet(BlockState block, SetState set, int index) {
    if (!draft.blocks.contains(block)) return;
    final list = set.isWarmup ? block.warmupSets : block.workingSets;
    list.insert(index.clamp(0, list.length), set);
    notifyListeners();
  }
```

(e) In both `finish()` (next to `restStart = null;`) and `discard()`, add:

```dart
    _focusedSetId = null;
    _rirPromptSetId = null;
    _rirPromptUntil = null;
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `make -C app test TEST=test/session/controller_live_set_test.dart`
Expected: PASS.
Then run `make -C app test`. Expected: all pass. `controller_edit_test.dart` ignores `removeSet`'s return value, which is fine.

- [ ] **Step 5: Commit**

```bash
git add app/lib/session/active_session_controller.dart app/test/session/controller_live_set_test.dart
git commit -m "feat(app): track a live set, RIR prompt and set undo in the session controller"
```

---

### Task 2: Strings

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app_it.arb`, `app_de.arb`, `app_es.arb`
- Regenerated: `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/l10n/arb_parity_test.dart` (existing)

**Interfaces:**
- Produces these `AppLocalizations` getters and methods, used by Tasks 4–8:
  - `sessionLogSet(int index, String weight, int reps)`
  - `sessionLogWarmup(String weight, int reps)`
  - `sessionUpdateSet(int index)`
  - `sessionUpdateWarmup`
  - `sessionLiveSet(int index)`
  - `sessionLiveWarmup`
  - `sessionLiveLogged(String label)`
  - `sessionLastRef(String weight, int reps, String ago)`
  - `sessionMarkNotDone`
  - `sessionRestNext(String what)`
  - `sessionNextSet(String exercise, int index, String weight, int reps)`
  - `sessionNextWarmup(String exercise, String weight, int reps)`
  - `sessionWorkoutOptions`
  - `sessionExerciseOptions`
  - `sessionDiscardWorkout`
  - `sessionAddWarmupSet`
  - `sessionSetRemoved`
  - `commonUndo`
  - `sessionMinimize`

The dead keys `sessionColSet`, `sessionLastLabel` and `sessionAddWarmup` are deleted in Task 8, after their last use is gone.

- [ ] **Step 1: Add the English strings**

In `app/lib/l10n/app_en.arb`, insert after the `"sessionRir"` entry and its `"@sessionRir"` metadata. Keep the JSON valid, and watch the commas.

```json
  "sessionLogSet": "Log set {index} · {weight} × {reps}",
  "@sessionLogSet": {
    "placeholders": {
      "index": {"type": "int"},
      "weight": {"type": "String"},
      "reps": {"type": "int"}
    }
  },
  "sessionLogWarmup": "Log warm-up · {weight} × {reps}",
  "@sessionLogWarmup": {
    "placeholders": {
      "weight": {"type": "String"},
      "reps": {"type": "int"}
    }
  },
  "sessionUpdateSet": "Update set {index}",
  "@sessionUpdateSet": {
    "placeholders": {"index": {"type": "int"}}
  },
  "sessionUpdateWarmup": "Update warm-up",
  "sessionLiveSet": "SET {index}",
  "@sessionLiveSet": {
    "placeholders": {"index": {"type": "int"}}
  },
  "sessionLiveWarmup": "WARM-UP",
  "sessionLiveLogged": "{label} · LOGGED",
  "@sessionLiveLogged": {
    "placeholders": {"label": {"type": "String"}}
  },
  "sessionLastRef": "last {weight} × {reps} · {ago}",
  "@sessionLastRef": {
    "placeholders": {
      "weight": {"type": "String"},
      "reps": {"type": "int"},
      "ago": {"type": "String"}
    }
  },
  "sessionMarkNotDone": "Mark as not done",
  "sessionRestNext": "Next · {what}",
  "@sessionRestNext": {
    "placeholders": {"what": {"type": "String"}}
  },
  "sessionNextSet": "{exercise} · set {index} · {weight} × {reps}",
  "@sessionNextSet": {
    "placeholders": {
      "exercise": {"type": "String"},
      "index": {"type": "int"},
      "weight": {"type": "String"},
      "reps": {"type": "int"}
    }
  },
  "sessionNextWarmup": "{exercise} · warm-up · {weight} × {reps}",
  "@sessionNextWarmup": {
    "placeholders": {
      "exercise": {"type": "String"},
      "weight": {"type": "String"},
      "reps": {"type": "int"}
    }
  },
  "sessionWorkoutOptions": "Workout options",
  "sessionExerciseOptions": "Exercise options",
  "sessionDiscardWorkout": "Discard workout",
  "sessionAddWarmupSet": "Add warm-up",
  "sessionSetRemoved": "Set removed",
  "commonUndo": "Undo",
  "sessionMinimize": "Minimize",
```

- [ ] **Step 2: Add the same keys to it/de/es**

The other locale files carry no `@` metadata, because the template holds it. Insert the key/value pairs after each file's `"sessionRir"` line.

`app_it.arb`:
```json
  "sessionLogSet": "Registra serie {index} · {weight} × {reps}",
  "sessionLogWarmup": "Registra riscaldamento · {weight} × {reps}",
  "sessionUpdateSet": "Aggiorna serie {index}",
  "sessionUpdateWarmup": "Aggiorna riscaldamento",
  "sessionLiveSet": "SERIE {index}",
  "sessionLiveWarmup": "RISCALDAMENTO",
  "sessionLiveLogged": "{label} · REGISTRATA",
  "sessionLastRef": "ultima {weight} × {reps} · {ago}",
  "sessionMarkNotDone": "Segna come non fatta",
  "sessionRestNext": "Dopo · {what}",
  "sessionNextSet": "{exercise} · serie {index} · {weight} × {reps}",
  "sessionNextWarmup": "{exercise} · riscaldamento · {weight} × {reps}",
  "sessionWorkoutOptions": "Opzioni allenamento",
  "sessionExerciseOptions": "Opzioni esercizio",
  "sessionDiscardWorkout": "Scarta allenamento",
  "sessionAddWarmupSet": "Aggiungi riscaldamento",
  "sessionSetRemoved": "Serie rimossa",
  "commonUndo": "Annulla",
  "sessionMinimize": "Riduci",
```

`app_de.arb`:
```json
  "sessionLogSet": "Satz {index} speichern · {weight} × {reps}",
  "sessionLogWarmup": "Aufwärmsatz speichern · {weight} × {reps}",
  "sessionUpdateSet": "Satz {index} aktualisieren",
  "sessionUpdateWarmup": "Aufwärmsatz aktualisieren",
  "sessionLiveSet": "SATZ {index}",
  "sessionLiveWarmup": "AUFWÄRMEN",
  "sessionLiveLogged": "{label} · GESPEICHERT",
  "sessionLastRef": "zuletzt {weight} × {reps} · {ago}",
  "sessionMarkNotDone": "Als nicht erledigt markieren",
  "sessionRestNext": "Als Nächstes · {what}",
  "sessionNextSet": "{exercise} · Satz {index} · {weight} × {reps}",
  "sessionNextWarmup": "{exercise} · Aufwärmen · {weight} × {reps}",
  "sessionWorkoutOptions": "Trainingsoptionen",
  "sessionExerciseOptions": "Übungsoptionen",
  "sessionDiscardWorkout": "Training verwerfen",
  "sessionAddWarmupSet": "Aufwärmsatz hinzufügen",
  "sessionSetRemoved": "Satz entfernt",
  "commonUndo": "Rückgängig",
  "sessionMinimize": "Minimieren",
```

`app_es.arb`:
```json
  "sessionLogSet": "Registrar serie {index} · {weight} × {reps}",
  "sessionLogWarmup": "Registrar calentamiento · {weight} × {reps}",
  "sessionUpdateSet": "Actualizar serie {index}",
  "sessionUpdateWarmup": "Actualizar calentamiento",
  "sessionLiveSet": "SERIE {index}",
  "sessionLiveWarmup": "CALENTAMIENTO",
  "sessionLiveLogged": "{label} · REGISTRADA",
  "sessionLastRef": "última {weight} × {reps} · {ago}",
  "sessionMarkNotDone": "Marcar como no hecha",
  "sessionRestNext": "Siguiente · {what}",
  "sessionNextSet": "{exercise} · serie {index} · {weight} × {reps}",
  "sessionNextWarmup": "{exercise} · calentamiento · {weight} × {reps}",
  "sessionWorkoutOptions": "Opciones del entrenamiento",
  "sessionExerciseOptions": "Opciones del ejercicio",
  "sessionDiscardWorkout": "Descartar entrenamiento",
  "sessionAddWarmupSet": "Añadir calentamiento",
  "sessionSetRemoved": "Serie eliminada",
  "commonUndo": "Deshacer",
  "sessionMinimize": "Minimizar",
```

- [ ] **Step 3: Regenerate and verify**

Run: `make -C app get`. With `generate: true`, this regenerates `app_localizations*.dart`.
Then run: `make -C app test TEST=test/l10n/arb_parity_test.dart`. Expected: PASS.
Then run: `make -C app analyze`. Expected: "No issues found".

- [ ] **Step 4: Commit**

```bash
git add app/lib/l10n/
git commit -m "feat(app): add live set, log bar and session menu strings"
```

---

### Task 3: Large stepper, taller RIR chips, `⋯` icon and the action sheet

**Files:**
- Modify: `app/lib/widgets/stepper.dart`, `app/lib/widgets/rir_picker.dart`, `app/lib/theme/icons.dart`
- Create: `app/lib/widgets/w_action_sheet.dart`
- Test: `app/test/widgets/stepper_large_test.dart`, `app/test/widgets/w_action_sheet_test.dart`

**Interfaces:**
- Produces:
  - `WStepper(..., large: bool = false)`
  - `RirPicker(..., height: double = 30)`
  - `WIcons.more`
  - `class WSheetAction<T> { const WSheetAction({required String label, required T value, required IconData icon, bool destructive = false, bool enabled = true}); }`
  - `Future<T?> showWActionSheet<T>(BuildContext context, {required String title, required List<WSheetAction<T>> actions})`

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/stepper_large_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/rir_picker.dart';
import 'package:workout_tracker/widgets/stepper.dart';

import '../support/l10n_harness.dart';

void main() {
  Widget host(Widget child) => wrapL10n(SizedBox(width: 232, child: child));

  testWidgets('large stepper has 56dp buttons and still steps', (tester) async {
    double? got;
    await tester.pumpWidget(host(WStepper(
      value: 140, step: 2.5, format: (v) => v.toStringAsFixed(1),
      large: true, editable: true, onChanged: (v) => got = v,
    )));
    final inc = tester.getSize(find.byKey(const Key('stepper-inc')));
    expect(inc.width, greaterThanOrEqualTo(56));
    expect(inc.height, greaterThanOrEqualTo(56));
    await tester.tap(find.byKey(const Key('stepper-inc')));
    expect(got, 142.5);
  });

  testWidgets('large editable stepper shows an edit cue under the value', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 140, step: 2.5, format: (v) => '$v', large: true, editable: true, onChanged: (_) {},
    )));
    expect(find.byKey(const Key('stepper-edit-cue')), findsOneWidget);
  });

  testWidgets('default stepper keeps its compact size and has no cue', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 8, step: 1, format: (v) => '$v', editable: true, onChanged: (_) {},
    )));
    expect(tester.getSize(find.byKey(const Key('stepper-inc'))), const Size(25, 34));
    expect(find.byKey(const Key('stepper-edit-cue')), findsNothing);
  });

  testWidgets('large value scales down instead of ellipsising', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: host(WStepper(value: 142.5, step: 2.5, format: (v) => v.toStringAsFixed(1),
          large: true, onChanged: (_) {})),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('RirPicker honours its height', (tester) async {
    await tester.pumpWidget(host(RirPicker(value: 1, height: 48, onChanged: (_) {})));
    expect(tester.getSize(find.byKey(const Key('rir-2'))).height, 48);
  });
}
```

Create `app/test/widgets/w_action_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/w_action_sheet.dart';

import '../support/l10n_harness.dart';

void main() {
  late String? result;

  Widget host() => wrapL10n(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showWActionSheet<String>(context, title: 'Options', actions: const [
              WSheetAction(label: 'Add set', value: 'add', icon: Icons.add),
              WSheetAction(label: 'Move up', value: 'up', icon: Icons.north, enabled: false),
              WSheetAction(label: 'Remove', value: 'rm', icon: Icons.delete_outline, destructive: true),
            ]);
          },
          child: const Text('open'),
        ),
      ));

  setUp(() => result = null);

  testWidgets('returns the tapped action value', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result, 'rm');
    expect(find.text('Options'), findsNothing);
  });

  testWidgets('a disabled action does nothing', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Options'), findsOneWidget);
  });

  testWidgets('rows are at least 56dp tall', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Add set'), matching: find.byKey(const ValueKey('sheet-action-0')));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `make -C app test TEST=test/widgets/stepper_large_test.dart` and `make -C app test TEST=test/widgets/w_action_sheet_test.dart`
Expected: FAIL to compile. `large`, `height` and `w_action_sheet.dart` don't exist yet.

- [ ] **Step 3: Implement**

**`app/lib/theme/icons.dart`.** After `resume`, add:
```dart
  static const IconData more = Icons.more_horiz;
```

**`app/lib/widgets/rir_picker.dart`:**
- Add the constructor parameter `this.height = 30,` and the field `final double height;` with the doc comment `/// Chip height; the live workout's post-log strip uses 48.`
- Replace `height: 30,` in the `Container` with `height: height,`.

**`app/lib/widgets/stepper.dart`:**
- Add the constructor parameter `this.large = false,` and the field below:
```dart
  /// The live workout's focused-set size: 56dp buttons, a 30pt tabular value
  /// that scales down rather than ellipsising, and an edit cue when
  /// [editable]. The default stays the compact row size.
  final bool large;
```
- In `build`, replace the `btn` container size and the `Row` body. The full new `build` is:

```dart
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final large = widget.large;
    final btnSize = large ? const Size(56, 56) : const Size(25, 34);
    final gap = large ? 8.0 : 4.0;
    final valueStyle = large
        ? WorkoutType.display(size: 30, weight: FontWeight.w700, color: tokens.text)
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : WorkoutType.mono(size: 15, weight: FontWeight.w700, color: tokens.text);

    final buttonDecoration = BoxDecoration(
      color: tokens.surface3,
      borderRadius: BorderRadius.circular(AppRadius.radius * (large ? 0.6 : 0.4)),
    );

    Widget btn({required Key key, required IconData icon, required int dir}) {
      return GestureDetector(
        key: key,
        // Stop tap from propagating to parent (e.g. accordion header).
        behavior: HitTestBehavior.opaque,
        onTap: () => _step(dir),
        child: Container(
          width: btnSize.width,
          height: btnSize.height,
          decoration: buttonDecoration,
          alignment: Alignment.center,
          child: Icon(icon, size: large ? 22 : 16, color: tokens.text),
        ),
      );
    }

    final Widget label = Text(
      widget.format(_internalValue),
      key: ValueKey(widget.format(_internalValue)),
      maxLines: 1,
      overflow: large ? TextOverflow.visible : TextOverflow.ellipsis,
      style: valueStyle,
    );

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        btn(key: const Key('stepper-dec'), icon: Icons.remove, dir: -1),
        SizedBox(width: gap),
        Expanded(
          child: Center(
            child: _editing
                ? TextField(
                    controller: _editCtrl,
                    focusNode: _focusNode,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.numberWithOptions(
                        decimal: widget.allowDecimal),
                    inputFormatters: [
                      // A whole-string predicate, NOT
                      // FilteringTextInputFormatter.allow with an anchored
                      // pattern: that treats non-matching text as entirely
                      // banned and WIPES the field instead of rejecting the
                      // edit. Empty stays allowed so a sentinel can be typed
                      // back by clearing.
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        // A leading '-' is allowed through (no on-screen
                        // numeric keypad exposes one, but callers/tests can
                        // still supply it) so a negative value reaches
                        // clampRound2/parseNumberInput and gets clamped to
                        // [min], instead of being wiped by the formatter.
                        final ok = widget.allowDecimal
                            ? RegExp(r'^-?\d*[.,]?\d*$')
                                .hasMatch(newValue.text)
                            : RegExp(r'^-?\d*$').hasMatch(newValue.text);
                        return ok ? newValue : oldValue;
                      }),
                    ],
                    onSubmitted: (_) => _commitEdit(),
                    style: valueStyle,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _beginEdit,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: Motion.of(context, Motion.fast),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: Offset(0, _up ? 0.4 : -0.4),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: large
                              ? FittedBox(
                                  key: ValueKey(widget.format(_internalValue)),
                                  fit: BoxFit.scaleDown,
                                  child: label,
                                )
                              : label,
                        ),
                        if (large && widget.editable)
                          Container(
                            key: const Key('stepper-edit-cue'),
                            margin: const EdgeInsets.only(top: 2),
                            width: 28,
                            height: 1.5,
                            color: tokens.lineStrong,
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        SizedBox(width: gap),
        btn(key: const Key('stepper-inc'), icon: Icons.add, dir: 1),
      ],
    );
  }
```

This does not change the commit logic, `didUpdateWidget` or `deactivate`; see the `app/CLAUDE.md` stepper rules. `FontFeature` comes from `package:flutter/material.dart`, so no new import is needed.

**Create `app/lib/widgets/w_action_sheet.dart`:**

```dart
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One row in a [showWActionSheet].
class WSheetAction<T> {
  const WSheetAction({
    required this.label,
    required this.value,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData icon;
  final bool destructive;
  final bool enabled;
}

/// Tokens-styled bottom action sheet: a small caps [title] over 56dp rows.
/// Returns the tapped action's value, or null on dismiss. Disabled rows render
/// faint and ignore taps.
Future<T?> showWActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<WSheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _WActionSheetBody<T>(title: title, actions: actions),
  );
}

class _WActionSheetBody<T> extends StatelessWidget {
  const _WActionSheetBody({required this.title, required this.actions});

  final String title;
  final List<WSheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.radius),
          border: Border.all(color: tokens.lineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Text(
                title.toUpperCase(),
                style: WorkoutType.mono(
                    size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
              ),
            ),
            for (var i = 0; i < actions.length; i++)
              _row(context, tokens, i, actions[i]),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WorkoutTokens tokens, int i, WSheetAction<T> a) {
    final color = !a.enabled
        ? tokens.line
        : a.destructive
            ? tokens.danger
            : tokens.text;
    return Semantics(
      button: true,
      enabled: a.enabled,
      child: GestureDetector(
        key: ValueKey('sheet-action-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: a.enabled ? () => Navigator.of(context).pop(a.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(a.icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    a.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkoutType.body(size: 15, weight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `make -C app test TEST=test/widgets/stepper_large_test.dart`, then `make -C app test TEST=test/widgets/w_action_sheet_test.dart`, then `make -C app test`.
Expected: all PASS. The existing stepper tests still pass because the default path is unchanged in behaviour. The label now sits inside a `Column` with `mainAxisSize.min`. If an existing test finds the label by `Text` ancestor type, update only that finder.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/ app/lib/theme/icons.dart app/test/widgets/
git commit -m "feat(app): add a large stepper, tall RIR chips and a tokens action sheet"
```

---

### Task 4: `SetLine`, the compact set row with the RIR strip

**Files:**
- Create: `app/lib/session/set_line.dart`
- Delete: `app/lib/session/set_row.dart`, `app/test/session/set_row_overflow_test.dart`
- Test: `app/test/session/set_line_test.dart`

**Interfaces:**
- Consumes: `RirPicker(height:)` from Task 3.
- Produces:
  - `SetLine({Key? key, required SetState set, required int workIndex, required UnitService unit, required bool isLiveTop, required bool isLivePr, required bool showRirPrompt, required VoidCallback onTap, required ValueChanged<int> onRir})`
  - `workIndex` is -1 for warm-ups.

Deleting `set_row.dart` breaks `exercise_block.dart` until Task 6. In this task, only **create** `set_line.dart` and its test. Delete `set_row.dart` and its test in Task 6, where the last importer changes.

- [ ] **Step 1: Write the failing test**

Create `app/test/session/set_line_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/set_line.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

SetState _s({bool done = false, bool warmup = false, int? rir = 1}) => SetState(
    id: 's1', weightKg: 140, reps: 6, rir: warmup ? null : rir, isWarmup: warmup, done: done);

void main() {
  late int taps;
  late List<int> rirs;
  setUp(() {
    taps = 0;
    rirs = [];
  });

  Widget line(SetState s, {bool prompt = false, bool top = false, int idx = 1}) => SetLine(
        set: s, workIndex: s.isWarmup ? -1 : idx, unit: UnitService(),
        isLiveTop: top, isLivePr: false, showRirPrompt: prompt,
        onTap: () => taps++, onRir: rirs.add,
      );

  testWidgets('a pending line is a 48dp tap target showing weight × reps', (tester) async {
    await tester.pumpWidget(wrapL10n(line(_s())));
    // A Text.rich matches find.text by its whole plain text.
    expect(find.text('140kg  ×  6'), findsOneWidget);
    expect(tester.getSize(find.byType(SetLine)).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(SetLine));
    expect(taps, 1);
  });

  testWidgets('a logged line shows its RIR and the TOP tag', (tester) async {
    await tester.pumpWidget(wrapL10n(line(_s(done: true), top: true)));
    expect(find.text('RIR 1'), findsOneWidget);
    expect(find.text('TOP'), findsOneWidget);
  });

  testWidgets('the RIR strip shows 48dp chips; a chip tap sets RIR, not focus', (tester) async {
    await tester.pumpWidget(wrapL10n(line(_s(done: true), prompt: true)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('rir-2'))).height, 48);
    await tester.tap(find.byKey(const Key('rir-2')));
    expect(rirs, [2]);
    expect(taps, 0);
  });

  testWidgets('a warm-up never shows the RIR strip and shows a W index', (tester) async {
    await tester.pumpWidget(wrapL10n(line(_s(done: true, warmup: true), prompt: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rir-0')), findsNothing);
    expect(find.text('W'), findsOneWidget);
  });

  testWidgets('no overflow at 320dp / 1.3× (it)', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(SizedBox(width: 260, child: line(_s(done: true), prompt: true, top: true)),
          locale: const Locale('it')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make -C app test TEST=test/session/set_line_test.dart`
Expected: FAIL at compile time, because `set_line.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `app/lib/session/set_line.dart`:

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/pr_badge.dart';
import '../widgets/rir_picker.dart';
import '../widgets/tag.dart';
import 'active_session_controller.dart';

/// One not-live set in an exercise block: a read-only line that is a 48dp tap
/// target as a whole (a tap makes the set live). A just-logged working set
/// additionally shows the RIR correction strip under it while
/// [showRirPrompt] is true.
///
/// Logged: `1  140kg × 6  RIR 1   [TOP|PR]  ●✓`
/// Pending: `3  140kg × 6   ○`
class SetLine extends StatelessWidget {
  const SetLine({
    super.key,
    required this.set,
    required this.workIndex,
    required this.unit,
    required this.isLiveTop,
    required this.isLivePr,
    required this.showRirPrompt,
    required this.onTap,
    required this.onRir,
  });

  final SetState set;

  /// 1-based working-set index; -1 for warm-ups.
  final int workIndex;
  final UnitService unit;
  final bool isLiveTop;
  final bool isLivePr;
  final bool showRirPrompt;
  final VoidCallback onTap;
  final ValueChanged<int> onRir;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final done = set.done;
    final strip = showRirPrompt && done && !set.isWarmup;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    set.isWarmup ? l.sessionWarmupShort : '$workIndex',
                    textAlign: TextAlign.center,
                    style: WorkoutType.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: done && !set.isWarmup ? tokens.accent : tokens.faint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: unit.fmtWt(set.weightKg),
                        style: WorkoutType.mono(
                            size: 15,
                            weight: FontWeight.w700,
                            color: done ? tokens.text : tokens.dim),
                      ),
                      TextSpan(
                        text: unit.uLabel,
                        style: WorkoutType.mono(size: 11, color: tokens.faint),
                      ),
                      TextSpan(
                        text: '  ×  ',
                        style: WorkoutType.mono(size: 12, color: tokens.faint),
                      ),
                      TextSpan(
                        text: '${set.reps}',
                        style: WorkoutType.mono(
                            size: 15,
                            weight: FontWeight.w700,
                            color: done ? tokens.text : tokens.dim),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (done && !set.isWarmup) ...[
                  const SizedBox(width: 10),
                  Text(
                    l.sessionRir(set.rir ?? 0),
                    style: WorkoutType.mono(size: 10.5, color: tokens.faint),
                  ),
                ],
                const Spacer(),
                if (isLivePr)
                  const PRBadge(small: true)
                else if (isLiveTop)
                  Tag(label: l.sessionTagTop, tone: TagTone.solid),
                const SizedBox(width: 10),
                _StatusGlyph(done: done, tokens: tokens),
              ],
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: strip
                ? Padding(
                    padding: const EdgeInsets.only(left: 34, bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          l.sessionColRir,
                          style: WorkoutType.mono(
                              size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RirPicker(value: set.rir, height: 48, onChanged: onRir),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Filled accent check when logged, an empty ring when pending. Decorative:
/// the whole line is the tap target.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.done, required this.tokens});

  final bool done;
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? tokens.accent : null,
        border: done ? null : Border.all(color: tokens.lineStrong, width: 1.5),
      ),
      alignment: Alignment.center,
      child: done ? Icon(WIcons.check, size: 14, color: tokens.accentInk) : null,
    );
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `make -C app test TEST=test/session/set_line_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/session/set_line.dart app/test/session/set_line_test.dart
git commit -m "feat(app): add a compact set line with a post-log RIR strip"
```

---

### Task 5: `LiveSetCard`

**Files:**
- Create: `app/lib/session/live_set_card.dart`
- Test: `app/test/session/live_set_card_test.dart`

**Interfaces:**
- Consumes: `WStepper(large: true)` from Task 3, and the strings from Task 2.
- Produces:
  - `LiveSetCard({Key? key, required SetState set, required Exercise exercise, required int workIndex, required ({double weight, int reps, String date})? lastTop, required UnitService unit, required VoidCallback onChanged, required VoidCallback onMarkNotDone})`
  - The card mutates `set.weightKg`/`set.reps` in place and then calls `onChanged`, which is the same contract `SetRow` had.

- [ ] **Step 1: Write the failing test**

Create `app/test/session/live_set_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/live_set_card.dart';
import 'package:workout_tracker/units/unit_service.dart';
import 'package:workout_tracker/util/dates.dart';

import '../support/l10n_harness.dart';

const _ex = Exercise(
  id: 'lp', name: 'Leg press', slug: 'lp', muscleGroup: 'quads',
  compound: true, plateStepKg: 2.5, isTemplate: false,
);

SetState _s({bool done = false, bool warmup = false}) => SetState(
    id: 's', weightKg: 140, reps: 6, rir: warmup ? null : 1, isWarmup: warmup, done: done);

void main() {
  late int changes;
  late int unlogs;
  setUp(() {
    changes = 0;
    unlogs = 0;
  });

  Widget card(SetState s, {int idx = 2, ({double weight, int reps, String date})? last}) => LiveSetCard(
        set: s, exercise: _ex, workIndex: s.isWarmup ? -1 : idx, lastTop: last,
        unit: UnitService(), onChanged: () => changes++, onMarkNotDone: () => unlogs++,
      );

  Widget host(Widget child, {Locale locale = const Locale('en')}) =>
      wrapL10n(SingleChildScrollView(child: SizedBox(width: 260, child: child)), locale: locale);

  testWidgets('labels: pending set, warm-up, logged', (tester) async {
    await tester.pumpWidget(host(card(_s())));
    expect(find.text('SET 2'), findsOneWidget);
    await tester.pumpWidget(host(card(_s(warmup: true))));
    expect(find.text('WARM-UP'), findsOneWidget);
    await tester.pumpWidget(host(card(_s(done: true), idx: 1)));
    expect(find.text('SET 1 · LOGGED'), findsOneWidget);
  });

  testWidgets('the weight + button steps by the plate and reports the change', (tester) async {
    final s = _s();
    await tester.pumpWidget(host(card(s)));
    await tester.tap(find.byKey(const Key('stepper-inc')).first);
    expect(s.weightKg, 142.5);
    expect(changes, 1);
  });

  testWidgets('shows the last-session reference or no previous data', (tester) async {
    await tester.pumpWidget(host(card(_s(), last: (weight: 140, reps: 9, date: isoDate(DateTime.now())))));
    expect(find.text('last 140kg × 9 · today'), findsOneWidget);
    await tester.pumpWidget(host(card(_s())));
    expect(find.text('No previous data'), findsOneWidget);
  });

  testWidgets('mark-as-not-done shows only for a logged set and is 48dp tall', (tester) async {
    await tester.pumpWidget(host(card(_s())));
    expect(find.text('Mark as not done'), findsNothing);
    await tester.pumpWidget(host(card(_s(done: true))));
    final btn = find.byKey(const Key('live-mark-not-done'));
    expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));
    await tester.tap(btn);
    expect(unlogs, 1);
  });

  testWidgets('no overflow at 320dp / 1.3× (it)', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 900), textScaler: TextScaler.linear(1.3)),
      child: host(card(_s(done: true), last: (weight: 142.5, reps: 12, date: '2026-09-01')),
          locale: const Locale('it')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make -C app test TEST=test/session/live_set_card_test.dart`
Expected: FAIL at compile time.

- [ ] **Step 3: Implement**

Create `app/lib/session/live_set_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import '../widgets/stepper.dart';
import 'active_session_controller.dart';

/// The focused set of the workout: large weight and reps steppers, the
/// last-session reference, and — for a logged set being corrected — a
/// "mark as not done" action. Logging itself is the log bar's job.
///
/// Weight is held in kg; typed input converts back through
/// [UnitService.toKg] (see the stepper rules in app/CLAUDE.md).
class LiveSetCard extends StatelessWidget {
  const LiveSetCard({
    super.key,
    required this.set,
    required this.exercise,
    required this.workIndex,
    required this.lastTop,
    required this.unit,
    required this.onChanged,
    required this.onMarkNotDone,
  });

  final SetState set;
  final Exercise exercise;

  /// 1-based working-set index; -1 for warm-ups.
  final int workIndex;
  final ({double weight, int reps, String date})? lastTop;
  final UnitService unit;

  /// Called after the card mutates [set] in place.
  final VoidCallback onChanged;
  final VoidCallback onMarkNotDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final base = set.isWarmup ? l.sessionLiveWarmup : l.sessionLiveSet(workIndex);
    final label = set.done ? l.sessionLiveLogged(base) : base;
    final last = lastTop;

    TextStyle caption() => WorkoutType.mono(
        size: 10, color: tokens.faint, letterSpacing: 0.08 * 10);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.8),
        border: Border.all(color: tokens.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: WorkoutType.mono(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: tokens.accent,
                  letterSpacing: 0.08 * 10.5)),
          const SizedBox(height: 10),
          Text('${l.sessionColWeight} · ${unit.uLabel.toUpperCase()}', style: caption()),
          const SizedBox(height: 4),
          WStepper(
            value: set.weightKg,
            step: exercise.plateStepKg,
            format: (v) => unit.fmtWt(v),
            editable: true,
            large: true,
            parseDisplay: (v) => UnitService.toKg(v, unit.unit),
            min: 0,
            onChanged: (v) {
              set.weightKg = v;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Text(l.sessionColReps, style: caption()),
          const SizedBox(height: 4),
          WStepper(
            value: set.reps.toDouble(),
            step: 1,
            format: (v) => v.toInt().toString(),
            editable: true,
            large: true,
            allowDecimal: false,
            min: 0,
            onChanged: (v) {
              set.reps = v.toInt();
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Text(
            last == null
                ? l.sessionNoPreviousData
                : l.sessionLastRef('${unit.fmtWt(last.weight)}${unit.uLabel}',
                    last.reps, localizedDaysAgo(l, last.date)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkoutType.mono(size: 11.5, color: tokens.dim),
          ),
          if (set.done)
            GestureDetector(
              key: const Key('live-mark-not-done'),
              behavior: HitTestBehavior.opaque,
              onTap: onMarkNotDone,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Text(
                    l.sessionMarkNotDone,
                    style: WorkoutType.body(size: 14, weight: FontWeight.w600, color: tokens.dim),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `make -C app test TEST=test/session/live_set_card_test.dart`
Expected: PASS. If the `last …` text finder fails because `fmtWt(140)` renders `140`, the expected string is exactly `last 140kg × 9 · today`, and `localizedDaysAgo` of today's ISO date gives `today`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/session/live_set_card.dart app/test/session/live_set_card_test.dart
git commit -m "feat(app): add the live set card with large steppers and last-session reference"
```

---

### Task 6: `ExerciseBlock` renders lines and the live card; the header gets `⋯`

**Files:**
- Modify (rewrite the widget): `app/lib/session/exercise_block.dart`
- Delete: `app/lib/session/set_row.dart`, `app/test/session/set_row_overflow_test.dart`
- Rewrite: `app/test/session/exercise_block_edit_test.dart`
- Modify: `app/test/session/exercise_block_accordion_test.dart`

**Interfaces:**
- Consumes: `SetLine` (Task 4), `LiveSetCard` (Task 5), `liveTopOf` (Task 1), `WIcons.more` (Task 3).
- Produces:
  - `ExerciseBlock({Key? key, required BlockState block, required UnitService unit, required String? liveSetId, required String? rirPromptSetId, GlobalKey? liveCardKey, required void Function(BlockState, SetState) onFocusSet, required void Function(BlockState, SetState) onSetChanged, required void Function(BlockState, SetState, int) onRir, required void Function(BlockState, SetState) onMarkNotDone, void Function(BlockState, SetState)? onRemoveSet, required void Function(BlockState) onMenu})`
- Removed: `onToggleDone`, `onAddSet`, `onRemoveBlock`, `onAddWarmup`, `onMoveUp`, `onMoveDown`. The screen now reaches those through `onMenu` (Task 8).

- [ ] **Step 1: Write the failing tests**

Replace the whole of `app/test/session/exercise_block_edit_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/exercise_block.dart';
import 'package:workout_tracker/session/live_set_card.dart';
import 'package:workout_tracker/session/set_line.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

BlockState _block({bool firstDone = false, bool expanded = true}) {
  const exercise = Exercise(
    id: 'e1', name: 'Bench Press', slug: 'bench', muscleGroup: 'chest',
    compound: true, plateStepKg: 2.5, isTemplate: false,
  );
  return BlockState(
    exercise: exercise,
    resolved: const ResolvedSlot(exercise: exercise, workSets: 2, warmupSets: 0,
        repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 2),
    warmupSets: [],
    workingSets: [
      SetState(id: 's1', weightKg: 60, reps: 8, rir: 1, isWarmup: false, done: firstDone),
      SetState(id: 's2', weightKg: 60, reps: 8, rir: 1, isWarmup: false, done: false),
    ],
    expanded: expanded,
  );
}

void main() {
  late List<String> removed;
  late List<String> focused;
  late int menus;

  setUp(() {
    removed = [];
    focused = [];
    menus = 0;
  });

  Widget host(BlockState b, {String? live = 's2', String? prompt}) => wrapL10n(
        SingleChildScrollView(
          child: ExerciseBlock(
            key: const ValueKey('e1'),
            block: b,
            unit: UnitService(),
            liveSetId: live,
            rirPromptSetId: prompt,
            onFocusSet: (_, s) => focused.add(s.id),
            onSetChanged: (_, __) {},
            onRir: (_, __, ___) {},
            onMarkNotDone: (_, __) {},
            onRemoveSet: (_, s) => removed.add(s.id),
            onMenu: (_) => menus++,
          ),
        ),
      );

  Finder rowOf(String setId) => find.byKey(ValueKey('dismiss-$setId'));

  testWidgets('the live set renders as the card, the others as lines', (tester) async {
    await tester.pumpWidget(host(_block(firstDone: true)));
    await tester.pumpAndSettle();
    expect(find.byType(LiveSetCard), findsOneWidget);
    expect(find.byType(SetLine), findsOneWidget);
  });

  testWidgets('tapping a line focuses that set', (tester) async {
    await tester.pumpWidget(host(_block(firstDone: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SetLine));
    expect(focused, ['s1']);
  });

  testWidgets('a block holding the live set renders expanded even if collapsed', (tester) async {
    await tester.pumpWidget(host(_block(expanded: false)));
    await tester.pumpAndSettle();
    expect(find.byType(LiveSetCard), findsOneWidget);
  });

  testWidgets('a collapsed block without the live set shows no sets', (tester) async {
    await tester.pumpWidget(host(_block(expanded: false), live: null));
    await tester.pumpAndSettle();
    expect(find.byType(SetLine), findsNothing);
  });

  testWidgets('the header ⋯ is a labelled 48dp button that opens the menu', (tester) async {
    await tester.pumpWidget(host(_block()));
    await tester.pumpAndSettle();
    final more = find.bySemanticsLabel('Exercise options');
    expect(more, findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('block-menu-e1'))).height, greaterThanOrEqualTo(48));
    await tester.tap(more);
    expect(menus, 1);
  });

  testWidgets('the old footer is gone', (tester) async {
    await tester.pumpWidget(host(_block()));
    await tester.pumpAndSettle();
    expect(find.text('Add set'), findsNothing);
    expect(find.text('Remove exercise'), findsNothing);
  });

  testWidgets('swiping an unticked set left removes it without asking', (tester) async {
    await tester.pumpWidget(host(_block(), live: 's2'));
    await tester.pumpAndSettle();
    await tester.drag(rowOf('s1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove set?'), findsNothing);
    expect(removed, ['s1']);
  });

  testWidgets('swiping a ticked set asks first; cancelling keeps it', (tester) async {
    await tester.pumpWidget(host(_block(firstDone: true)));
    await tester.pumpAndSettle();
    await tester.drag(rowOf('s1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove set?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
    expect(rowOf('s1'), findsOneWidget);
  });

  testWidgets('no overflow on a narrow phone at large text (Italian)', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 1200), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ExerciseBlock(
              block: _block(firstDone: true),
              unit: UnitService(),
              liveSetId: 's2',
              rirPromptSetId: 's1',
              onFocusSet: (_, __) {},
              onSetChanged: (_, __) {},
              onRir: (_, __, ___) {},
              onMarkNotDone: (_, __) {},
              onRemoveSet: (_, __) {},
              onMenu: (_) {},
            ),
          ),
        ),
        locale: const Locale('it'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

In `app/test/session/exercise_block_accordion_test.dart`:
- Replace the `ExerciseBlock(...)` constructor call inside `host` with:
```dart
                child: ExerciseBlock(
                  key: const ValueKey('e1'),
                  block: b,
                  unit: UnitService(),
                  liveSetId: null,
                  rirPromptSetId: null,
                  onFocusSet: (_, __) {},
                  onSetChanged: (_, __) {},
                  onRir: (_, __, ___) {},
                  onMarkNotDone: (_, __) {},
                  onMenu: (_) {},
                ),
```
- Replace every `find.text('Add set')` with `find.byType(SetLine)` and add the import `import 'package:workout_tracker/session/set_line.dart';`. The set `s1` is pending and not live, so it renders as a `SetLine` while the block is expanded.

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `make -C app test TEST=test/session/exercise_block_edit_test.dart`
Expected: FAIL at compile time. The new constructor parameters don't exist yet.

- [ ] **Step 3: Implement**

Delete `app/lib/session/set_row.dart` and `app/test/session/set_row_overflow_test.dart` with `git rm`.

In `app/lib/session/exercise_block.dart`:

(a) **Imports.** Replace `import 'set_row.dart';` with `import 'live_set_card.dart';` and `import 'set_line.dart';`. Remove `import '../util/dates.dart';`, since `_LastTopRow` is deleted.

(b) **Constructor and fields.** Replace them with:

```dart
class ExerciseBlock extends StatefulWidget {
  const ExerciseBlock({
    super.key,
    required this.block,
    required this.unit,
    required this.liveSetId,
    required this.rirPromptSetId,
    this.liveCardKey,
    required this.onFocusSet,
    required this.onSetChanged,
    required this.onRir,
    required this.onMarkNotDone,
    this.onRemoveSet,
    required this.onMenu,
  });

  final BlockState block;
  final UnitService unit;

  /// The workout's live set id; when it belongs to this block that set renders
  /// as the [LiveSetCard] and the block renders expanded.
  final String? liveSetId;

  /// The logged set whose RIR strip is open, if it is in this block.
  final String? rirPromptSetId;

  /// Put on the live card (when it is in this block) so the screen can scroll
  /// it into view.
  final GlobalKey? liveCardKey;

  final void Function(BlockState, SetState) onFocusSet;
  final void Function(BlockState, SetState) onSetChanged;
  final void Function(BlockState, SetState, int) onRir;
  final void Function(BlockState, SetState) onMarkNotDone;

  /// Swipe-left removal of a set. Null disables the swipe. A ticked set is
  /// confirmed first; an unticked one goes straight away.
  final void Function(BlockState, SetState)? onRemoveSet;

  /// The header's ⋯ button (add set / warm-up, reorder, remove exercise).
  final void Function(BlockState) onMenu;
```

(c) **`build`.** Replace the whole method:
- Remove the column-header row, the `_LastTopRow`, the footer buttons and the move/remove row.
- Compute `containsLive` and `showSets`.
- Render `LiveSetCard` for the live set and `SetLine` for the rest.
- Add the `⋯` header button.

The full method:

```dart
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final block = widget.block;
    final ex = block.exercise;
    final resolved = block.resolved;
    final unit = widget.unit;

    final working = block.workingSets;
    final doneWorking = working.where((s) => s.done).length;
    final allDone = working.isNotEmpty && doneWorking == working.length;
    final top = liveTopOf(block);
    final containsLive =
        widget.liveSetId != null && block.allSets.any((s) => s.id == widget.liveSetId);
    final showSets = block.expanded || containsLive;

    final rirStr = resolved.rirLow == resolved.rirHigh
        ? '${resolved.rirLow}'
        : '${resolved.rirLow}–${resolved.rirHigh}';
    final subLabel =
        '${ex.muscleGroup} · ${resolved.workSets}×${resolved.repLow}–${resolved.repHigh} @ RIR $rirStr';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.radius),
        border: Border.all(color: showSets ? tokens.lineStrong : tokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The block holding the live set stays open.
            onTap: containsLive
                ? null
                : () => setState(() => block.expanded = !block.expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: allDone ? tokens.accent : tokens.surface3,
                      borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
                    ),
                    alignment: Alignment.center,
                    child: allDone
                        ? Icon(Icons.check, size: 18, color: tokens.accentInk)
                        : Text(
                            '$doneWorking/${working.length}',
                            style: WorkoutType.mono(
                                size: 13, weight: FontWeight.w700, color: tokens.dim),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex.name,
                          style: WorkoutType.body(
                              size: 15, weight: FontWeight.w600, color: tokens.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkoutType.mono(size: 10.5, color: tokens.faint),
                        ),
                      ],
                    ),
                  ),
                  if (top.topKg > 0) ...[
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(
                            text: unit.fmtWt(top.topKg),
                            style: WorkoutType.mono(
                                size: 14, weight: FontWeight.w700, color: tokens.text),
                          ),
                          TextSpan(
                            text: unit.uLabel,
                            style: WorkoutType.mono(size: 10, color: tokens.faint),
                          ),
                        ])),
                        if (top.isPr) ...[
                          const SizedBox(height: 2),
                          const PRBadge(small: true),
                        ],
                      ],
                    ),
                  ],
                  Semantics(
                    button: true,
                    label: l.sessionExerciseOptions,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: ValueKey('block-menu-${ex.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onMenu(block),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(WIcons.more, size: 20, color: tokens.dim),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sets ───────────────────────────────────────────────────────
          if (showSets)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: AnimatedSize(
                duration: Motion.of(context, Motion.base),
                curve: Motion.curve,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in block.allSets) _setWidget(block, s, top, tokens),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _setWidget(BlockState block, SetState s,
      ({double topKg, bool isPr}) top, WorkoutTokens tokens) {
    final workIdx = s.isWarmup ? -1 : block.workingSets.indexOf(s) + 1;
    final Widget child;
    if (s.id == widget.liveSetId) {
      final card = LiveSetCard(
        key: ValueKey('live-${s.id}'),
        set: s,
        exercise: block.exercise,
        workIndex: workIdx,
        lastTop: block.lastTop,
        unit: widget.unit,
        onChanged: () => widget.onSetChanged(block, s),
        onMarkNotDone: () => widget.onMarkNotDone(block, s),
      );
      child = widget.liveCardKey == null
          ? card
          : KeyedSubtree(key: widget.liveCardKey, child: card);
    } else {
      final isLiveTop = s.done && !s.isWarmup && top.topKg > 0 && s.weightKg == top.topKg;
      child = SetLine(
        set: s,
        workIndex: workIdx,
        unit: widget.unit,
        isLiveTop: isLiveTop,
        isLivePr: isLiveTop && top.isPr,
        showRirPrompt: s.id == widget.rirPromptSetId,
        onTap: () => widget.onFocusSet(block, s),
        onRir: (v) => widget.onRir(block, s, v),
      );
    }
    final onRemoveSet = widget.onRemoveSet;
    return Reveal(
      key: ValueKey(s.id),
      child: onRemoveSet == null
          ? child
          : Dismissible(
              key: ValueKey('dismiss-${s.id}'),
              direction: DismissDirection.endToStart,
              background: _RemoveSetBackground(tokens: tokens),
              confirmDismiss: (_) => _confirmRemoveSet(s),
              onDismissed: (_) => onRemoveSet(block, s),
              child: child,
            ),
    );
  }
```

(d) **Delete** the now-unused classes `_LastTopRow`, `_DashedBlockButton`, `_MoveButton` and `_RemoveExerciseButton`. Keep `_RemoveSetBackground` and `_confirmRemoveSet`.

**Temporary screen compile fix.** `active_session_screen.dart` still passes the old parameters. So that this task compiles and its tests run, replace the `ExerciseBlock(...)` call there with the new constructor using these interim callbacks:

```dart
                        child: ExerciseBlock(
                          block: block,
                          unit: unit,
                          liveSetId: controller.liveSet?.set.id,
                          rirPromptSetId: controller.rirPromptSetId,
                          onFocusSet: (_, s) => controller.focusSet(s),
                          onSetChanged: (b, s) => controller.markChanged(),
                          onRir: (_, s, v) => controller.setRirFromPrompt(s, v),
                          onMarkNotDone: (_, s) => controller.markNotDone(s),
                          onRemoveSet: (b, s) => controller.removeSet(b, s),
                          onMenu: (_) {},
                        ),
```

Task 8 replaces this with the full wiring.

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `make -C app test TEST=test/session/exercise_block_edit_test.dart`, then `make -C app test TEST=test/session/exercise_block_accordion_test.dart`, then `make -C app analyze` and `make -C app test`.
Expected: all PASS, and analyze reports "No issues found". Analyze may flag `sessionAddWarmup`/`sessionColSet`/`sessionLastLabel` as unused; they are generated getters, so no warning is expected. They are removed in Task 8.

- [ ] **Step 5: Commit**

```bash
git add -A app/lib/session/ app/test/session/
git commit -m "feat(app): render the live set card and set lines in exercise blocks with a header menu"
```

---

### Task 7: `LogSetBar`

**Files:**
- Create: `app/lib/session/log_set_bar.dart`
- Test: `app/test/session/log_set_bar_test.dart`

**Interfaces:**
- Consumes: `LiveSet` (Task 1), the strings (Task 2), `LiveSetCard` (Task 5, test harness only).
- Produces:
  - `LogSetBar({Key? key, required LiveSet? live, required bool canFinish, required UnitService unit, required VoidCallback onLog, required VoidCallback onFinish})`
  - `static String? LogSetBar.labelFor(AppLocalizations l, UnitService unit, LiveSet? live, bool canFinish)`

- [ ] **Step 1: Write the failing test**

Create `app/test/session/log_set_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/live_set_card.dart';
import 'package:workout_tracker/session/log_set_bar.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

const _ex = Exercise(
  id: 'lp', name: 'Leg press', slug: 'lp', muscleGroup: 'quads',
  compound: true, plateStepKg: 2.5, isTemplate: false,
);

BlockState _block(List<SetState> warm, List<SetState> work) => BlockState(
      exercise: _ex,
      resolved: const ResolvedSlot(exercise: _ex, workSets: 3, warmupSets: 1,
          repLow: 6, repHigh: 8, rirLow: 1, rirHigh: 1),
      warmupSets: warm, workingSets: work, expanded: true,
    );

SetState _s(String id, {bool warmup = false, bool done = false}) => SetState(
    id: id, weightKg: warmup ? 70 : 140, reps: warmup ? 8 : 6,
    rir: warmup ? null : 1, isWarmup: warmup, done: done);

void main() {
  final unit = UnitService();
  final l = lookupAppLocalizations(const Locale('en'));

  group('labelFor', () {
    final w = _s('w', warmup: true);
    final a1 = _s('a1', done: true);
    final a2 = _s('a2');
    final b = _block([w], [a1, a2]);

    test('pending working set', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: a2), true), 'Log set 2 · 140kg × 6');
    });
    test('pending warm-up', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: w), false), 'Log warm-up · 70kg × 8');
    });
    test('logged working set being corrected', () {
      expect(LogSetBar.labelFor(l, unit, (block: b, set: a1), true), 'Update set 1');
    });
    test('logged warm-up being corrected', () {
      final dw = _s('dw', warmup: true, done: true);
      expect(LogSetBar.labelFor(l, unit, (block: _block([dw], []), set: dw), true), 'Update warm-up');
    });
    test('nothing live: finish when possible, hidden otherwise', () {
      expect(LogSetBar.labelFor(l, unit, null, true), 'Finish workout');
      expect(LogSetBar.labelFor(l, unit, null, false), isNull);
    });
  });

  testWidgets('the bar is 56dp tall, labelled, and logs on tap', (tester) async {
    final s = _s('a1');
    var logs = 0;
    await tester.pumpWidget(wrapL10n(Align(
      alignment: Alignment.bottomCenter,
      child: LogSetBar(
        live: (block: _block([], [s]), set: s), canFinish: false, unit: unit,
        onLog: () => logs++, onFinish: () {},
      ),
    )));
    final bar = find.byKey(const Key('log-set-bar'));
    expect(tester.getSize(bar).height, 56);
    expect(find.bySemanticsLabel('Log set 1 · 140kg × 6'), findsOneWidget);
    await tester.tap(bar);
    expect(logs, 1);
  });

  testWidgets('renders nothing when there is nothing to log or finish', (tester) async {
    await tester.pumpWidget(wrapL10n(LogSetBar(
      live: null, canFinish: false, unit: unit, onLog: () {}, onFinish: () {},
    )));
    expect(find.byKey(const Key('log-set-bar')), findsNothing);
  });

  testWidgets('with nothing live it finishes', (tester) async {
    var finishes = 0;
    await tester.pumpWidget(wrapL10n(Align(
      alignment: Alignment.bottomCenter,
      child: LogSetBar(live: null, canFinish: true, unit: unit, onLog: () {}, onFinish: () => finishes++),
    )));
    await tester.tap(find.byKey(const Key('log-set-bar')));
    expect(finishes, 1);
  });

  testWidgets('typed weight commits before the bar logs', (tester) async {
    final s = _s('a1');
    final block = _block([], [s]);
    final c = ActiveSessionController()
      ..seedForTest(SessionDraft(templateId: null, name: 'W', focus: '',
          startedAt: DateTime(2026, 9, 24), blocks: [block]));
    await tester.pumpWidget(wrapL10n(StatefulBuilder(
      builder: (context, setState) => Column(children: [
        LiveSetCard(set: s, exercise: _ex, workIndex: 1, lastTop: null, unit: unit,
            onChanged: c.markChanged, onMarkNotDone: () {}),
        const Spacer(),
        LogSetBar(live: c.liveSet, canFinish: c.canFinish, unit: unit,
            onLog: () => setState(() => c.logLiveSet()), onFinish: () {}),
      ]),
    )));
    // Open the weight field and type without pressing Done.
    await tester.tap(find.text('140'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '152.5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('log-set-bar')));
    await tester.pump();
    expect(s.weightKg, 152.5);
    expect(s.done, isTrue);
  });

  testWidgets('a long German label ellipsises on a narrow phone', (tester) async {
    final s = _s('a1');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: wrapL10n(Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 320, child: LogSetBar(
          live: (block: _block([], [s]), set: s), canFinish: false, unit: unit,
          onLog: () {}, onFinish: () {},
        )),
      ), locale: const Locale('de')),
    ));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make -C app test TEST=test/session/log_set_bar_test.dart`
Expected: FAIL at compile time.

- [ ] **Step 3: Implement**

Create `app/lib/session/log_set_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import 'active_session_controller.dart';

/// The live workout's one primary action, pinned above the system inset.
/// Its label names exactly what a tap does (see [labelFor]); it renders
/// nothing when there is neither a live set nor a finishable workout.
class LogSetBar extends StatelessWidget {
  const LogSetBar({
    super.key,
    required this.live,
    required this.canFinish,
    required this.unit,
    required this.onLog,
    required this.onFinish,
  });

  final LiveSet? live;
  final bool canFinish;
  final UnitService unit;

  /// Logs (or confirms the correction of) [live].
  final VoidCallback onLog;

  /// Finishes the workout; used when nothing is live.
  final VoidCallback onFinish;

  /// The bar's label, or null when the bar is hidden.
  static String? labelFor(
      AppLocalizations l, UnitService unit, LiveSet? live, bool canFinish) {
    if (live == null) return canFinish ? l.sessionFinishWorkout : null;
    final s = live.set;
    final index = live.block.workingSets.indexOf(s) + 1;
    if (s.done) return s.isWarmup ? l.sessionUpdateWarmup : l.sessionUpdateSet(index);
    final weight = '${unit.fmtWt(s.weightKg)}${unit.uLabel}';
    return s.isWarmup
        ? l.sessionLogWarmup(weight, s.reps)
        : l.sessionLogSet(index, weight, s.reps);
  }

  void _tap() {
    // A live-card value still being typed commits on focus loss only, and on
    // Android a tap on a non-text widget does not drop focus. Commit it
    // synchronously first, or the bar would log the pre-edit value.
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    if (live != null) {
      onLog();
    } else {
      onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = labelFor(AppLocalizations.of(context), unit, live, canFinish);
    if (label == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('log-set-bar'),
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(AppRadius.radius),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(WIcons.check, size: 20, color: tokens.accentInk),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.display(
                            size: 16, weight: FontWeight.w700, color: tokens.accentInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `make -C app test TEST=test/session/log_set_bar_test.dart`
Expected: PASS.

To prove the flush is load-bearing, temporarily delete the two `FocusManager` lines and rerun. `typed weight commits before the bar logs` must then FAIL with `weightKg` equal to 140. Restore the lines afterwards.

- [ ] **Step 5: Commit**

```bash
git add app/lib/session/log_set_bar.dart app/test/session/log_set_bar_test.dart
git commit -m "feat(app): add the pinned log set bar that commits typed values first"
```

---

### Task 8: `SessionHeader` with rest, and wiring the screen

**Files:**
- Create: `app/lib/session/session_header.dart`
- Delete: `app/lib/session/rest_timer.dart`
- Modify: `app/lib/session/active_session_screen.dart`
- Modify: `app/lib/l10n/app_{en,it,de,es}.arb` (delete `sessionColSet`, `sessionLastLabel` and `sessionAddWarmup`, plus the `@` metadata of the first two in en)
- Test: `app/test/session/session_header_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `SessionHeader({Key? key, required SessionDraft draft, required Duration elapsed, required int doneWork, required int totalWork, required int prCount, required DateTime? restStart, required int restTotal, required String nextLabel, required VoidCallback onMinimize, required VoidCallback onMenu, required VoidCallback onAdd30s, required VoidCallback onSkip})`
  - `String restNextLabel(AppLocalizations l, UnitService unit, LiveSet? live)`

- [ ] **Step 1: Write the failing test**

Create `app/test/session/session_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/models.dart';
import 'package:workout_tracker/l10n/app_localizations.dart';
import 'package:workout_tracker/session/active_session_controller.dart';
import 'package:workout_tracker/session/session_header.dart';
import 'package:workout_tracker/units/unit_service.dart';

import '../support/l10n_harness.dart';

const _ex = Exercise(
  id: 'lc', name: 'Lying leg curl', slug: 'lc', muscleGroup: 'hamstrings',
  compound: false, plateStepKg: 2.5, isTemplate: false,
);

final _draft = SessionDraft(templateId: 't', name: 'Lower B', focus: 'Posterior Chain',
    startedAt: DateTime(2026, 9, 24, 16), blocks: const []);

void main() {
  late int adds, skips, menus, mins;
  setUp(() => adds = skips = menus = mins = 0);

  Widget header({DateTime? restStart, int restTotal = 0, Locale locale = const Locale('en')}) => wrapL10n(
        SessionHeader(
          draft: _draft, elapsed: const Duration(minutes: 1, seconds: 2),
          doneWork: 1, totalWork: 14, prCount: 0,
          restStart: restStart, restTotal: restTotal,
          nextLabel: 'Next · Lying leg curl · set 1 · 40kg × 8',
          onMinimize: () => mins++, onMenu: () => menus++,
          onAdd30s: () => adds++, onSkip: () => skips++,
        ),
        locale: locale,
      );

  testWidgets('not resting: no rest row', (tester) async {
    await tester.pumpWidget(header());
    expect(find.text('REST'), findsNothing);
    expect(find.text('+30s'), findsNothing);
    expect(find.text('1:02'), findsOneWidget);
  });

  testWidgets('resting: countdown, next line and 48dp chips that fire', (tester) async {
    await tester.pumpWidget(header(restStart: DateTime.now(), restTotal: 90));
    expect(find.text('REST'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('Next · Lying leg curl · set 1 · 40kg × 8'), findsOneWidget);
    final add = find.byKey(const Key('rest-add'));
    final skip = find.byKey(const Key('rest-skip'));
    expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(48));
    await tester.tap(add);
    await tester.tap(skip);
    expect((adds, skips), (1, 1));
  });

  testWidgets('menu and minimize are labelled 48dp buttons', (tester) async {
    await tester.pumpWidget(header());
    await tester.tap(find.bySemanticsLabel('Workout options'));
    await tester.tap(find.bySemanticsLabel('Minimize'));
    expect((menus, mins), (1, 1));
    expect(tester.getSize(find.byKey(const Key('session-menu'))).height, greaterThanOrEqualTo(48));
  });

  testWidgets('no overflow at 320dp / 1.3× (de) while resting', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 800), textScaler: TextScaler.linear(1.3)),
      child: header(restStart: DateTime.now(), restTotal: 180, locale: const Locale('de')),
    ));
    expect(tester.takeException(), isNull);
  });

  group('restNextLabel', () {
    final l = lookupAppLocalizations(const Locale('en'));
    final unit = UnitService();
    BlockState block(List<SetState> warm, List<SetState> work) => BlockState(
        exercise: _ex,
        resolved: const ResolvedSlot(exercise: _ex, workSets: 1, warmupSets: 0,
            repLow: 8, repHigh: 10, rirLow: 1, rirHigh: 1),
        warmupSets: warm, workingSets: work, expanded: true);

    test('names the exercise, set and prescription', () {
      final s = SetState(id: 's', weightKg: 40, reps: 8, rir: 1, isWarmup: false, done: false);
      expect(restNextLabel(l, unit, (block: block([], [s]), set: s)),
          'Next · Lying leg curl · set 1 · 40kg × 8');
    });
    test('warm-up variant', () {
      final w = SetState(id: 'w', weightKg: 20, reps: 8, rir: null, isWarmup: true, done: false);
      expect(restNextLabel(l, unit, (block: block([w], []), set: w)),
          'Next · Lying leg curl · warm-up · 20kg × 8');
    });
    test('nothing left: finish', () {
      expect(restNextLabel(l, unit, null), 'Next · Finish workout');
    });
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `make -C app test TEST=test/session/session_header_test.dart`
Expected: FAIL at compile time.

- [ ] **Step 3: Implement `session_header.dart`**

Create `app/lib/session/session_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import 'active_session_controller.dart';

/// "Next · …" for the header rest row: the live set, or finishing.
String restNextLabel(AppLocalizations l, UnitService unit, LiveSet? live) {
  if (live == null) return l.sessionRestNext(l.sessionFinishWorkout);
  final s = live.set;
  final weight = '${unit.fmtWt(s.weightKg)}${unit.uLabel}';
  final name = live.block.exercise.name;
  return l.sessionRestNext(s.isWarmup
      ? l.sessionNextWarmup(name, weight, s.reps)
      : l.sessionNextSet(name, live.block.workingSets.indexOf(s) + 1, weight, s.reps));
}

/// The live workout's sticky header: minimize, title and set count, the ⋯
/// menu and elapsed time; under it the progress bar, which becomes a thicker
/// draining rest countdown while resting, with a rest row (countdown, what is
/// next, +30s / Skip). Replaces the old floating rest card, so nothing ever
/// covers the exercise list.
class SessionHeader extends StatelessWidget {
  const SessionHeader({
    super.key,
    required this.draft,
    required this.elapsed,
    required this.doneWork,
    required this.totalWork,
    required this.prCount,
    required this.restStart,
    required this.restTotal,
    required this.nextLabel,
    required this.onMinimize,
    required this.onMenu,
    required this.onAdd30s,
    required this.onSkip,
  });

  final SessionDraft draft;
  final Duration elapsed;
  final int doneWork;
  final int totalWork;
  final int prCount;
  final DateTime? restStart;
  final int restTotal;
  final String nextLabel;
  final VoidCallback onMinimize;
  final VoidCallback onMenu;
  final VoidCallback onAdd30s;
  final VoidCallback onSkip;

  /// Threshold (inclusive) for the final-seconds accent.
  static const _finalThreshold = 5;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final prText = prCount > 0 ? l.sessionPrCount(prCount) : '';
    final setsText = '${l.sessionSetsProgress(doneWork, totalWork)}$prText';
    final mm = elapsed.inMinutes;
    final ss = elapsed.inSeconds % 60;

    final start = restStart;
    final remaining = start == null
        ? 0
        : (restTotal - DateTime.now().difference(start).inSeconds).clamp(0, restTotal);
    final resting = start != null && remaining > 0;
    final progress = totalWork > 0 ? doneWork / totalWork : 0.0;
    final barFraction =
        resting ? (restTotal > 0 ? remaining / restTotal : 0.0) : progress.clamp(0.0, 1.0);

    Widget circleButton({required Key key, required String label, required VoidCallback onTap, required Widget icon}) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surface,
                    border: Border.all(color: tokens.line),
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
              ),
            ),
          ),
        );

    return Container(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
            child: Row(
              children: [
                circleButton(
                  key: const Key('session-minimize'),
                  label: l.sessionMinimize,
                  onTap: onMinimize,
                  icon: Transform.rotate(
                    angle: 1.5708,
                    child: Icon(WIcons.chevron, size: 18, color: tokens.dim),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: WorkoutType.display(
                              size: 18, weight: FontWeight.w700, color: tokens.text),
                          children: [
                            TextSpan(text: draft.name),
                            if (draft.focus.isNotEmpty)
                              TextSpan(
                                text: ' · ${draft.focus}',
                                style: WorkoutType.display(
                                    size: 18, weight: FontWeight.w600, color: tokens.faint),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(setsText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkoutType.mono(size: 11, color: tokens.faint)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$mm:${ss.toString().padLeft(2, '0')}',
                        style: WorkoutType.mono(
                            size: 18, weight: FontWeight.w700, color: tokens.accent)),
                    const SizedBox(height: 2),
                    Text(l.sessionElapsed,
                        style: WorkoutType.mono(
                            size: 9, color: tokens.faint, letterSpacing: 0.06 * 9)),
                  ],
                ),
                const SizedBox(width: 4),
                circleButton(
                  key: const Key('session-menu'),
                  label: l.sessionWorkoutOptions,
                  onTap: onMenu,
                  icon: Icon(WIcons.more, size: 18, color: tokens.dim),
                ),
              ],
            ),
          ),
          if (resting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Row(
                children: [
                  Text(l.restLabel,
                      style: WorkoutType.mono(
                          size: 10, color: tokens.faint, letterSpacing: 0.08 * 10)),
                  const SizedBox(width: 8),
                  AnimatedDefaultTextStyle(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.curve,
                    style: WorkoutType.display(
                      size: 20,
                      weight: FontWeight.w700,
                      color: remaining <= _finalThreshold ? tokens.accent : tokens.text,
                    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    child: Text('${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(nextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.mono(size: 11, color: tokens.dim)),
                  ),
                  const SizedBox(width: 8),
                  _RestChip(
                    key: const Key('rest-add'),
                    label: l.restAdd30s,
                    filled: false,
                    tokens: tokens,
                    onTap: onAdd30s,
                  ),
                  const SizedBox(width: 6),
                  _RestChip(
                    key: const Key('rest-skip'),
                    label: l.commonSkip,
                    filled: true,
                    tokens: tokens,
                    onTap: onSkip,
                  ),
                ],
              ),
            ),
          // Progress bar; while resting, a thicker draining countdown whose
          // fraction glides linearly between the one-second ticks.
          AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            height: resting ? 6 : 3,
            color: tokens.surface3,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: barFraction),
              duration: Motion.of(context, const Duration(seconds: 1)),
              curve: Curves.linear,
              builder: (_, value, __) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: tokens.accent),
              ),
            ),
          ),
          Container(height: 1, color: tokens.line),
        ],
      ),
    );
  }
}

class _RestChip extends StatelessWidget {
  const _RestChip({
    super.key,
    required this.label,
    required this.filled,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: filled ? tokens.accent : null,
          border: filled ? null : Border.all(color: tokens.lineStrong),
          borderRadius: BorderRadius.circular(AppRadius.radius * 0.5),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: WorkoutType.mono(
                size: 12,
                weight: FontWeight.w700,
                color: filled ? tokens.accentInk : tokens.dim)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the header test**

Run: `make -C app test TEST=test/session/session_header_test.dart`
Expected: PASS.

If the 320dp/German case overflows, the `Expanded` next line absorbs the squeeze. If it still overflows, lower the countdown to size 18. Do not remove the chips.

- [ ] **Step 5: Wire the screen**

In `app/lib/session/active_session_screen.dart`:

(a) **Imports.**
- Remove `import 'rest_timer.dart';`.
- Add `import '../widgets/w_action_sheet.dart';`, `import 'log_set_bar.dart';` and `import 'session_header.dart';`.

(b) **State fields.** Add below the haptic guards:
```dart
  /// On the live card, so logging can scroll the next live set into view.
  final GlobalKey _liveCardKey = GlobalKey();
```

(c) **Ticker.** Inside the ticker's periodic callback, before `setState(() {});`, add:
```dart
      c?.expireRirPrompt(DateTime.now());
```

(d) **Handlers.** Add these methods above `// ── Build`:

```dart
  int _restSecondsFor(BlockState b) {
    final settings = context.read<SettingsService>();
    return b.exercise.defaultRestSeconds ??
        (b.exercise.compound
            ? settings.restCompoundSeconds
            : settings.restIsolationSeconds);
  }

  /// The log bar: logs the live set (the bar has already committed any
  /// in-flight typed value), starts rest after a newly logged working set,
  /// and scrolls the next live set into view.
  void _logLive(ActiveSessionController c) {
    final r = c.logLiveSet();
    if (r == null) return;
    if (r.newlyDone) {
      final top = liveTopOf(r.block);
      final isPr = !r.set.isWarmup && top.isPr && r.set.weightKg == top.topKg;
      isPr ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
      if (!r.set.isWarmup) c.startRest(_restSecondsFor(r.block));
    } else {
      HapticFeedback.selectionClick();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _liveCardKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: 0.3);
    });
  }

  void _removeSet(ActiveSessionController c, BlockState b, SetState s) {
    final index = c.removeSet(b, s);
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l.sessionSetRemoved),
        action: SnackBarAction(
          label: l.commonUndo,
          onPressed: () => c.restoreSet(b, s, index),
        ),
      ));
  }

  Future<void> _openWorkoutMenu(ActiveSessionController c) async {
    final l = AppLocalizations.of(context);
    final picked = await showWActionSheet<String>(context,
        title: l.sessionWorkoutOptions,
        actions: [
          WSheetAction(
              label: l.sessionFinishWorkout,
              value: 'finish',
              icon: WIcons.check,
              enabled: c.canFinish),
          WSheetAction(
              label: l.sessionDiscardWorkout,
              value: 'discard',
              icon: WIcons.trash,
              destructive: true),
        ]);
    if (!mounted || picked == null) return;
    if (picked == 'finish') await _handleFinish(context, c);
    if (picked == 'discard' && mounted) await _handleClose(context, c);
  }

  Future<void> _openBlockMenu(ActiveSessionController c, BlockState b) async {
    final l = AppLocalizations.of(context);
    final blocks = c.draft.blocks;
    final picked = await showWActionSheet<String>(context,
        title: b.exercise.name,
        actions: [
          WSheetAction(label: l.sessionAddSet, value: 'set', icon: WIcons.plus),
          WSheetAction(label: l.sessionAddWarmupSet, value: 'warmup', icon: WIcons.flame),
          WSheetAction(
              label: l.sessionMoveUp,
              value: 'up',
              icon: Icons.keyboard_arrow_up,
              enabled: !identical(b, blocks.first)),
          WSheetAction(
              label: l.sessionMoveDown,
              value: 'down',
              icon: Icons.keyboard_arrow_down,
              enabled: !identical(b, blocks.last)),
          WSheetAction(
              label: l.sessionRemoveExercise,
              value: 'remove',
              icon: WIcons.trash,
              destructive: true),
        ]);
    if (!mounted || picked == null) return;
    switch (picked) {
      case 'set':
        c.addSet(b);
      case 'warmup':
        c.addWarmupSet(b);
      case 'up':
        c.moveBlock(b, -1);
      case 'down':
        c.moveBlock(b, 1);
      case 'remove':
        if (b.allSets.any((s) => s.done)) {
          final confirmed = await showWConfirm(
            context,
            title: l.sessionRemoveExerciseTitle,
            message: l.sessionRemoveExerciseMessage,
            confirmLabel: l.commonRemove,
            destructive: true,
          );
          if (confirmed == true) c.removeBlock(b);
        } else {
          c.removeBlock(b);
        }
    }
  }
```

(e) **`build`.** Replace everything from `final draft = controller.draft;` to the end of the method with:

```dart
    final draft = controller.draft;
    final live = controller.liveSet;

    return Scaffold(
      body: Column(
        children: [
          SessionHeader(
            draft: draft,
            elapsed: controller.elapsed,
            doneWork: controller.doneWork,
            totalWork: controller.totalWork,
            prCount: controller.prCount,
            restStart: controller.restStart,
            restTotal: controller.restTotal,
            nextLabel: restNextLabel(l, unit, live),
            onMinimize: () => Navigator.of(context).pop(),
            onMenu: () => _openWorkoutMenu(controller),
            onAdd30s: () {
              HapticFeedback.lightImpact();
              controller.addRestTime(30);
            },
            onSkip: controller.stopRest,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                if (draft.blocks.isEmpty) ...[
                  const SizedBox(height: 40),
                  _EmptySessionPlaceholder(tokens: tokens, l: l),
                  const SizedBox(height: 20),
                ],
                for (final block in draft.blocks)
                  Reveal(
                    key: ValueKey(block.exercise.id),
                    child: ExerciseBlock(
                      block: block,
                      unit: unit,
                      liveSetId: live?.set.id,
                      rirPromptSetId: controller.rirPromptSetId,
                      liveCardKey: _liveCardKey,
                      onFocusSet: (_, s) => controller.focusSet(s),
                      onSetChanged: (_, __) => controller.markChanged(),
                      onRir: (_, s, v) => controller.setRirFromPrompt(s, v),
                      onMarkNotDone: (_, s) => controller.markNotDone(s),
                      onRemoveSet: (b, s) => _removeSet(controller, b, s),
                      onMenu: (b) => _openBlockMenu(controller, b),
                    ),
                  ),
                const SizedBox(height: 10),
                _DashedButton(
                  height: 48,
                  icon: WIcons.plus,
                  label: l.sessionAddExercise,
                  tokens: tokens,
                  onTap: () async {
                    final repo = ExerciseRepository(db);
                    final all = await repo.all();
                    if (!context.mounted) return;
                    final picked = await showExercisePicker(context, exercises: all);
                    if (picked != null) {
                      await controller.addBlock(picked, sessionRepo: SessionRepository(db));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      // In bottomNavigationBar (not the body) so the undo snackbar floats above it.
      bottomNavigationBar: LogSetBar(
        live: live,
        canFinish: controller.canFinish,
        unit: unit,
        onLog: () => _logLive(controller),
        onFinish: () => _handleFinish(context, controller),
      ),
    );
  }
```

The build no longer auto-stops rest mid-build, so delete the old `restRemaining` block and its `addPostFrameCallback(stopRest)`; the ticker already stops rest at 0. Delete the `_Header` and `_FinishButton` classes. Keep `_EmptySessionPlaceholder` and `_DashedButton`. Update the class doc comment at the top of `ActiveSessionScreen` to describe the header, the list of blocks, the pinned log bar and rest in the header. Change `import 'package:flutter/services.dart';` only if analyze flags it; it is still used for haptics.

(f) **Delete the old timer.** `git rm app/lib/session/rest_timer.dart`.

(g) **Delete the dead strings.** Remove `sessionColSet`, `sessionLastLabel` (with `@sessionLastLabel` in en) and `sessionAddWarmup` from all four ARB files. Confirm nothing references them:

Run: `grep -rnE "sessionColSet|sessionLastLabel|sessionAddWarmup\b" app/lib app/test --include='*.dart' | grep -v 'lib/l10n/'`
Expected: no output. Then run `make -C app get` to regenerate.

- [ ] **Step 6: Verify**

Run: `make -C app analyze`. Expected: "No issues found".
Run: `make -C app test`. Expected: all pass.
Run: `make -C app build`. Expected: the Linux bundle builds.

- [ ] **Step 7: Commit**

```bash
git add -A app/lib/ app/test/
git commit -m "feat(app): pin the log bar, move rest into the header and session actions into menus"
```

---

### Task 9: Docs and device checks

**Files:**
- Modify: `app/AGENTS.md`, `docs/design_handoff_workout_tracker/README.md`

- [ ] **Step 1: Update `app/AGENTS.md`**

Under `## Architecture`, replace:

> Visual source of truth: `../docs/design_handoff_workout_tracker/` (README + `.jsx` prototypes). Match its exact control sizes; make rows flex for narrow phones.

with:

> Visual source of truth: `../docs/design_handoff_workout_tracker/` (README + `.jsx` prototypes). Match its exact control sizes; make rows flex for narrow phones. **Exception — the live workout screen** follows `../docs/superpowers/specs/2026-09-24-live-set-focus-design.md` instead of `screen-log.jsx`: one live set (`ActiveSessionController.liveSet`) in a `LiveSetCard`, the rest as `SetLine`s, a pinned `LogSetBar`, rest in `SessionHeader`, and per-block/workout actions in `showWActionSheet`. Every tappable there is ≥48dp.

Under `**UI/motion:**`, add a bullet:

> - The live workout's `LogSetBar` MUST commit any in-flight typed value before acting (`primaryFocus?.unfocus()` + `applyFocusChangesIfNeeded()`): a logged set can be re-opened in the live card, so a stepper can be mid-edit on a done set and the bar would otherwise log the pre-edit value. Pinned by `test/session/log_set_bar_test.dart`.

- [ ] **Step 2: Note the supersession in the handoff README**

At the end of `docs/design_handoff_workout_tracker/README.md`, append:

```markdown

## Superseded: live workout layout

The live workout screen (`screen-log.jsx` `SetRow`, `ExerciseBlock` footer, `RestTimer`) is superseded by `docs/superpowers/specs/2026-09-24-live-set-focus-design.md`: one live set with large steppers, compact read-only set lines, a pinned "Log set" bar, rest in the header, and ⋯ action sheets. Tokens, type and colour from this README still apply.
```

- [ ] **Step 3: Commit**

```bash
git add app/AGENTS.md docs/design_handoff_workout_tracker/README.md
git commit -m "docs: point the live workout screen at the live set focus spec"
```

- [ ] **Step 4: Device checks (a person with a phone; CI renders no pixels)**

On a release APK (`make -C app build-apk-release`), check each item:

1. Starting a template workout shows the first exercise expanded with its first set, or warm-up, as the live card. The bar reads "Log warm-up · …" or "Log set 1 · …".
2. One tap on the bar logs the set. Rest appears in the header with a draining bar and the "Next · …" line. The RIR strip shows on the logged line for about 4s, then collapses.
3. Logging the last set of an exercise collapses that exercise, expands the next, and scrolls its live card into view.
4. Tapping a logged set opens it as "SET 1 · LOGGED". Changing the weight and tapping "Update set 1" keeps it logged with the new weight. "Mark as not done" un-logs it.
5. Type a weight in the live card with the keypad open, then tap the bar. Where the bar is visible above the keypad, the typed value is logged; otherwise press Done first and confirm the value sticks.
6. Swiping a set away shows "Set removed · Undo" above the bar, and Undo puts it back in place.
7. The header ⋯ offers Finish (disabled until a working set is logged) and Discard (confirm dialog). The block ⋯ offers add set, warm-up, move and remove, with arrows disabled at the ends.
8. With gesture navigation, the bar sits above the home pill and nothing overlaps the list, including during rest.
9. Italian and German at the largest system font: no clipped or overflowing text on the card, lines, header or bar.
10. With the system's remove-animations setting on: nothing pulses, and strip and expand changes are instant.
11. Minimize during rest, then return: the notification and Today mini-bar rest still work, and the header shows the same remaining time.
```
