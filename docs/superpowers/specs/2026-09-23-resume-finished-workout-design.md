# v0.14.0 — resume a just-finished workout

**Date:** 2026-09-23
**Status:** Approved (design)
**Scope:** A workout finished by mistake can be resumed from History — if it belongs to today, or was finished within the last hour. Resuming brings back the workout exactly as it was when Finish was tapped (unticked planned sets, exercise order, targets, PR baseline, clock); finishing it again updates the same History entry instead of creating a second one. Ships as v0.14.0.

User report: "It happened sometime that I clicked Finish by error."

---

## 0. Current state

- **Finish is one tap, no confirmation.** `_FinishButton` (`session/active_session_screen.dart:620`) calls `_handleFinish` (`:152-180`) directly. `controller.finish` (`session/active_session_controller.dart:530-591`) writes the session and its **done** sets, then deletes `workout-draft.json` and nulls the draft. After a successful Finish nothing but the DB rows survives.
- **The DB cannot rebuild the workout.** It never holds: unticked planned sets, blocks with no done set, exercise order (`sets` has no position column; `setsForSession` orders by `exercise_id`), resolved targets (planned counts, rep/RIR ranges), the PR baseline (`bestKg`/`lastTop`), or `startedAt` (only a rounded `duration_min`). `name`/`focus` survive only joined into `split_label`.
- **There is no local "created at" timestamp.** `persistSession` (`data/session_writer.dart:123-156`) never writes `sessions.created_at`; the server fills it with `DEFAULT NOW()` at **upload** time. It is NULL on the phone until a sync round-trip, and NULL forever with no account. Only `sessions.date` (the local date at finish) is reliable, so "finished within the last hour" needs a new timestamp.
- **Finishing twice would duplicate or fail.** `finish()` always mints `uuid.v4()` for the session and plain-INSERTs every set with its draft id. A second finish of a restored draft would either create a second session or collide on set primary keys.
- **PR detection would compare the workout against itself.** `bestTopSet`/`lastTopSet` (`data/session_repository.dart:66-123`) have no session filter; any block built while the finished rows exist gets a `bestKg` that includes the session's own top set, so a real PR re-finishes as `is_pr = 0` — permanently for offline users (History edits never recompute `is_pr`).
- **Only one workout can be live, but nothing enforces it across an await.** `SessionManager.register` (`session/session_manager.dart:79-90`) silently swaps controllers; `startSession` checks `hasActive` and only registers after its awaits (`shell/session_launcher.dart:31-49`).
- **A deleted training day can make the server drop a session.** `sessions.day_template_id REFERENCES day_templates ON DELETE SET NULL` (`server/db/migrations/00012_session_day_template_fk.sql:5`); a session PUT carrying an id the server has already deleted fails the FK, is skipped, and every set PUT of the batch is then skipped as an orphan (`server/internal/api/sync_upload.go:194-203, 426-429`). `deleteDay` never touches sessions (`data/day_template_repository.dart:401-411`), so finishing a workout whose day was deleted mid-workout loses it on the next sync today.

The visual handoff (`docs/design_handoff_workout_tracker/`) is **silent** on resume, undo and finish confirmation — its History card is read-only. The app's History footer actions (edit sets, add exercise, delete session) are already a deliberate deviation; Resume joins them in the same inline style.

## 1. Behaviour

1. Finish a workout (by mistake). Go to History; today's card, expanded, shows **Resume workout** as its first action.
2. Tap it: the workout opens as the live workout — every set you had ticked, every planned set you had not, the same exercise order and targets. The clock continues from where it stopped (the time between Finish and Resume is not counted). The ongoing notification, mini-bar and Today's resume hero come back.
3. Keep logging, then Finish again: History still has **one** entry — same id, same date — now holding the updated sets and the combined duration.
4. Or Discard instead: the History entry stays exactly as it was when you finished, and Resume is still offered while the window lasts.

Resume is offered only for **the last workout finished on this device**, and only while it is **eligible** (§3). Nothing is written to the database when resuming; the finished rows are replaced only when the resumed workout is finished again.

## 2. The finished-workout snapshot

At Finish the draft is not thrown away. `finish()` records a snapshot of it:

