# Back-nav + FAB/card fixes + full motion pass — design

**Date:** 2026-06-02
**Status:** Approved (design)
**Scope:** Four on-device findings from v0.2.0: (1) Android back exits the app from any tab — make it navigate home first (and close the Plan in-tab editor first — closes that deferred item); (2) the center FAB looks small — enlarge; (3) remove the cut-off decorative dumbbell on the Today split card; (4) the app feels flat — a **full motion pass** (micro layer + hero moments) in the app's sharp/minimal language: fast, snappy, zero bounce.

## 1. Back navigation
- `PopScope(canPop: false)` on the AppShell scaffold; `onPopInvokedWithResult` runs a 3-level priority:
  1. **Active tab intercepts:** Plan's in-tab editor open → close it (PlanScreen exposes `bool handleBack()` — closes `_editor`/returns true — via a `GlobalKey<PlanScreenState>` held by the shell). Only Plan needs interception today.
  2. **Not on Today (index != 0)** → switch to Today.
  3. **On Today** → exit (`SystemNavigator.pop()`).
- The decision is a pure, testable function: `BackAction decideBack({required bool tabHandled, required int tabIndex})` → `none | goHome | exit` (tabHandled means a tab consumed it).
- Root overlays (active session, profile) are normal pushed routes — back already pops them; the PopScope only matters at the shell level.

## 2. FAB size
`w_tab_bar.dart` `_FabButton`: 52×52 → **64×64**, icon 23 → 28. Keep the bottom-only glow (`offset (0,8)`, `spreadRadius -2`) and the `Clip.none` straddle; visually verify the overlap.

## 3. Split-card dumbbell
Delete the decorative `Positioned(... Icon(WIcons.dumbbell ...))` block in `split_card.dart` (~:113-126). No replacement.

## 4. Motion pass
**Motion system** — `lib/theme/motion.dart`: `Motion.fast = 120ms`, `Motion.base = 200ms`, `Motion.slow = 300ms`; `Motion.curve = Curves.easeOutCubic` (single source; nothing bouncy). All animations are transform/opacity-only (60fps-cheap). Haptics via Flutter's built-in `HapticFeedback` — **no new dependencies**.

### Micro layer
- **Tab switch:** soft cut — on index change, the IndexedStack content fades in (Motion.fast). IndexedStack is kept (state preservation); the fade re-triggers per switch.
- **`PressableScale`** (`lib/widgets/pressable.dart`): reusable wrapper — scale to 0.97 on tap-down, back on release (Motion.fast). Applied to: Today cards (split card, stat tiles where tappable), History `SessionCard`, Plan day/exercise rows, `_SegBtn`, `PrimaryBtn`, the FAB.
- **Plan editor:** entering/leaving the in-tab editor slides+fades (220ms) instead of snapping (`AnimatedSwitcher` with a slide-up transition around `_buildBody`'s editor branch).
- **Today entrance:** one-shot staggered fade+rise (~12px) of Today's top-level children on first build; ~30ms stagger, Motion.base per item; never re-runs on rebuilds.
- **Steppers (`WStepper`):** the value text animates on change — slides up when incrementing, down when decrementing (AnimatedSwitcher keyed on value, Motion.fast) + `HapticFeedback.selectionClick()` per tap.

### Hero layer
- **FAB → active session:** custom `PageRouteBuilder` — slide-up + fade, 250ms, easeOutCubic (replaces the default route).
- **Set done toggle:** the check control "pops" (quick 1.0→1.15→1.0 scale flash, Motion.fast) + `HapticFeedback.mediumImpact()`.
- **PR hit mid-session:** when a logged set first exceeds the block's `bestKg`, the `PRBadge` pulses (scale + accent glow flash, ~400ms one-shot) + `HapticFeedback.heavyImpact()`.
- **Session finish → summary:** the summary's stat blocks stagger-reveal (fade+rise, ~40ms stagger); the PR count **ticks up from 0** (IntTween, Motion.slow); one accent flash on the header as the "success" beat.

## Error handling / constraints
- Animations must not change layout semantics or break existing widget-test finders (wrappers preserve child trees; tests use `pumpAndSettle`/`pump(duration)` where needed).
- Entrance animations are one-shot (no re-trigger on stream rebuilds) — guard with a `bool _played` or equivalent.
- Reduced-motion: respect `MediaQuery.disableAnimations` — when set, durations collapse to zero (a `Motion.of(context)` helper or duration guard).

## Testing
- Pure: `decideBack` priority table.
- Widget: `PressableScale` scales on tap-down; `WStepper` still reports changes (existing tests green); existing suite (133) stays green.
- On-device (user): back behavior from each tab + inside the Plan editor; FAB size; no dumbbell; the feel of the motion pass.

## Out of scope
Lottie/rive or custom shaders; animated app icon; per-screen redesigns; remaining polish items (delete-exercise guard, Spec B nits).
