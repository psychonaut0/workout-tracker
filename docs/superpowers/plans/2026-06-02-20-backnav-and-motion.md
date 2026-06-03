# Back-nav + Motion Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix Android back (home-first, Plan-editor-aware), enlarge the FAB, remove the cut dumbbell, and give the whole app a fast/snappy motion layer plus hero moments (set-done pop, PR pulse, summary reveal).

**Architecture:** A shell-level `PopScope` driven by a pure `decideBack` + a `PlanScreenState.handleBack()` hook. A tiny motion system (`Motion` constants + `PressableScale` + `StaggeredEntrance`) applied surgically; hero moments are one-shot transform/opacity animations + built-in `HapticFeedback`. No new dependencies.

**Tech Stack:** Flutter 3.44 (fvm, `make -C app`), built-in animations/haptics only.

**Spec:** `docs/superpowers/specs/2026-06-02-backnav-and-motion-pass-design.md`

**Branch:** `backnav-motion` (off `main`).

**Grounding facts (verified):**
- `app_shell.dart`: `_AppShellState` holds `int _index = 0`; `IndexedStack(index: _index, children: [...,'const PlanScreen()'])` (~:105-118); the FAB's session push is `Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(...))` (~:86-87). No `PopScope` anywhere in `lib/`.
- `plan_screen.dart`: `_PlanScreenState` (private) with `_EditorRoute? _editor`, `_onBack() => setState(() => _editor = null)` (:51).
- `w_tab_bar.dart` `_FabButton`: `width: 52, height: 52` (:172-173), icon `size: 23`.
- `split_card.dart` ~:113-126: the decorative `Positioned(right: -28, top: -28, child: IgnorePointer(child: Icon(WIcons.dumbbell, size: 150, ...)))` inside a `Stack`.
- `stepper.dart` (`WStepper`): buttons are `GestureDetector`s; `widget.onChanged(clamped)` fires at :65; the value label `Text` is at ~:104; values clamp ≥ 0.
- `set_row.dart`: `done = set.done`; the check button toggles done; shows `PRBadge` (in `lib/widgets/pr_badge.dart`) when PR.
- Tests baseline: 133.

---

## Task 1: Back navigation + FAB size + dumbbell removal

**Files:**
- Create: `app/lib/shell/back_dispatch.dart`
- Modify: `app/lib/shell/app_shell.dart`, `app/lib/ui/plan_screen.dart`, `app/lib/shell/w_tab_bar.dart`, `app/lib/widgets/split_card.dart`
- Test: `app/test/shell/back_dispatch_test.dart`

- [ ] **Step 1: Failing test for the pure back decision**

Create `app/test/shell/back_dispatch_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/back_dispatch.dart';

void main() {
  test('a tab that handled back wins (stay put)', () {
    expect(decideBack(tabHandled: true, tabIndex: 3), BackAction.none);
  });
  test('non-home tab goes home', () {
    for (final i in [1, 2, 3]) {
      expect(decideBack(tabHandled: false, tabIndex: i), BackAction.goHome);
    }
  });
  test('home exits', () {
    expect(decideBack(tabHandled: false, tabIndex: 0), BackAction.exit);
  });
}
```

- [ ] **Step 2: Run, watch fail** — `make -C app test 2>&1 | tail -10` → FAIL.

- [ ] **Step 3: Implement `back_dispatch.dart` + wire the shell**

Create `app/lib/shell/back_dispatch.dart`:
```dart
/// What the shell should do with an Android back press.
enum BackAction { none, goHome, exit }

/// Priority: a tab that consumed the press wins; otherwise non-home tabs go
/// home; home exits the app.
BackAction decideBack({required bool tabHandled, required int tabIndex}) {
  if (tabHandled) return BackAction.none;
  return tabIndex == 0 ? BackAction.exit : BackAction.goHome;
}
```