```dart
class FinishedSession {
  final String sessionId;    // the sessions.id this finish wrote
  final String sessionDate;  // the sessions.date this finish wrote (YYYY-MM-DD)
  final DateTime finishedAt; // local wall clock at finish
  final int elapsedSeconds;  // workout time at finish (what duration_min rounds)
  final SessionDraft draft;  // the draft exactly as it was when Finish was tapped
}
```

- **Where:** `app/lib/data/finished_session_store.dart` — `FinishedSession` (with `toJson`/`fromJson`) and `FinishedSessionStore`, a sibling of `DraftStore`: one JSON file `<appSupport>/workout-last-finished.json`, atomic save (tmp + rename), `clear()`. **One slot**: a later finish overwrites it.
- **Tolerant load:** `load()` catches **everything** (`catch (_)`, not `on Exception`) — a malformed file (a `TypeError` from a cast) is cleared and treated as absent. It is read at boot before `runApp`; an escaping error would stop the app starting (see §9.2).
- **Who records it:** `finish()` stores the snapshot in a new controller field `FinishedSession? lastFinished`, set just before `_draft = null`. `discard()` never sets it.
- **Who adopts it — only after the commit.** `finish()` runs inside the `db.writeTransaction` callback and notifies **before** COMMIT (`active_session_controller.dart:583-588`), so the manager must not adopt the snapshot from `_onControllerChange`: a failed commit would overwrite the one slot with a snapshot of writes that never happened (after a failed re-finish, the rolled-back session would then resume without the sets ticked since the first resume). Instead adoption goes through `finishWorkout(controller, manager, {transact, draftStore})` (`shell/session_launcher.dart`), which runs `controller.finish` inside the `transact` callback and, only once that callback's transaction has resolved, hands `controller.lastFinished` to `manager.recordFinished`. `_handleFinish` (`session/active_session_screen.dart`) calls it with a `db.writeTransaction` runner as `transact`. `_onControllerChange` stays teardown-only.
- **Who owns it:** `SessionManager` gains `FinishedSession? lastFinished` and a `FinishedSessionStore` (constructor-injectable for tests: `SessionManager({FinishedSessionStore? finishedStore})`).
  - `recordFinished(f)`: adopt in memory, notify, persist. A failed save **clears** the file (errors swallowed) so an older snapshot of the same session cannot survive and be resumed later.
  - `loadLastFinished({DateTime? now})` (boot): drop an unreadable or no-longer-resumable snapshot (§8).
  - `forgetFinished(String sessionId)`: drop it if it matches — used when History deletes that session, and on a tap that finds it expired (§3).
  - **Expiry timer:** whenever a snapshot is adopted or loaded, arm a one-shot `Timer` for the moment it stops being resumable (§3); on fire, `forgetFinished`. Cancelled on forget/replace/dispose. This is what makes the button disappear on its own while History is on screen. The timer runs on the monotonic clock, which does not advance while the device sleeps: on `AppLifecycleState.resumed`, `SessionManager.didChangeAppLifecycleState` calls `_recheckFinished(DateTime.now())`, which re-evaluates `isResumable` against the wall clock — `forgetFinished` if it no longer holds, otherwise re-`_adopt`s the same snapshot to re-arm the timer from the fresh `now`.

## 3. Eligibility

Pure functions in `app/lib/session/resume.dart`:

```dart
bool isResumable(FinishedSession? f, String sessionId, DateTime now)
DateTime resumableUntil(FinishedSession f) // for the expiry timer
```

`isResumable` is true iff `f != null`, `f.sessionId == sessionId`, and either
- `f.sessionDate == isoDate(now)` — the workout belongs to the current calendar day, or
- `now.difference(f.finishedAt) <= const Duration(hours: 1)` — it was finished within the last hour. This covers the midnight case (finished 23:50, noticed 00:20). A negative difference (clock moved back) counts as within the hour.

The day branch uses the **session's date**, not the finish time: a workout re-finished just after midnight keeps its original date (§5), and must not stay resumable for the whole next day under that date. For a fresh finish the two are the same day. The hour branch is measured from the **last** finish, so a quick resume-and-refinish keeps the workout correctable for another hour.

`resumableUntil(f)` = the later of the next local midnight after `sessionDate` and `finishedAt + 1h`.

