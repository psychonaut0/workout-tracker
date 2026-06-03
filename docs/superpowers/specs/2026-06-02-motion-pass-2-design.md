# Motion pass 2 — completing the design-agents' spec

**Date:** 2026-06-02
**Status:** Approved (design — the user's design-agents' list is the source; this spec is the delta vs what v0.3.0 shipped)
**Scope:** Implement the items from the design spec that are NOT yet in the code. Same motion language as pass 1: `Motion` constants (fast/base/slow, easeOutCubic, zero bounce), transform/opacity-only, `HapticFeedback` built-ins, reduced-motion honored everywhere, no new dependencies.

## Delta to implement

### 1. Set-row done reveal + PR shimmer
- **Done-state reveal:** the not-done row (steppers) ↔ done row (static value + badges) currently swaps with a hard rebuild. Animate it: `AnimatedSwitcher`/`AnimatedSize` cross-fade + slight rise (Motion.fast/base) keyed on `done`, in `set_row.dart`. The existing check `_Pop` and haptics stay.
- **PR badge light-sweep shimmer:** on top of the existing pulse, a one-shot diagonal light sweep across the badge (a moving gradient via `ShaderMask`/`AnimatedBuilder`, ~600ms, once on mount). `pr_badge.dart`.

### 2. Rest timer
`rest_timer.dart` (read its real structure first):
- **Smooth ring sweep:** the ring progress animates continuously over the countdown (an `AnimationController` with the full duration, or a per-tick `TweenAnimationBuilder`) instead of per-second jumps.
- **Final 5 seconds:** the timer pulses (subtle scale ~1.04 loop) and its ring/label shift to the accent color.
- **Haptics:** `HapticFeedback.selectionClick()` tick at 0:03; a buzz at zero (`HapticFeedback.vibrate()`).

### 3. Stat count-ups
A tiny reusable `CountUp` widget (in `theme/motion.dart`): `TweenAnimationBuilder<int>`-based, `Motion.slow`, formats via a builder; animates 0→N on first data and old→new on later changes (TweenAnimationBuilder's natural behavior). Apply to:
- Today: the **Sets / wk** and **PRs / wk** tile values (not Bodyweight — it's a decimal weight + sparkline).
- History: the 4-week summary stats (read `history_screen.dart` for the actual summary numbers).
- Session summary: the remaining numeric stat tiles (sets, volume/tonnage, duration — PR count already ticks).

### 4. Charts draw themselves in
One-shot on mount, reduced-motion aware (progress jumps to 1):
- `line_chart.dart` (progression line): stroke-on via `PathMetric.extractPath(0, length * t)` driven by a mount `AnimationController` (Motion.slow ~400-500ms).
- `sparkline.dart`: same stroke-on treatment (shorter, Motion.base).
- `volume_bars.dart`: bars grow from the left (`width * t`), slight per-bar stagger (~20ms).
Painters gain a `progress` (0..1) param; a small stateful wrapper drives it.

### 5. Overlay polish
- **Profile overlay:** apply the same slide-up + fade `PageRouteBuilder` (250ms) used for the session push (`app_shell.dart` profile push).
- **History card expand:** wrap the expanded section in `AnimatedSize` (Motion.base) so expand/collapse is smooth (`history_screen.dart`).
- **Picker sheets:** verify the modal bottom sheets already get the native rise + backdrop fade (expected: yes → no change; note the finding).

## Constraints
- All one-shot animations must not re-trigger on stream rebuilds.
- Chart painters must keep their existing rendering when `progress == 1` (golden behavior unchanged at rest).
- Existing 138 tests stay green; count-up/chart changes must not break existing widget tests (value text now appears via CountUp — keep the final formatted text identical).

## Testing
- Unit/widget: `CountUp` reaches the exact final formatted value; chart painter clamps `progress`; existing suite green.
- On-device (user): the rest-timer final-5s feel, chart strokes, count-ups, row reveal, shimmer, profile slide, card expand.

## Out of scope
The additional gaps I identified beyond the agents' list (list-mutation animations, dialog restyling, onboarding entrance, sync feedback, unit-toggle cross-fade) — a future pass if wanted.