In `app/lib/ui/plan_screen.dart`: rename the private `_PlanScreenState` to public `PlanScreenState` (update `createState`) and add:
```dart
  /// Consumes a back press when the in-tab editor is open. Returns true if handled.
  bool handleBack() {
    if (_editor == null) return false;
    _onBack();
    return true;
  }
```

In `app/lib/shell/app_shell.dart`:
- `import 'package:flutter/services.dart';` (SystemNavigator), `import 'back_dispatch.dart';`
- Add `final _planKey = GlobalKey<PlanScreenState>();` to `_AppShellState`; instantiate `PlanScreen(key: _planKey)` in the IndexedStack (drop the `const`).
- Wrap the Scaffold in:
```dart
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tabHandled =
            _index == 3 && (_planKey.currentState?.handleBack() ?? false);
        switch (decideBack(tabHandled: tabHandled, tabIndex: _index)) {
          case BackAction.none:
            break;
          case BackAction.goHome:
            setState(() => _index = 0);
          case BackAction.exit:
            SystemNavigator.pop();
        }
      },
      child: <existing Scaffold>,
    );
```
(Plan is index 3 in the IndexedStack — confirm against the children order.)

- [ ] **Step 4: FAB 52→64** — in `w_tab_bar.dart` `_FabButton`: `width: 64, height: 64`, icon `size: 28`. Keep the existing boxShadow.

- [ ] **Step 5: Delete the dumbbell** — in `split_card.dart`, remove the entire decorative `Positioned(right: -28, top: -28, ... WIcons.dumbbell ...)` block (and the now-unused comment). If `WIcons.dumbbell` becomes unused in the file, leave the import only if other icons use it (analyze will tell).

- [ ] **Step 6: Verify** — `make -C app test` (136 = 133 + 3) + `make -C app analyze` → green/clean.

- [ ] **Step 7: Commit**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker && git checkout -b backnav-motion
git add app/lib/shell/back_dispatch.dart app/lib/shell/app_shell.dart app/lib/ui/plan_screen.dart app/lib/shell/w_tab_bar.dart app/lib/widgets/split_card.dart app/test/shell/back_dispatch_test.dart
git commit -m "fix(app): back goes home-first (Plan editor aware); bigger FAB; drop cut dumbbell"
```

---

## Task 2: Motion primitives (`Motion`, `PressableScale`, `StaggeredEntrance`, stepper tick)

**Files:**
- Create: `app/lib/theme/motion.dart`, `app/lib/widgets/pressable.dart`
- Modify: `app/lib/widgets/stepper.dart`
- Test: `app/test/widgets/pressable_test.dart`

- [ ] **Step 1: Failing test for PressableScale**

Create `app/test/widgets/pressable_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/widgets/pressable.dart';

void main() {
  testWidgets('scales down on pointer-down and back up on release', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: PressableScale(child: SizedBox(width: 100, height: 40))),
    ));
    double currentScale() {
      final t = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      return t.scale;
    }
    expect(currentScale(), 1.0);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump();
    expect(currentScale(), lessThan(1.0));
    await gesture.up();
    await tester.pump();
    expect(currentScale(), 1.0);
  });

  testWidgets('does not block the child\'s own taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: PressableScale(
          child: GestureDetector(onTap: () => tapped = true, child: const SizedBox(width: 100, height: 40)),
        ),
      ),
    ));
    await tester.tap(find.byType(PressableScale));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run, watch fail** — FAIL (pressable not found).

- [ ] **Step 3: Implement**

`app/lib/theme/motion.dart`:
```dart
import 'package:flutter/widgets.dart';

/// Single source of motion truth: fast & snappy, zero bounce.
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;

  /// Honors the platform reduced-motion setting.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}
```

`app/lib/widgets/pressable.dart`:
```dart
import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// Press-down scale feedback (1.0 → 0.97) that NEVER interferes with the
/// child's own gestures: it observes raw pointer events via [Listener]
/// (no gesture-arena participation).
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.pressedScale = 0.97});

  final Widget child;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}
```