The rule is evaluated when History builds and **re-checked on tap**. A tap that finds it expired calls `manager.forgetFinished(id)`, which notifies; `HistoryScreen` re-derives the state and the button disappears.

## 4. Resuming: restoring the draft

`resumeFinishedSession(BuildContext context, String sessionId)` in `shell/session_launcher.dart` is a thin navigation wrapper around a context-free, testable core:

```dart
Future<ActiveSessionController?> prepareResume(
  SessionManager manager, String sessionId, {
  required SessionRepository sessionRepo,
  required ExerciseRepository exerciseRepo,
  required DraftStore draftStore,
  DateTime? now,
})
```

1. **Guard, synchronously, before any await:** return null if `manager.hasActive`, if a launch is already in flight (`!manager.tryBeginLaunch()`), or if `!isResumable(manager.lastFinished, sessionId, now)`. The launch flag is cleared in a `finally`. This closes the double-tap race: without it two taps both pass the check, both register a copy of the same `sessionId`, the visible screen drives a detached controller, and finishing the leftover copy later would delete every set logged in the real one.
2. `rows = await sessionRepo.setsForSession(sessionId)`, and the row's `duration_min`.
3. `draft = await restoreFinishedDraft(f, rows, durationMin:, exerciseRepo:, sessionRepo:, now:)`.
4. Re-check `manager.hasActive` (belt-and-braces; the flag already excludes a concurrent resume). Then `await draftStore.save(draft)` — **before** registering, so process death right after Resume boots straight back into the resumed workout.
5. `manager.register(ActiveSessionController.fromDraft(draft, draftStore: draftStore))` — restores notification, mini-bar and Today hero (`register` already calls `showFor` with `startedAt`). Return the controller.

`resumeFinishedSession` then, if a controller came back and `context.mounted`, calls `openActiveSession(context, manager)`.

The same `tryBeginLaunch`/`endLaunch` guard wraps `startSession`'s build-and-register section (§9.7); `register()` gains `assert(_active == null || identical(_active, c))`.

No database write happens at resume.

### The merge rule: the DB is the truth for logged sets

The snapshot can be stale: History can edit, delete or add sets between Finish and Resume, a sync can change rows, and an interrupted snapshot write can leave the previous finish's snapshot for the same session. `restoreFinishedDraft` therefore takes the **logged sets from the DB** and only the things the DB cannot hold from the snapshot (unticked planned sets, order, targets, PR baseline, clock). It works on a deep copy of `f.draft` (`jsonDecode(jsonEncode(f.draft.toJson()))`, the same path as the file) so the manager's snapshot is never mutated by the live workout — it must still be valid after a Discard.

The pure step, `mergeLoggedSets(SessionDraft draft, List<LoggedSet> rows)`, returns the merged draft plus the unmatched rows grouped by exercise. It is keyed on **set id**, never on the snapshot's `done` flag:

- A snapshot set whose id **is** in `rows` → `done: true`, with `weightKg`, `reps`, `rir` from the row (a History edit wins; a set ticked after a newer, lost snapshot is still recognised as logged).
- A snapshot set with `done == true` whose id is **not** in `rows` → dropped (deleted in History).
- A snapshot set with `done == false` whose id is not in `rows` → kept unchanged (planned).
- A row whose id matches **no** snapshot set (added in History) → appended, `done: true`, to the **first** snapshot block with the same `exercise_id` (warm-up/working by `is_warmup`, in `set_number` order); if no block has that exercise it goes to the unmatched groups.
- A snapshot block left with **no sets at all** after the merge is dropped.

The async step then:
- **drops snapshot blocks with no logged rows whose exercise no longer exists locally** (`exerciseRepo.byId` is null) — their planned sets were never stored, and ticking them later would produce set PUTs that fail the server's `exercise_id` FK. (A block with logged rows always has its exercise: `deleteExercise` is refused while logged sets reference it.)
- appends one block per unmatched group, in first-appearance order: `exerciseRepo.byId(id)` (unfiltered; if the exercise was deleted, a placeholder `Exercise` whose name is its id — the fallback History already shows — so the logged rows are never dropped), `resolveSlot(Slot(exerciseId: id, position: blocks.length), exercise)`, and `bestKg`/`lastTop` computed with **`excludeSessionId`**. The block's sets are exactly the logged rows (`done: true`); no planned sets are invented.

