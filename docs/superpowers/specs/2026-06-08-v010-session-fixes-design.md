# v0.10.0 — session/notification fixes + in-progress UX

**Date:** 2026-06-08
**Status:** Approved (design)
**Scope:** Eight items from on-device use of v0.9.0: a data fix (absorb duplication), an in-progress-workout UX move (top-right indicator + Today resume hero), a notification rest overhaul (OS-scheduled revert + shade-actionable +30s), configurable rest duration (global + per-exercise), bottom-padding fix, and the Today target-bar normalization bug. Ships as v0.10.0.

All root causes below were confirmed by a parallel investigation with file:line evidence (see this increment's plan for the evidence trail).

---

## 1. Absorb duplication (data fix)

**Root cause:** onboarding seeds ~24 owned exercises with random `uuid.v4` ids (`catalog_seed.dart` `seedStarterCatalog`, `is_template=0`); the server's identical 24 template exercises sync down (`is_template=1`); the v0.9.0 absorb (`template_absorb.dart`) creates owned copies with *deterministic* `uuid.v5` ids that don't match the onboarding ids, so its id-only `existingIds` check misses and it inserts a second copy of every exercise. The name-twin filter (`dedupeCatalog`) that masked this was deleted in the same release.

**Fix:** add name-based dedup to `absorbOps`. For each template exercise, if an owned exercise (`is_template=0`) with the same `lower(name)` AND same `muscle_group` already exists, map `exCopyIds[templateId] = existingOwnedId` and emit NO insert — references (`sets.exercise_id`, `day_template_items.exercise_id`) re-point to the existing owned row via the existing `exCopyIds` plumbing. Apply the same dedup to day templates keyed on `lower(name)` (days have no muscle group; onboarding seeds no days, so this only guards a user-created day colliding with a future template). Tombstone the template id regardless (so a name-matched template is never retried).

**Signature change:** `absorbOps` gains `required Map<String,String> ownedExerciseByKey` (key = `'<lower(name)>|<muscle_group>'` → owned id) and `required Map<String,String> ownedDayByName` (`lower(name)` → owned id). `absorbTemplates` builds these from `SELECT id, name, muscle_group FROM exercises WHERE is_template=0` and `SELECT id, name FROM day_templates WHERE is_template=0`.

**Retroactive:** none. The current user already manually removed duplicates and their templates are already tombstoned, so absorb won't touch them again — this fix only prevents NEW duplication (fresh installs, future server templates). No merge pass for already-duplicated-uncleaned states (out of scope; the affected user is the dev and is clean).

**Match key decision:** name + muscle_group (not name-only) — avoids merging a user's custom exercise that happens to share a name with a template but targets a different muscle. The 24 starter exercises match the templates on both, so the real case still dedups.

---

## 2 & 3. In-progress workout surfaces

**Current state:** `session_mini_bar.dart` is a full-width pill docked bottom (`app_shell.dart`, `bottom: 105`), shown when `hasActive && !screenOpen`. `today_screen.dart` does not watch `SessionManager`.

**#2 — Top-right indicator (replaces the bottom mini-bar).** Reparent the in-progress indicator to a **compact top-right pill** in the AppShell Stack: `Positioned(top: MediaQuery.paddingOf(context).top + 8, right: 16, ...)`. Compact (auto-width): a small dumbbell glyph + live elapsed `M:SS`, swapping to an accent rest countdown while `restStart != null`; tap → `openActiveSession`. Its own 1s ticker. The old bottom mini-bar is removed entirely.
**Visibility:** `hasActive && !screenOpen && tabIndex != 0` — hidden on Today (index 0), where the resume hero covers it. The shell already knows `_index`; pass it into the indicator's visibility.

**#3 — Today resume hero (replaces the pager when active).** `today_screen.dart` watches `SessionManager`. When `hasActive`, the hero region renders a single **resume card** instead of the `SplitCard` pager (and NO dots): eyebrow "ACTIVE NOW", the active day's name/focus (resolve `draft.templateId` against the loaded day list; fall back to `draft.name` / "Custom" with `draft.blocks.length` exercises), a live elapsed stat (own 1s ticker, swaps to rest countdown while resting), and a "Resume workout" button → `openActiveSession`. When not active, the existing pager renders unchanged.

Open implementation notes (not user decisions): the resume card is a small StatefulWidget for its ticker; reuse the elapsed/rest formatting helper from the indicator (extract a shared `fmtClock(Duration)` into `util/`). Discard mid-view → `SessionManager.clear()` flips `hasActive` false → Today rebuilds to the pager (guarded by `hasActive`).

---

## 4 & 5. Notification rest overhaul

**Root cause (#5):** the rest→elapsed revert is driven by `SessionManager._armRestExpiry`, a Dart `Timer`. Dart timers are suspended when the app is backgrounded, so the notification's countdown chronometer (`chronometerCountDown`, `when = restEnd`) is never re-issued in elapsed mode and Android keeps counting into negatives.

**Architecture (OS-scheduled revert + shade-actionable +30s):**

- **Persisted rest state.** On rest start, write a compact blob to SharedPreferences: `{sessionName, startedAt(iso), restStart(iso), restTotal(int)}`. This is the source of truth a background isolate / reconciliation can read without the live controller.
- **Show + schedule on rest start.** Show the countdown notification now (with the +30s action), AND `zonedSchedule` a pre-baked **elapsed-mode** notification at `restEnd` (same notification id) — Android posts it at the alarm time even when backgrounded, replacing the countdown → exact revert at 0, no negatives. `androidScheduleMode: exactAllowWhileIdle`.
- **+30s action chip.** `AndroidNotificationAction(id: 'add30', title: '+30s')` on the rest notification. Tap handling:
  - Foreground (`onDidReceiveNotificationResponse`, `actionId == 'add30'`): `controller.addRestTime(30)` → re-show countdown with new `restEnd`, cancel + reschedule the revert alarm, rewrite the prefs blob.
  - Background/killed (`onDidReceiveBackgroundNotificationResponse`, top-level `@pragma('vm:entry-point')`): a fresh isolate — re-init the plugin, read the prefs blob, add 30 to `restTotal`, rewrite the blob, cancel + reschedule the revert alarm, re-post the countdown notification with the new `restEnd`. Does NOT touch the controller (not in this isolate).
- **Foreground reconciliation.** An `AppLifecycleState.resumed` observer compares the prefs blob's `restStart/restTotal` to the controller's; if they differ (a background +30s happened), update the controller so the in-app rest card matches the shade.
- **Stop/finish/discard.** Manual stopRest / set-done-ends-rest / finish / discard: cancel the scheduled revert alarm, clear the prefs blob, and either show elapsed (workout continues) or cancel the notification (workout ended). The existing `_armRestExpiry` Dart timer is removed (the alarm replaces it; the in-app rest card already self-updates via the screen ticker when open).

**Android setup:** add `USE_EXACT_ALARM` (auto-granted for alarm/timer apps — no runtime prompt) and the plugin's scheduled-notification manifest receivers (`ScheduledNotificationReceiver`; include `ScheduledNotificationBootReceiver` + `RECEIVE_BOOT_COMPLETED` only if the resolved plugin requires them for `zonedSchedule` — verify against the package). `flutter_local_notifications` `zonedSchedule` needs `timezone` initialization (`tz.initializeTimeZones()` + local location) — add it to `WorkoutNotification.init`.

**Pure, testable core:** keep `notificationPayloadFor` pure (already is) and add a pure `restRevertAt(restStart, restTotal) → DateTime` and a pure reschedule-decision helper so the alarm math is unit-tested. The plugin calls (show/zonedSchedule/cancel) stay thin.

**Honest limitations (documented):** rendering/alarm behavior varies by OEM and CI cannot test it — heavy on-device verification. Background +30s depends on the prefs write flushing before process death (acceptable; the alarm + countdown remain correct even if a single +30s is lost).

---

## 6. Configurable rest duration (global + per-exercise)

**Global defaults (client-only):** `SettingsService` gains `restCompoundSeconds` (default 180) and `restIsolationSeconds` (default 90) with getters/setters persisted to SharedPreferences (`settings.rest_compound_seconds` / `settings.rest_isolation_seconds`), loaded in `load()`. A "Rest" group in `profile_screen.dart` with two `WStepper` rows (step 15, range 30–600, format `'<v>s'` or `m:ss`).

**Per-exercise override (server migration):**
- Migration: `ALTER TABLE exercises ADD COLUMN default_rest_seconds INTEGER` (nullable; null = use global).
- `schema.dart`: `Column.integer('default_rest_seconds')`.
- `Exercise` model + `ExerciseDraft` + `fromRow` + the exercise-editor: a "Rest (optional)" field (a WStepper with an empty/"default" state at 0/null).
- `sync_upload.go` `applyExercise`: add `default_rest_seconds` to the PUT INSERT column list **and the PATCH allowlist** (omitting it from PATCH silently drops edits — the documented trap).
- `template_absorb.dart` exercise INSERT column list: add `default_rest_seconds` so absorbed copies keep it.
- `catalog_seed.dart`: leave null (fall back to global) — no need to seed.

**Resolution at rest start** (`active_session_screen.dart`, replacing `controller.startRest(b.exercise.compound ? 180 : 90)`):
`exercise.defaultRestSeconds ?? (exercise.compound ? settings.restCompoundSeconds : settings.restIsolationSeconds)`.

**Out of scope:** live base-rest editing on the rest card and a −30s chip (the +30s extend already exists). Changing a global default mid-session affects only the next set's rest (in-flight `restTotal` is immutable) — acceptable.

---

## 7. Bottom padding behind the FAB

Add `const double kBottomNavInset = 112;` (FAB reach ~99px + comfortable gap) to `theme/tokens.dart`. Replace the bottom value in every scrollable's padding with it: `today_screen`, `progress_screen`, `history_screen`, `split_tab`, `exercise_library_tab`, `targets_tab`, `day_editor`, `exercise_editor` (the Plan editors render in-tab under the FAB, so they need it too). Keep each page's existing top inset.

---

## 8. Today target bars

**Root cause:** `volume_bars.dart` computes a global `maxVal = max(all sets, all targets)` and divides every bar by it, so 100% = the highest-volume muscle, not each muscle's own target.

**Fix:** normalize per-row. `fillFraction = (row.sets / row.target).clamp(0, 1)` (guard `target <= 0` → fraction 0, or hide the bar); the target tick sits at a constant 100% (right edge). Over-target clamps to a full bar (no overflow indicator this pass). Unit is already correct (weekly working-set count vs `target_sets`) — verify the count excludes warm-ups; if it doesn't, fix the query to count non-warm-up sets.

---

## Testing

- **Pure/unit:** absorb name-dedup (re-points to existing owned, emits no insert, tombstones; days too); `restRevertAt` + reschedule decision; `notificationPayloadFor` (existing); target-bar fraction math (per-target, clamp, zero-target guard); settings persistence (rest defaults); Exercise model round-trip with `default_rest_seconds`.
- **Server:** `applyExercise` PUT+PATCH persist `default_rest_seconds` (the allowlist trap).
- **Widget:** top-right indicator renders + ticks + tap; Today resume hero replaces pager (no dots) when active and reverts on clear; exercise-editor rest field.
- **On-device (user, the real gate for #4/#5):** rest notification counts down, flips to workout at 0 with the app backgrounded/screen-off (no negatives); +30s from the shade with the app killed extends and reschedules; per-exercise + global rest applied; top-right pill on non-Today tabs, resume hero on Today; delete buttons clear the FAB; target bars read per-target; fresh-install (or pm clear) does NOT duplicate exercises.

## Out of scope

Retroactive duplicate-merge pass; foreground service; live base-rest editing / −30s; target-bar over-100% overflow visual; reps/RIR notification controls.