Also add to `motion.dart` (below `Motion`) the one-shot entrance used by Today + the summary:
```dart
/// One-shot fade + 12px rise on first mount, staggered by [index]. Never
/// re-plays on rebuilds (the animation only runs forward once).
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.base,
  );
  late final CurvedAnimation _a = CurvedAnimation(parent: _c, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() { _a.dispose(); _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - _a.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
```

`stepper.dart` (WStepper): wrap the value `Text` (~:104) in an `AnimatedSwitcher` that slides the new value in the direction of change, and add a selection haptic where `onChanged` fires (:65):
- Track the previous value in the state; compute `up = newValue > oldValue`.
- `AnimatedSwitcher(duration: Motion.of(context, Motion.fast), transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween(begin: Offset(0, up ? 0.4 : -0.4), end: Offset.zero).animate(anim), child: child)), child: Text(key: ValueKey(widget.format(widget.value)), ...existing text...))`
- At the `widget.onChanged(clamped)` site add `HapticFeedback.selectionClick();` (`import 'package:flutter/services.dart';`).
READ the actual stepper state structure and adapt; the contract: value label animates directionally, taps haptic, existing stepper tests (targets tab, edit sheet) stay green.

- [ ] **Step 4: Run** — all tests pass (138 = 136 + 2), analyze clean.

- [ ] **Step 5: Commit**
```bash
git add app/lib/theme/motion.dart app/lib/widgets/pressable.dart app/lib/widgets/stepper.dart app/test/widgets/pressable_test.dart
git commit -m "feat(app): motion system — Motion constants, PressableScale, StaggeredEntrance, stepper ticks"
```

---

## Task 3: Micro layer application

**Files:**
- Modify: `app/lib/shell/app_shell.dart` (tab fade), `app/lib/ui/plan_screen.dart` (editor slide), `app/lib/ui/today_screen.dart` (entrance), `app/lib/widgets/split_card.dart` + `app/lib/ui/history_screen.dart` + `app/lib/ui/plan_screen.dart`(`_SegBtn`) + `app/lib/widgets/plan_form.dart`(`PrimaryBtn`) + `app/lib/shell/w_tab_bar.dart`(FAB) (PressableScale)

- [ ] **Step 1: Tab fade (app_shell)** — wrap the `IndexedStack` in a small stateful `_TabFade` (declare it in `app_shell.dart`): holds an `AnimationController` (Motion.fast); `didUpdateWidget` → if `index` changed, `_c.forward(from: 0.35)`; build = `FadeTransition(opacity: _c, child: child)`. IndexedStack stays mounted (state preserved); switching gives a soft cut. Honor `MediaQuery.disableAnimations` (skip by keeping opacity 1).

- [ ] **Step 2: Plan editor slide** — in `plan_screen.dart` `_buildBody()`, wrap the returned widget in:
```dart
    return AnimatedSwitcher(
      duration: Motion.of(context, const Duration(milliseconds: 220)),
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_editor == null ? 'list-$_activeTab' : 'editor-${_editor!.kind}-${_editor!.id}'),
        child: <the existing branch result>,
      ),
    );
```

- [ ] **Step 3: Today entrance** — in `today_screen.dart`, wrap the ListView's top-level children (greeting header, split card section, This-week section, Recent PRs, Weekly volume — the existing direct children) each in `StaggeredEntrance(index: i, child: ...)` with sequential indices. One-shot on mount only (StaggeredEntrance guarantees this).