Finally the draft becomes: `templateId`/`name`/`focus` from the snapshot, `sessionId: f.sessionId`, `sessionDate: f.sessionDate`, `startedAt: now − max(f.elapsedSeconds, durationMin × 60)` (a stale snapshot cannot roll the clock back), and the merged blocks. The rest timer starts empty (it is cleared at finish and never in the draft).

### Baselines exclude the resumed session

`lastTopSet` and `bestTopSet` gain an optional `String? excludeSessionId`. `lastTopSet` adds `AND s.session_id != ?` to **both** of its SQL branches; `bestTopSet` has no table alias and adds `AND session_id != ?`. Every baseline lookup made while a resumed draft is live passes it: the unmatched-group blocks above, and **`ActiveSessionController.addBlock`**, which passes `excludeSessionId: draft.sessionId` (null for a fresh workout — unchanged behaviour). Without the latter, removing and re-adding an exercise in a resumed workout would take `bestKg` and "Last · today" from the session's own finished rows. `buildFromTemplate` only builds fresh drafts and needs no change.

## 5. Finishing a resumed workout: replace in place

`SessionDraft` gains two nullable fields, `sessionId` and `sessionDate` — null for a fresh workout, set for a resumed one — serialized in `toJson` and read in `fromJson` as `String?` (drafts written by older builds have neither key and stay fresh workouts).

`finish()`:
- `sessionId = d.sessionId ?? uuid.v4()`; `dateIso = d.sessionDate ?? isoDate(DateTime.now())` — a resumed workout keeps its **original date**: its card does not move, and a workout resumed after midnight stays on the day it was done.
- `d.sessionId == null` → `persistSession(executor, write)` as today.
- `d.sessionId != null` → `replaceSession(executor, write)` (new, in `session_writer.dart`), all inside the caller's single `db.writeTransaction`:
  1. `UPDATE sessions SET split_label = ?, duration_min = ? WHERE id = ?`
  2. `INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) SELECT ?, ?, (SELECT id FROM day_templates WHERE id = ?), ?, ? WHERE NOT EXISTS (SELECT 1 FROM sessions WHERE id = ?)` — only if the row has vanished (deleted by a sync from another device during the resumed workout).
  3. `DELETE FROM sets WHERE session_id = ?`
  4. one `INSERT INTO sets …` per done set, as in `persistSession`.
- PR flags: each block's `bestKg` is the pre-workout baseline (§4), so local `is_pr` is right; the server recomputes regardless.
- It records a fresh `FinishedSession` (same id, new `finishedAt`/`elapsedSeconds`/draft), which `_handleFinish` hands to `recordFinished` after the commit (§2).

