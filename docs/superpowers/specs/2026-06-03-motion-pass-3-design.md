# Motion pass 3 — beyond-spec gaps

**Date:** 2026-06-03
**Status:** Approved (design)
**Scope:** The five gaps identified beyond the design-agents' list during motion pass 2: list-mutation animations, dialog restyle, onboarding entrance, sync feedback, unit-toggle cross-fade. Same motion language as passes 1–2: `Motion` constants (fast/base/slow, easeOutCubic, zero bounce), transform/opacity-only, reduced-motion honored everywhere (`Motion.of` / skip loops), no new dependencies. Ships as v0.5.0.

## 1. List mutations (lightweight implicit — chosen over AnimatedList)

No list refactor. Session sets / plan slots / history sets live in shrink-wrapped `Column`s inside cards; converting to `AnimatedList` is invasive and risks the suite for exit-animation polish. Instead:

- **New `Reveal` widget** in `theme/motion.dart`: one-shot fade + 12px rise on mount, `Motion.base`, reduced-motion aware — `StaggeredEntrance` minus the index/delay. Stays one-shot across rebuilds (State persists at a stable tree position; rows must keep stable keys).
- **Applied to newly added rows only** (rows present on first build of a screen should NOT replay — guard by only wrapping rows, relying on `Reveal` being mounted once per row; the screen-level entrance is pass-1 territory):
  - Active session: new set row on "Add set" and new exercise block on add (`session/exercise_block.dart`, `session/active_session_screen.dart`).
  - Plan day editor: newly added slot row (`ui/day_editor.dart`).
  - History edit: newly added set row / exercise block (`ui/history_screen.dart`).
- **`AnimatedSize`** (Motion.base, topCenter) around the mutating containers so add/remove height changes ease instead of snapping. Removal content disappears instantly but the layout collapse is smooth — accepted trade-off of the lightweight approach.

Note: where every row in a list gets `Reveal`, first-build rows animate once on screen entry — acceptable (matches the existing entrance language); what must NOT happen is replay on stream rebuilds.

## 2. Dialog restyle

One shared helper replaces all 8 `AlertDialog` call sites (visual consistency is the point as much as motion):

- **New `widgets/w_dialog.dart`** (all 8 call sites are text-only — verified; no widget-content slot):
  - Generic core: `Future<T?> showWDialog<T>(BuildContext context, {required String title, required String message, required List<WDialogAction<T>> actions})` where `WDialogAction<T>` = `(label, value, {bool destructive = false})`. Built on `showGeneralDialog`.
  - Convenience wrapper for the common case: `Future<bool?> showWConfirm(BuildContext context, {required String title, required String message, String cancelLabel = 'Cancel', required String confirmLabel, bool destructive = false})` → two actions returning false/true.
  - Surface: tokens-styled container (surface2, 16px radius, same border treatment as cards), title in the app's display style (size 18), message in body style (size 14, dim) — matching the hand-styled dialog in `active_session_screen.dart:134`.
  - Entrance: fade + scale 0.96→1.0, `Motion.base`, `Motion.curve` (via `transitionBuilder`); barrier fades; reduced motion → instant (`Motion.of` on `transitionDuration`).
  - Destructive actions render in the danger color, others accent/quiet. Dismiss (barrier tap) returns `null` — same as today.
- **Call sites:** 7 are bool confirms → `showWConfirm` (`session/active_session_screen.dart` ×2 [Discard workout, Remove exercise], `ui/history_screen.dart` ×2 [Delete session, Delete set], `ui/profile_screen.dart` ×2 [Switch server, Sign out], `ui/day_editor.dart` ×1 [Delete training day]); 1 is the 3-way Spec-B attach prompt (`profile_screen.dart:343`, returns `_ReconcileChoice`) → generic `showWDialog<_ReconcileChoice>`. Each keeps its exact semantics (return values, what confirm does) — only presentation changes.

## 3. Onboarding entrance

`StaggeredEntrance` (existing primitive) on `ui/onboarding_screen.dart`'s top-level children — logo/title, copy, the two choice cards — ~40ms stagger. The `_busy` double-tap guard is untouched.

## 4. Sync feedback (Profile only — user's pick over global dot / snackbars)

A status row in the existing Sync & Backend section of `ui/profile_screen.dart`, rendered only when sync is enabled:

- **Driven by** a `StreamBuilder` on the PowerSync database's `statusStream`.
- **State mapping is a pure function** (testable): status → `(label, color, pulsing)`:
  - uploading/downloading → "Syncing…", accent, pulsing dot.
  - connected idle → "Synced · <relative last-synced time>" (from `lastSyncedAt`; "just now"/"Xm ago"/"Xh ago"/date), accent, static dot.
  - disconnected → "Offline", faint, static dot.
  - `uploadError`/`downloadError` present → "Sync error", danger/warn color, static dot.
- **Dot pulse**: small repeating opacity/scale controller, started only while syncing, skipped under reduced motion (same lifecycle pattern as the rest-timer pulse: stop + reset on exit, dispose).

## 5. Unit-toggle cross-fade

Tiny `UnitSwap` wrapper (in `theme/motion.dart` or `widgets/`): `AnimatedSwitcher` at `Motion.fast` fade with the child keyed on the unit, so kg↔lb re-renders cross-fade instead of snapping. Applied at high-visibility weight values only (YAGNI — not every weight text in the app):

- Profile quick stats (`ui/profile_screen.dart`).
- Progress `BigStat`s (`ui/progress_screen.dart` / `progress_widgets.dart`).
- Bodyweight view Current/30-day/Lowest (`ui/bodyweight_view.dart`).
- Today bodyweight tile (`ui/today_screen.dart`).

## Constraints

- One-shot animations must not re-trigger on stream rebuilds (stable keys on revealed rows).
- All 140 existing tests stay green; dialog swaps must preserve each call site's confirm/cancel semantics exactly.
- No new dependencies; reduced motion honored in every item (including the sync pulse and dialog entrance).

## Testing

- Unit/widget: `Reveal` one-shot; `showWDialog` returns true/false correctly and renders title/labels; sync status mapping pure function (all four states + relative-time formatting); `UnitSwap` shows the final value text.
- On-device (user): row add feel in session/plan/history, dialog look + feel across all 8 sites, onboarding entrance (fresh install or pm clear), sync row states (toggle airplane mode), kg↔lb cross-fade.

## Out of scope

Exit animations for removed rows (would need AnimatedList); global sync indicator or sync snackbars; restyling non-confirm dialogs/sheets (sheets are native and fine); animating every weight text on unit change.
