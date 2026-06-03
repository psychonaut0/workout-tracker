# Background workout + ongoing notification + accordion fix

**Date:** 2026-06-03
**Status:** Approved (design)
**Scope:** (1) App-scoped active-session ownership so a workout keeps running while navigating the app (minimize + mini-bar + resume, incl. resume-on-launch from the persisted draft); (2) a silent ongoing Android notification with chronometer elapsed / rest countdown (`flutter_local_notifications` — new dep); (3) fix the exercise-block accordion losing its collapsed state when scrolled off-screen. Foreground service explicitly OUT (user's pick: notification dies with the process; resume-on-launch covers it).

## 1. App-scoped session ownership

### `SessionManager` (new, `app/lib/session/session_manager.dart`)
ChangeNotifier provided in `main.dart`'s MultiProvider:
- `ActiveSessionController? get active`
- `void register(ActiveSessionController c)` — set + notify.
- `void clear()` — null + notify (called on finish and discard).
- `bool get hasActive`
- `Future<bool> resumeFromDraft()` — boot path: `DraftStore().load()`; if a draft exists, build a controller around it (`ActiveSessionController.fromDraft(SessionDraft)` — new constructor/factory that adopts the deserialized draft as-is) and `register` it; returns whether resumed. Called once from `main()`/app boot after the DB opens. Corrupt drafts already self-clear in `DraftStore.load()`.

### Controller changes (`active_session_controller.dart`)
- New `fromDraft` path (adopt an existing `SessionDraft` without rebuilding from a template).
- **Rest timer moves in from the screen State:** fields `DateTime? restStart`, `int restTotal` + `void startRest(int seconds)`, `void addRestTime(int seconds)` (the +30s), `void stopRest()` (notifyListeners on each). `_ActiveSessionScreenState` drops `_restActive/_restStart/_restTotal` and reads the controller; its 1s ticker and haptic guards stay screen-local (haptics only matter with the screen open).
- **Draft save cadence:** verify the draft is saved on every mutation (markChanged/addSet/toggleDone/...). If saving is currently only at finish, add a debounced `DraftStore().save(draft)` on `notifyListeners`-worthy mutations (a `_scheduleSave()` helper, ~1s debounce) — resume-on-launch is only as good as the last save. `startedAt` already serializes; rest state need NOT survive process death (a stale rest countdown after relaunch is useless) — do not serialize it.

### Launch/minimize/resume flow (`session_launcher.dart`, `app_shell.dart`, `active_session_screen.dart`)
- `startSession`: if `manager.hasActive` → just (re)open the session route for the existing controller (no new session); else create + populate controller, `manager.register(c)`, push the route. The route's provider becomes `.value(manager.active!)` — the route no longer owns the controller's lifetime.
- Session screen header gains a **minimize button** (chevron-down, left side where appropriate) → `Navigator.pop()` — nothing else. The existing X/discard flow keeps its semantics but now also calls `manager.clear()` after `controller.discard()`. Finish: after the summary `pushReplacement`, call `manager.clear()`.
- **Android back on the session route = minimize** (plain pop — which is what back already does; the change is that popping no longer orphans the session because the manager owns it). No PopScope needed on the session route.
- **FAB while active** → resume (open the route), not start-new. Today hero Start while active → also resume (simplest consistent rule: any "start" entry point resumes when a session is active).

### Mini-bar (`app/lib/shell/session_mini_bar.dart`, new)
Rendered by AppShell (watching `SessionManager`) when `hasActive` AND the session route is not on top (track with a simple `manager.screenOpen` bool set by the session screen's initState/dispose — no navigator observers needed). Docked directly above the `WTabBar` in the existing Stack:
- Left: session name (`draft.name`), mono small.
- Right: ticking elapsed `MM:SS` (its own 1s `Timer.periodic` in the mini-bar's State); while `restStart != null` → swaps to accent `Rest M:SS` countdown.
- Tap anywhere → reopen the session route (same `.value` provider push as startSession's resume path).
- Style: tokens surface2 pill, border line, PressableScale, Reveal on appear; reduced-motion respected via the existing primitives.

## 2. Ongoing notification

### Package
`flutter_local_notifications` (latest compatible). Android-only behavior; guard all calls with `Platform.isAndroid` (Linux dev build: plugin has a Linux implementation but we simply skip — sessions on desktop don't need it).

### `WorkoutNotification` (new, `app/lib/session/workout_notification.dart`)
Thin wrapper around the plugin + a PURE payload builder (testable):
```dart
// pure — no plugin types:
({String title, String body, bool countdown, DateTime when}) notificationPayloadFor({
  required String sessionName,
  required DateTime startedAt,
  DateTime? restStart,
  int restTotal = 0,
  required DateTime now,
})
```
- No rest: title `sessionName`, body `'Workout in progress'`, `countdown: false`, `when: startedAt` → shown with `usesChronometer: true` (Android ticks elapsed natively — zero per-second updates from Dart).
- Resting (restStart != null and remaining > 0): title `sessionName`, body `'Rest'`, `countdown: true`, `when: restStart + restTotal` → `usesChronometer: true, chronometerCountDown: true`.
- Rest expired (remaining <= 0): same as no-rest.

Wrapper API: `init()` (plugin init + channel: id `workout_session`, name "Workout session", `Importance.low`, silent, no badge), `requestPermission()` (Android 13+ `requestNotificationsPermission()`; result ignored — feature degrades to nothing if denied), `show(payload)` (notification id constant 1, `ongoing: true, autoCancel: false, onlyAlertOnce: true, showWhen: true`), `cancel()`.

### Trigger points (all driven by `SessionManager`/controller listeners — a small glue listener in `SessionManager` itself: on register → show; on rest start/+30s/stop (controller notifies) → re-show with new payload; on clear → cancel)
- `register()` → `requestPermission()` (first time) + show elapsed mode.
- Controller rest transitions → re-show (re-issuing with `onlyAlertOnce` updates in place, still silent).
- `clear()` → cancel. App cold start without resume → nothing.
- Notification **tap** → `onDidReceiveNotificationResponse` → bring app forward (automatic) + open the session route if not already open (a callback wired from main.dart that uses the root navigator key — add a `GlobalKey<NavigatorState>` to `MaterialApp` if one doesn't exist).

### Manifest
Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` to `AndroidManifest.xml`. No service declarations (no foreground service). flutter_local_notifications needs no receiver config for plain ongoing notifications (verify against the package README for the resolved version; add only what it requires for `show()` — scheduled-notification receivers are NOT needed).

## 3. Accordion fix (collapsed state lost on scroll)

Root cause: `ListView` sliver children disposed past the cache extent; `_ExerciseBlockState._expanded` (local, default true) resets on remount. Fix both layers:
- **Hoist:** `BlockState` gains a runtime `bool collapsed` (default false, NOT serialized in toJson/fromJson — re-expansion after relaunch is fine). `ExerciseBlock` reads `widget.block.collapsed`; toggle calls `controller.toggleCollapsed(block)` (sets + notifyListeners). `_ExerciseBlockState._expanded` is deleted.
- **Keep-alive:** `_ExerciseBlockState` mixes in `AutomaticKeepAliveClientMixin` (`wantKeepAlive => true`, `super.build(context)` first line of build) so off-screen blocks keep their element subtree — this also stops the block's `Reveal` entrance replaying on scroll-back.

## Constraints
- All 168 existing tests stay green; the rest-timer behavior (smooth ring, final-5s, haptics, +30s re-arm) must be visually unchanged — only the state's home moves.
- Reduced motion honored in the mini-bar (existing primitives).
- No foreground service, no wakelock.
- The notification channel is silent (no sound/vibration/heads-up) — it's a status surface, not an alert.

## Testing
- `SessionManager`: register/clear/hasActive notify; `resumeFromDraft` with a seeded draft file (or injected DraftStore seam) restores name/startedAt/blocks; no draft → false.
- Controller: `startRest/addRestTime/stopRest` transitions; `fromDraft` adopts the draft; collapse toggle.
- `notificationPayloadFor`: the three modes (elapsed / resting / rest-expired) with exact `when` math.
- Mini-bar widget test: renders name, swaps to rest mode, tap fires callback.
- Accordion: widget test — toggle collapsed, scroll the block out of a small viewport and back (or simply rebuild the list), assert it stays collapsed.
- On-device (user): minimize → browse tabs → mini-bar ticks → reopen intact; notification appears/updates on rest/clears on finish; tap notification reopens; kill app mid-workout → relaunch → mini-bar back with correct elapsed; accordion stays closed.

## Out of scope
Foreground service / battery-optimization UX; notification action buttons (pause/finish in the shade); pause-workout semantics; iOS parity; home-screen widget.