**The session row is never deleted.** Upstream this is one CRUD transaction: `PATCH` session (`split_label`, `duration_min` only — both in the server's PATCH allowlist, both non-null), then one `DELETE` per old set, then one `PUT` per set. The server handles it unchanged: the PATCH never carries `day_template_id`, so a training day deleted since cannot fail it; set DELETEs and PUTs each register top-set/PR recompute, which runs once after the batch; each set PUT finds its parent, which was never removed. Same-id set DELETE→PUT inside one transaction is the documented re-point pattern (app `AGENTS.md`, `template_absorb.dart`): PowerSync emits both ops, no coalescing. The worst a rejected op can now do is lose that one set (e.g. an exercise deleted on another device) — never the session.

**Why not delete and re-insert the session row too:** a PUT the server rejects *after* a DELETE it accepted destroys the row. That is exactly what a dangling `day_template_id` does (§0): the session DELETE applies, the re-insert fails the FK, every set PUT is skipped as an orphan, and the next sync-down removes the whole, previously synced workout locally.

**Why the guarded INSERT and not only UPDATE:** a local `UPDATE` of a vanished row is a silent no-op, and the set INSERTs would then be orphans the server skips. The `WHERE NOT EXISTS` insert re-creates the row only in that case, with the day resolved against the local table so a deleted day becomes NULL.

## 6. Discarding a resumed workout

Nothing in the DB changes: the session stays as it was at its last finish, the in-progress draft is cleared, and `lastFinished` is kept, so Resume is still offered while the window lasts.

The discard dialog copy switches when `draft.sessionId != null`: title **"Discard changes?"**, message **"The workout stays in History as it was when you finished it."**, confirm `commonDiscard`, cancel `sessionKeepGoing`, still destructive-styled. The choice lives in a small pure helper (title/message from `l` and the draft) so it is testable. The existing no-done-sets shortcut (discard without asking) is unchanged and is equally non-destructive here.

## 7. History

- `HistoryScreen.build` reads `context.watch<SessionManager>()` and derives each card's state with a pure helper in `session/resume.dart`:

  ```dart
  enum SessionResumeState { none, available, inProgress }
  SessionResumeState resumeStateFor({String? activeSessionId, FinishedSession? lastFinished,
      required String sessionId, required DateTime now})
  ```

  `inProgress` when `activeSessionId == sessionId` — checked **first**, because during a resumed workout the kept snapshot also matches; otherwise `available` when `isResumable`; otherwise `none`. `activeSessionId` is `manager.active?.draftOrNull?.sessionId`.
- `SessionCard` takes `resumeState` plus `onResume`, and is **keyed `ValueKey(session.id)`** (§9.3). `_ExerciseBlocks` receives `resumeState` too.
- The expanded body splits into the loading shell (`_ExerciseBlocks`: future + reload) and a stateless `SessionCardBody(blocks, resumeState, callbacks)` that renders the block rows and the footer, **including when `blocks` is empty** (§9.4):
  - `available`: **Resume workout** first — accent, mono 11 w600, 14px `WIcons.resume` (new: `Icons.play_arrow_rounded`), the same centred inline style as Add exercise — then Add exercise, divider, Delete session as today.
  - `inProgress`: only **Resume workout**, which reopens the running workout. Add exercise and Delete session are hidden and block rows are not tappable: the running workout is where it is edited, and a History edit or delete would be overwritten by its next finish.
  - `none`: unchanged.
- Tap on Resume, in this order — decided by the pure `resumeTapAction(state, hasActive:)` / `ResumeTapAction` (`session/resume.dart`), re-derived from `resumeStateFor` at tap time (the card may have been built before the window closed):
  1. `inProgress` → `openActiveSession(context, manager)`.
  2. Not resumable any more → `manager.forgetFinished(id)` (the button disappears).
  3. Another workout is running (`manager.hasActive`) → `showWDialog` titled **"Workout in progress"**, message **"Finish or discard your current workout before resuming another."**, one `commonOk` action.
  4. Otherwise → `resumeFinishedSession(context, session.id)`; a failure (DB or draft-file error) shows a danger-styled SnackBar with `historyResumeFailed` (`{error}` placeholder) instead of failing silently.
- Delete session also calls `manager.forgetFinished(id)`.
- **Card refresh:** `_ExerciseBlocks.didUpdateWidget` reloads whenever `!identical(oldWidget.session, widget.session)`. Every `watchSessionStats` emission follows a commit on `sessions`/`sets` and builds new row objects (`reListenable` does not dedupe), so this catches a re-finish that changed only RIR or warm-ups, which no aggregate reflects. Reloads are **quiet**: `_future` is replaced without the `ValueKey(_refresh)` bump, and the body renders `snap.data` whenever it has data (FutureBuilder keeps the previous data while a new future is pending), showing the spinner only on the very first load — so a stream-driven reload never blanks the card or replays its `Reveal` rows. `_reload()` after the sheet closes uses the same quiet path.
- `groupIntoBlocks` becomes a top-level pure function in `session_repository.dart` (the method stays and delegates), so `_ExerciseBlocks` needs only `setsForSession` from the repository — which makes `SessionCard` mountable in a widget test with a fake repository.

## 8. Boot and lifecycle

- `main.dart`: after `resumeFromDraft()`, `await sessionManager.loadLastFinished()`; it deletes the file when the snapshot is unreadable or no longer resumable against its own id, and otherwise arms the expiry timer.
- A resumed workout's in-progress draft carries `sessionId`/`sessionDate`, so process death mid-resume restores it at boot and its finish still replaces in place.
- **The expiry timer runs on the monotonic clock**, which does not advance while the device sleeps, so it cannot be trusted to fire while backgrounded. `SessionManager.init()` registers it as a `WidgetsBindingObserver`; on `AppLifecycleState.resumed` it re-checks the snapshot against the wall clock (`_recheckFinished`), via `isResumable` — `forgetFinished` if it is no longer resumable, otherwise re-arms the timer from the current time. This is what actually retires a snapshot whose window closed while the app was backgrounded, not the timer itself.
- A snapshot pointing at a session that no longer exists (deleted, or local data discarded on re-login) is inert: no card carries its id, and it expires with its window.

## 9. Existing bugs fixed in passing

1. **Per-exercise rest is lost on every draft round trip.** `BlockState.toJson`/`fromJson` (`active_session_controller.dart:151-228`) omit `Exercise.defaultRestSeconds`, so a boot-resumed block falls back to the global rest default — and so would every resumed workout. Serialize it (`exerciseDefaultRestSeconds`).
2. **A malformed draft file stops the app starting.** `DraftStore.load()` catches only `on Exception`; a cast failure is a `TypeError`, escapes to `main()` before `runApp`. Catch everything, as the new store does.
3. **History cards are matched by position.** `SessionCard` has no key (`history_screen.dart:144-153`), so a row inserted or removed above an expanded card hands its expanded flag and loaded sets to a different session — and the set editor then writes to the wrong session. Key by session id.
4. **An emptied session cannot be deleted from History.** `_ExerciseBlocks` returns `SizedBox.shrink()` when a session has no sets (`:677`), hiding every action including Delete (and now Resume). Render the footer regardless.
5. **An expanded card ignores outside changes to its rows**, and after the set sheet closes its `_reload()` can race the stepper's `deactivate` commit and show a stale number (the known display-only fast-follow). The identity-based quiet reload (§7) covers both: the late commit's own stream emission refreshes the card.
6. **Finishing a workout whose training day was deleted mid-workout loses it on sync** (§0). `persistSession`'s session INSERT binds the day through `(SELECT id FROM day_templates WHERE id = ?)`, so a locally deleted day becomes NULL instead of an FK the server rejects.
7. **A double tap on Start can register two workouts.** `startSession` shares the resume launch guard (§4).

## 10. Deliberately not doing

- **Rebuilding from DB rows when there is no snapshot** (a workout finished on another device, or an earlier one today): it would lose unticked sets, order, targets and the clock, and a "last hour" check has no timestamp to use. Only the last workout finished on this device is resumable.
- **More than one snapshot.** One slot matches the use case: undo the Finish you just did.
- **A confirm on Resume.** Resume writes nothing and Discard reverts it; a dialog only slows the recovery.
- **Server changes.** The replace batch uses only existing handlers. The server's session PUT still rejects a dangling `day_template_id` instead of degrading it to NULL; that stays a recommended follow-up (§13), because the dev stack cannot run the Go tests on this host (no `infra/.env`) and the change needs a homelab redeploy.
- **Finish confirmation / a Resume action on the summary screen.** Not asked for; both are cheap follow-ups.
- **History's exercise order** (`setsForSession` orders by `exercise_id`). Pre-existing, unrelated; the resumed workout takes its order from the snapshot.

## 11. Localization

Six new keys, in all four ARB files (`arb_parity_test` enforces it); `@` metadata in `app_en.arb` only, as for every key. Italian is verified by the user; German and Spanish are best-effort.

| Key | en | it | de | es |
|---|---|---|---|---|
| `historyResumeWorkout` | Resume workout | Riprendi allenamento | Training fortsetzen | Reanudar entrenamiento |
| `historyResumeBlockedTitle` | Workout in progress | Allenamento in corso | Training läuft | Entrenamiento en curso |
| `historyResumeBlockedMessage` | Finish or discard your current workout before resuming another. | Termina o scarta l'allenamento in corso prima di riprenderne un altro. | Beende oder verwirf dein laufendes Training, bevor du ein anderes fortsetzt. | Termina o descarta tu entrenamiento actual antes de reanudar otro. |
| `historyResumeFailed` | Failed to resume workout: {error} | Ripresa allenamento non riuscita: {error} | Training konnte nicht fortgesetzt werden: {error} | No se pudo reanudar el entrenamiento: {error} |
| `sessionDiscardChangesTitle` | Discard changes? | Scartare le modifiche? | Änderungen verwerfen? | ¿Descartar los cambios? |
| `sessionDiscardChangesMessage` | The workout stays in History as it was when you finished it. | L'allenamento resta nella cronologia com'era quando l'hai terminato. | Das Training bleibt im Verlauf so, wie es beim Beenden war. | El entrenamiento queda en el historial tal como estaba al terminarlo. |

`historyResumeWorkout` duplicates `todayResumeWorkout`'s text on purpose: that key means "reopen the minimized workout", and the two may need to diverge in translation.

## 12. Testing

Contracts are pinned below the screen level — mounting `HistoryScreen` over a real DB hangs the test binding (app `AGENTS.md`).

- **Pure:**
  - `isResumable`: same day; 00:20 after a 23:50 finish; 61 minutes after a previous-day finish; re-finished 00:30 on D+1 for a D-dated session, checked at 12:00 on D+1 → false; wrong id; null; clock moved back. `resumableUntil` for both branches.
  - `resumeStateFor`: `none`, `available`, `inProgress`, and both conditions true → `inProgress`. `resumeTapAction`: each `SessionResumeState` maps to its `ResumeTapAction`, including `available` split by `hasActive` (`blockedByActive` vs `resume`).
  - `mergeLoggedSets`: History value edit wins; History delete drops; History add joins its block in `set_number` order; add for an unknown exercise lands in the unmatched groups; unticked sets and block order preserved; emptied block dropped; an unticked snapshot set whose id is in the rows becomes done with the row's values and no duplicate id.
  - JSON: `SessionDraft` with and without `sessionId`/`sessionDate` (legacy JSON → null); `BlockState` round-trips `defaultRestSeconds`; `FinishedSession` round trip and tolerant decode of malformed input. Discard-dialog copy helper.
- **Controller (`FakeExec`):** a fresh finish records `lastFinished` (id equals the returned id, today's date, elapsed, the draft) and its session INSERT binds the day via the subquery; a resumed finish emits the UPDATE, the guarded INSERT, `DELETE FROM sets WHERE session_id = ?`, then the set INSERTs — never `DELETE FROM sessions` — all with the **original** id and date; `discard()` records nothing; `addBlock` on a resumed draft passes `excludeSessionId`.
- **Manager:** `recordFinished` adopts, notifies and persists (fake store); a failed save clears the store; controller teardown alone leaves `lastFinished` unchanged; `loadLastFinished` drops an expired snapshot; `forgetFinished` only drops a matching id; the expiry timer forgets on fire (`fakeAsync`); `tryBeginLaunch` refuses a second launch until `endLaunch`. `finishWorkout` (`test/session/finish_workout_test.dart`): a committed finish hands its snapshot to the manager; a commit that throws after `finish()` ran keeps the previous snapshot (`finish()` itself still completes); without a manager it still returns the session id.
- **Integration, real PowerSync DB** (`test/data/resume_integration_test.dart`, the `*_integration_test.dart` harness):
  - finish → `prepareResume` → change → re-finish leaves exactly one session row with the original id and date and exactly the expected set rows, one top set per exercise, `is_pr` against the pre-workout baseline;
  - the replace transaction's CRUD ops (`getNextCrudTransaction`): a session PATCH without `day_template_id`, then set DELETEs, then set PUTs with the same ids, and no session DELETE;
  - the training day deleted before the re-finish → the session row survives; a vanished session row is re-created by the guarded INSERT with `day_template_id` NULL;
  - History edit / delete / add between finish and resume survive the merge;
  - discard after resume leaves every row identical;
  - two overlapping `prepareResume` calls → exactly one registered controller;
  - `lastTopSet` (both branches) and `bestTopSet` honour `excludeSessionId`.
- **Widget:** `SessionCard` pumped with a fake `SessionRepository` (`setsForSession` and `deleteSession` implemented, both returning a completed future — no DB, so no deadlock): the footer for each of the three states and which callback each action fires; an empty session still shows its footer; a new `session` object triggers a quiet reload (no spinner once data is shown).

## 13. Risks

- **Local same-id DELETE→INSERT of sets in one transaction, and `INSERT … SELECT … WHERE NOT EXISTS` through PowerSync's view triggers.** The first is relied on by `template_absorb.dart`; both are pinned by the integration test, including the CRUD op order.
- **Dangling `day_template_id` on a fresh finish when the day was deleted on *another* device** and has not synced down yet: the local subquery cannot see it, so the server still drops that session (pre-existing). Recommended follow-up: make the server's session PUT/PATCH resolve `day_template_id` through `(SELECT id FROM day_templates WHERE id = …)`, with a Go test, and redeploy. The resume path itself is immune — its PATCH never carries the column.
- **Synced edits during a resumed workout** (from another device) are overwritten by the re-finish — the DB is re-read only at resume. The History UI blocks local edits to the in-progress card.
- **A failed or interrupted snapshot write** can leave the previous finish's snapshot for the same session (a crash between the commit and the rename). The id-keyed merge and the `durationMin` floor make that snapshot safe to resume: every logged set is recognised from the DB.
- **Commit failure of a finish:** the previous snapshot is kept (adoption happens only after the commit); the in-progress draft is already gone, as it is today.
- **Local data cleared while a resumed workout is live** (sign-out, or re-login choosing the account's data): the live draft keeps its old `sessionId`, and its finish re-creates that id through the guarded INSERT, so on the next upload removed sets can survive server-side (same account) or the workout can be rejected (another account). Accepted for now. Follow-up: whenever local data is cleared, detach the live draft (null `sessionId`/`sessionDate`) and forget the snapshot.

## 14. Out of scope

Finish confirmation; summary-screen Resume; multi-snapshot history; resuming workouts finished on another device; History exercise ordering; the server-side `day_template_id` hardening (§13).

## 15. Release

Branch `feat/resume-finished-workout`; TDD per task; whole-branch adversarial review; `--no-ff` merge with `(v0.14.0)` in the subject; `app/pubspec.yaml` bumped to `0.14.0+30` in its own commit; tag `v0.14.0` — pushing and tagging only after the user says so.

Device checks before tagging:
1. Finish by mistake → History → today's card → Resume: ticked and unticked sets, exercise order and targets are back; the clock continues from the finish time, not from zero or the original start.
2. Finish again: one History entry, same day, all sets, correct PR badge, duration covering both parts.
3. Resume → Discard: the History entry is unchanged and Resume is still offered.
4. Resume while another workout is running: the "Workout in progress" dialog.
5. Finish at ~23:50: Resume still offered at 00:20, gone after 00:50 — without leaving History.
6. Kill the app while resumed, relaunch: the workout resumes, and Finish still updates the same entry.
7. Edit a set in History, then Resume: the edited value is what the workout shows.
8. The in-progress card: no edit, add or delete; Resume reopens the workout.
9. The ongoing notification's chronometer continues from the finish time.
10. With sync on: after a re-finish the server holds one session with the new sets.
11. A fast double tap on Resume opens one workout.

## 16. Addendum — live-workout editing (also ships in v0.14.0)

Added on 2026-09-24 as a bounded change (in-chat design, no separate spec): in the live workout you can **swipe a set row left to remove it** (a ticked set asks "Remove set?" first; an unticked one goes straight away; warm-ups and working sets alike), **add a warm-up** with a "+ Warm-up" button beside "Add set" (the i-th warm-up is `(0.5 + 0.18·i)` of the first working weight, rounded to the plate step and capped at it; reps `max(1, 8 − 2i)`), and **move an exercise up/down** with arrows in the expanded card's footer (disabled on the first/last exercise). Controller: `removeSet`, `addWarmupSet`, `moveBlock`. Finish already numbers sets by on-screen order, so moves and removals persist with no writer change; in a resumed workout a removed set that was logged is deleted at re-finish. The footer and "Last" rows now ellipsize instead of overflowing (the "No previous data" row overflowed at 320 dp / 1.3× text before this change).

Device checks before tagging (in addition to §15):
12. Swiping a set row left does not fight the weight/reps steppers, the RIR picker or an open number field.
13. Removing a ticked set asks first; an unticked one goes at once; the set numbers and the "n/m" badge update.
14. "+ Warm-up" produces a sensible ramp for a barbell lift and for a machine/dumbbell exercise, in kg and in lb.
15. Moving an exercise keeps its expanded state and typed values; after Finish, History and the summary show the new order (the summary's order comes from `exercise_id` — pre-existing — so only the resumed-workout order is guaranteed).
