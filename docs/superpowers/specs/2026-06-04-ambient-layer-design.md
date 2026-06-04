# Ambient layer — drifting accent auras, film grain, workout intensity, PR bloom

**Date:** 2026-06-04
**Status:** Approved (design)
**Scope:** An always-on ambient visual layer over the whole app: two slow-drifting accent-tinted auras + a static film-grain texture, intensifying (speed + opacity) while a workout is active, plus a one-shot full-screen accent "bloom" when a set beats the previous best (alongside the existing PR badge shimmer + heavy haptic). The "letterbox backlight" from the mockups is framing only — explicitly skipped (user's call). Ships as v0.8.0.

## Placement decision

Overlay ABOVE all routes (chosen over behind-content): every screen sits on an opaque `tokens.bg` Scaffold, so a true background layer would require making every Scaffold transparent. Instead one `AmbientLayer` wraps the app's content via the `MaterialApp.builder` callback, drawing inside an `IgnorePointer` above whatever route is on top. Over the dark theme, low-alpha accent glows read as background halos; over content they tint faintly (the intended wash). All alphas low enough that content stays crisp.

## Components

### `AmbientController` (new, lives in `app/lib/widgets/ambient_layer.dart` alongside the layer — one cohesive module)
ChangeNotifier in the root MultiProvider with exactly one job: `void bloom()` — increments a `bloomCount` and notifies. The layer listens and runs the one-shot wash on each increment. Trigger site: `app/lib/session/set_row.dart` ~:148, where the live-PR `HapticFeedback.heavyImpact()` already fires → add `context.read<AmbientController>().bloom();`.

### `AmbientLayer` (new, `app/lib/widgets/ambient_layer.dart`)
`Stack[ child, IgnorePointer(RepaintBoundary(<ambient painting>)) ]`, wired as `MaterialApp(builder: (ctx, child) => AmbientLayer(child: child!))` — NOTE: main.dart already wraps MaterialApp in a theme `Builder`; the ambient uses MaterialApp's own `builder:` param so it sits INSIDE the Navigator's context (above routes, below nothing). It needs `SessionManager` and `AmbientController` and `SettingsService` — all provided above MaterialApp, so `context.watch/read` works.

**Auras.** Two radial-gradient discs (accent → transparent; NO BackdropFilter/ImageFilter blur — plain gradients, GPU-trivial), diameter ≈ 0.7 × shortest screen side. Positions follow slow Lissajous paths — pure function, unit-testable:
```dart
/// t in seconds (virtual clock). Returns 0..1 fractional offsets.
({double x, double y}) auraPosition(double t, {required double periodX, required double periodY, required double phase})
```
Aura A: periodX 26s / periodY 34s; Aura B: periodX 34s / periodY 22s, phase-shifted so they roam opposite halves. Driven by a `Ticker` accumulating a virtual clock: `_t += dt * _speed` — speed changes are smooth by construction (no controller restarts).

**Workout intensity.** The layer watches `SessionManager.hasActive`: target speed 1.0 calm / 2.2 active; target aura alpha 0.05 calm / 0.09 active. Both ease toward their targets over ~1s inside the ticker (lerp per tick) — entering/leaving a workout glides, never jumps.

**Film grain.** A 128×128 RGBA noise tile generated ONCE at runtime via `dart:ui` (`Random` per-pixel low-alpha white/black speckle; no asset), drawn tiled (`ImageRepeat.repeat`) across the screen at α≈0.03. Static — animated grain flickers and costs. Until the async generation completes, the grain simply isn't drawn.

**PR bloom.** On each `bloomCount` change: a one-shot ~700ms radial accent wash centered on screen — opacity 0 → ~0.18 → 0 (ease-out curve both ways) with the radius expanding ~1.0 → ~1.3×. Re-trigger restarts the animation. Skipped entirely under reduced motion.

**Reduced motion** (`MediaQuery.disableAnimations`): no ticker (auras render at fixed t=0 positions, calm alpha), no bloom; grain stays (static texture, not motion).

**Kill switch.** `SettingsService` gains `bool ambientEnabled` (default true, persisted like the other settings) + an "Ambient effects" toggle row in Profile → Appearance (match the existing rows' style). When off, `AmbientLayer` returns the child untouched (no ticker, no painting).

**Theme/accent reactivity.** Aura/bloom color reads `tokens.accent` each build; accent or theme changes propagate naturally. Same alphas in light mode (subtle there too; eyeball on device).

## Performance constraints
- No blur filters anywhere — radial gradients only.
- `RepaintBoundary` isolates the ambient repaints from app content.
- One Ticker total; it does not run when ambient is disabled or reduced motion is set. (Flutter stops frame production when the app is backgrounded, so no battery drain off-screen.)
- Grain tile generated once, cached.

## Testing
- Pure: `auraPosition` bounded in [0,1], periodic, distinct paths for the two parameter sets.
- `AmbientController.bloom()` increments + notifies.
- Widget: layer renders its child and hits don't land on the ambient (IgnorePointer); disabled setting → child passthrough (no Ticker objects); reduced motion → no ticker; bloom: trigger → overlay visible mid-animation → gone after settle.
- Existing 185 stay green. On-device (user): calm drift on Today, intensified feel mid-workout, bloom on a PR set, grain subtlety, accent-switch reactivity, toggle off.

## Out of scope
Letterbox backlight (mockup framing); shaders/Lottie; animated grain; per-screen ambient variations; light-mode-specific tuning beyond the shared alphas.