- [ ] **Step 4: PressableScale application** — wrap the tappable surfaces' INNER content (inside their GestureDetector/InkWell so the child's gestures still own the tap; PressableScale only observes pointers — order doesn't break either way, prefer GestureDetector(child: PressableScale(child: visual))):
  - `split_card.dart`: the day-card body (the tappable start/open area).
  - `history_screen.dart`: `SessionCard`'s card container.
  - `plan_screen.dart`: `_SegBtn`.
  - `widgets/plan_form.dart`: `PrimaryBtn`.
  - `w_tab_bar.dart`: `_FabButton` + the tab items.
  READ each widget; apply where there's a visible pressed surface. Skip any surface where wrapping visibly breaks layout.

- [ ] **Step 5: Verify** — full tests green (138), analyze clean.

- [ ] **Step 6: Commit**
```bash
git add -A app/lib
git commit -m "feat(app): micro-motion layer — tab fade, editor slide, entrances, press feedback"
```

---

## Task 4: Hero moments

**Files:**
- Modify: `app/lib/shell/app_shell.dart` (FAB route), `app/lib/session/set_row.dart` (done pop + haptics + PR haptic), `app/lib/widgets/pr_badge.dart` (pulse), `app/lib/session/session_summary_screen.dart` (reveal + count-up + flash)

- [ ] **Step 1: FAB → session transition** — in `app_shell.dart` (~:86), replace the `MaterialPageRoute` for the session push with:
```dart
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => <existing screen>,
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Motion.curve);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      )
```
(Apply ONLY to the FAB/session push; other pushes unchanged.)

- [ ] **Step 2: Set-done pop + haptics** — in `set_row.dart`: where the check toggle fires, add `HapticFeedback.mediumImpact()`; wrap the check icon/control in a one-shot pop when `done` flips to true — a small private `_Pop` stateful (declared in `set_row.dart`): on `didUpdateWidget` where `done` went false→true, play a 1.0→1.15→1.0 scale (controller, Motion.fast up + Motion.fast down). If the toggle makes this set the NEW live top-set AND it beats the block's all-time best (the parent block already computes `isLiveTopSet`/has `bestKg` — read `exercise_block.dart` for what's available), fire `HapticFeedback.heavyImpact()` instead.

- [ ] **Step 3: PR badge pulse** — `pr_badge.dart`: add `pulseOnMount` (default true): a one-shot ~400ms scale 1.0→1.12→1.0 + accent glow (an outer `BoxShadow` flash via `TweenAnimationBuilder`) on first mount. Honor `disableAnimations`.

- [ ] **Step 4: Summary reveal** — `session_summary_screen.dart`: wrap its main content blocks in `StaggeredEntrance` (40ms steps — pass spaced indices); make the PR count tick up from 0 (`TweenAnimationBuilder<int>(tween: IntTween(begin: 0, end: prCount), duration: Motion.slow)`); one accent flash on the header (a `TweenAnimationBuilder` color/opacity from accent→normal over ~500ms on mount). READ the screen first and apply to its real structure.

- [ ] **Step 5: Verify** — full tests green, analyze clean.

- [ ] **Step 6: Commit**
```bash
git add -A app/lib
git commit -m "feat(app): hero moments — session transition, set-done pop, PR pulse, summary reveal"
```

---

## Task 5: Verify + ship (INLINE)

- [ ] **Step 1:** `make -C app analyze` + `make -C app test` + `make -C app build-apk-release` — all green, release APK links.
- [ ] **Step 2:** Merge `--no-ff` → main, push.
- [ ] **Step 3:** Cut `v0.3.0` (tag + push) → CI publishes `reps-v0.3.0.apk`; the user installs from GitHub Releases and verifies on-device: back behavior (tab → Today → exit; Plan editor closes first), bigger FAB, no dumbbell, and the motion feel (tabs, presses, steppers, session open, set-done, PR pulse, summary).

## Verification summary
1. +5 tests (decideBack ×3, PressableScale ×2); existing 133 stay green; analyze clean; release APK builds.
2. On-device: the four reported issues resolved; motion feels fast/snappy; reduced-motion respected.

## Out of scope
Lottie/rive/shaders; redesigns; remaining polish (delete-exercise guard, Spec B nits).
