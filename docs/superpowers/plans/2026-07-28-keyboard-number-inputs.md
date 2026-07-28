# Keyboard-Editable Number Inputs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every numeric control in the app typeable, not just +/-. All 17 `WStepper` instances gain tap-to-type; the bodyweight sheet's big ± number becomes tappable. A typed value survives **every** way of leaving the field, including dismissing the keyboard. Haptics become perceptible and consistent.

**Architecture:** One pure helper owns the parse/clamp/round semantics so the stepper and the bodyweight sheet cannot drift apart. `WStepper` gains local `min`/`max` (so it clamps what it displays instead of relying on a parent round-trip), `formatForEdit` (bare-number prefill for suffixed displays), `emptyValue` (clearing a field returns to a sentinel), and `allowDecimal`. Commit is driven by four independent exit paths.

**Tech Stack:** Flutter 3.44.0 (pinned via fvm), Dart 3.12, `provider`, `flutter_test` only (no mocking package).

**Spec:** `docs/superpowers/specs/2026-07-28-keyboard-number-inputs-design.md`

## Global Constraints

- **Never run `flutter` directly.** It is pinned via fvm. Every command goes through the Makefile from the **repo root**: `make -C app analyze`, `make -C app test`, `make -C app test TEST=test/path/file.dart`. Never `cd`.
- **Run every command in this exact shape** — a bare `make -C app test` gets auto-backgrounded in this environment and strands the agent waiting on a notification that never arrives. Three implementers lost work to this on the previous branch:
  ```
  timeout 200 make -C app analyze > /tmp/x-analyze.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/x-analyze.log
  timeout 200 make -C app test TEST=test/widgets/stepper_input_test.dart > /tmp/x-t.log 2>&1; echo "EXIT=$?"; tail -15 /tmp/x-t.log
  timeout 400 make -C app test > /tmp/x-full.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/x-full.log | tail -5
  ```
  Never background anything; never spawn subagents.
- `make -C app analyze` must end at exactly **"No issues found!"**. Deprecated APIs **and unused imports** are both fatal.
- The full suite must stay green. Baseline at branch start: **249 tests**.
- Commit style: **Conventional Commits, standard types, subject line only, no body.**
- **No plan/spec/task numbers in code or comments.** Descriptive language only.
- **`double.tryParse`, never `double.parse`** — `double.parse('')` throws and one bad row blanks an entire list stream.
- Widget tests needing `context.tokens`: `MaterialApp(theme: buildTheme(Brightness.dark, accents[0]))`. Tests calling `AppLocalizations.of(context)` must use `wrapL10n` from `test/support/l10n_harness.dart`.
- **No new user-visible strings** in this increment, so **no ARB edits** — `test/l10n/arb_parity_test.dart` must stay green.
- Tests must be deterministic: **no fixed `Future.delayed` waits**. If you need to wait for real work, `pumpUntilFound` exists at `app/test/support/pump_until.dart`.

## Test-harness facts established against the pinned SDK (use these; do not re-derive)

These were researched directly against `/home/psy/fvm/versions/3.44.0`. They determine what can be a test versus a device check.

1. **Keyboard dismissal IS simulatable.** `tester.view.viewInsets = const FakeViewPadding(bottom: 300)` fires `WidgetsBindingObserver.didChangeMetrics` **synchronously during the assignment** (`flutter_test/lib/src/window.dart:1204-1210` → `binding.dart:922-926`). Set `tester.view.devicePixelRatio = 1.0` first and `addTearDown(tester.view.reset)`. Insets do **not** change layout constraints and do **not** touch focus (`editable_text.dart:4541-4557`), so "keyboard dismissed while the field is still focused" is exactly expressible.
2. **`tester.tap()` on another widget does NOT unfocus a TextField in a widget test.** Tap-outside only unfocuses for touch on web, and `flutter test` forces `TargetPlatform.android` (`foundation/_platform_io.dart:29-34`). To force focus loss use `FocusManager.instance.primaryFocus!.unfocus()`, or `tester.tap(..., kind: PointerDeviceKind.mouse)`, or pump a tree containing an autofocusing field. **A test that taps elsewhere and asserts a commit would silently prove nothing.**
3. **Focus changes are asynchronous** — `FocusManager` schedules a microtask (`focus_manager.dart:1920-1932`). Always `await tester.pump()` after any focus mutation before asserting.
4. **Use `pumpWidget` with a different root to trigger `deactivate`/`dispose`** — deterministic in one pump (`framework.dart:6021-6031`). A Navigator pop needs `pumpAndSettle` and is route-config dependent; only use it if the route interaction itself is under test.
5. **Assert the requested keypad via `tester.testTextInput.setClientArgs`**, not by reading the widget: `args['inputType']['decimal']` is the integer-vs-decimal distinction, and `args['inputAction']` is the *resolved* action (`TextField.textInputAction` is nullable and resolved late). Requires an open connection — `await tester.showKeyboard(finder)`. Caveat: no SDK test asserts `['decimal']` directly, so **confirm the literal value on the first run** and report what you saw.
6. **`FilteringTextInputFormatter.allow` with an anchored regex is a trap that WIPES THE FIELD.** On non-matching input `allMatches` is empty, so the whole text is treated as banned and replaced with `''` (`services/text_formatter.dart:356-385`). The SDK's own class doc prescribes `TextInputFormatter.withFunction` with a whole-string predicate instead (`text_formatter.dart:224-242`). Use `withFunction`.

**Device-only (cannot be a test):** whether Android's keypad actually renders a `.` key; real keyboard show/hide timing; the OS "hide keyboard" gesture's true focus semantics; whether a haptic is perceptible.

---

### Task 1: The pure number-input helper

**Files:**
- Create: `app/lib/util/number_input.dart`
- Test: `app/test/util/number_input_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `double? parseNumberInput(String raw, {double min, double? max, double? emptyValue, double Function(double)? parseDisplay})` and `double clampRound2(double v, {double min, double? max})` — used by Tasks 2, 3 and 8.

- [ ] **Step 1: Write the failing tests**

Create `app/test/util/number_input_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/number_input.dart';

void main() {
  group('clampRound2', () {
    test('rounds to two decimals', () {
      expect(clampRound2(1.005), 1.01);
      expect(clampRound2(72.4999), 72.5);
    });
    test('applies the floor', () {
      expect(clampRound2(-4), 0);
      expect(clampRound2(-4, min: 1), 1);
    });
    test('applies the ceiling', () {
      expect(clampRound2(150, max: 99), 99);
      expect(clampRound2(40, min: 0, max: 40), 40);
    });
  });

  group('parseNumberInput', () {
    test('parses a plain number', () {
      expect(parseNumberInput('92.5'), 92.5);
    });
    test('accepts a comma decimal separator', () {
      expect(parseNumberInput('12,5'), 12.5);
    });
    test('trims surrounding whitespace', () {
      expect(parseNumberInput('  8 '), 8);
    });
    test('returns null for text that is not a number', () {
      expect(parseNumberInput('abc'), isNull);
      expect(parseNumberInput('1.2.3'), isNull);
    });
    test('empty text yields emptyValue when given, else null', () {
      expect(parseNumberInput('', emptyValue: 0), 0);
      expect(parseNumberInput('   ', emptyValue: 0), 0);
      expect(parseNumberInput(''), isNull);
    });
    test('clamps to min and max', () {
      expect(parseNumberInput('150', min: 1, max: 99), 99);
      expect(parseNumberInput('0', min: 1, max: 99), 1);
      expect(parseNumberInput('-4'), 0);
    });
    test('applies parseDisplay before clamping', () {
      // Display space is double the caller space.
      expect(parseNumberInput('250', parseDisplay: (d) => d / 2), 125);
    });
    test('parseDisplay result is still clamped', () {
      expect(parseNumberInput('400', max: 99, parseDisplay: (d) => d / 2), 99);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```
timeout 200 make -C app test TEST=test/util/number_input_test.dart > /tmp/t1.log 2>&1; echo "EXIT=$?"; tail -12 /tmp/t1.log
```
Expected: FAIL — the source file does not exist, so the import cannot resolve.

- [ ] **Step 3: Write the implementation**

Create `app/lib/util/number_input.dart`:

```dart
/// Shared semantics for interpreting typed numeric text.
///
/// Lives apart from any widget so the stepper and the bodyweight sheet cannot
/// drift apart, and so the rules are testable without pumping a widget.

/// Clamps [v] into `[min, max]` and rounds to two decimals.
///
/// Two decimals kills floating-point drift from repeated stepping; [max] of
/// null means unbounded.
double clampRound2(double v, {double min = 0, double? max}) {
  var out = v < min ? min : v;
  if (max != null && out > max) out = max;
  return (out * 100).round() / 100;
}

/// Interprets [raw] typed text as a value in the caller's space.
///
/// Returns null to mean "leave the current value alone" — either the text was
/// not a number, or it was empty and no [emptyValue] sentinel was supplied.
/// Callers must NOT treat null as zero.
///
/// A comma is accepted as the decimal separator, since Italian, German and
/// Spanish keyboards produce one. [parseDisplay] converts from display space to
/// the caller's space (e.g. lb to kg) and is applied BEFORE clamping, so the
/// bounds are always expressed in the caller's space.
double? parseNumberInput(
  String raw, {
  double min = 0,
  double? max,
  double? emptyValue,
  double Function(double display)? parseDisplay,
}) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return emptyValue;
  final typed = double.tryParse(text);
  if (typed == null) return null;
  final mapped = parseDisplay?.call(typed) ?? typed;
  return clampRound2(mapped, min: min, max: max);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```
timeout 200 make -C app test TEST=test/util/number_input_test.dart > /tmp/t1b.log 2>&1; echo "EXIT=$?"; tail -8 /tmp/t1b.log
```
Expected: PASS.

- [ ] **Step 5: Analyze and run the full suite**

```
timeout 200 make -C app analyze > /tmp/t1-a.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/t1-a.log
timeout 400 make -C app test > /tmp/t1-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/t1-f.log | tail -2
```
Expected: "No issues found!" and all green.

- [ ] **Step 6: Commit**

```bash
git add app/lib/util/number_input.dart app/test/util/number_input_test.dart
git commit -m "feat(app): shared parse/clamp semantics for typed numeric input"
```

---

### Task 2: `WStepper` bounds, sentinels and keypad

Adds the value-space parameters. **Commit-on-exit is deliberately NOT in this task** — it is Task 3, so a reviewer can reject one without the other.

**Files:**
- Modify: `app/lib/widgets/stepper.dart`
- Test: `app/test/widgets/stepper_input_test.dart` (extend), `app/test/widgets/stepper_test.dart` (extend)

**Interfaces:**
- Consumes: `parseNumberInput`, `clampRound2` from Task 1.
- Produces: `WStepper` gains `min` (double, default 0), `max` (double?, default null), `emptyValue` (double?, default null), `allowDecimal` (bool, default true), `formatForEdit` (`String Function(double)?`, default null). Tasks 4-7 pass these.

Current source for reference — `stepper.dart:21-29` is the constructor, `:73-79` `_beginEdit`, `:81-97` `_commitEdit`, `:100-108` `didUpdateWidget`, `:111` `_round2`, `:113-122` `_step`, `:165-182` the `TextField`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/widgets/stepper_input_test.dart` (keep the existing `host()` helper and all five existing tests unchanged):

```dart
  testWidgets('formatForEdit prefills a bare number for a suffixed display',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 80,
      step: 2.5,
      format: (v) => '${v.toStringAsFixed(0)}kg',
      formatForEdit: (v) => v.toStringAsFixed(0),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text('80kg'), findsOneWidget);
    await tester.tap(find.text('80kg'));
    await tester.pumpAndSettle();

    // Seeded with the bare number, not "80kg" — which would not round-trip.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '80');

    await tester.enterText(find.byType(TextField), '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 90.0);
    expect(find.text('90kg'), findsOneWidget);
  });

  testWidgets('a typed value above max is clamped and displayed clamped',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 8,
      step: 1,
      min: 1,
      max: 99,
      format: (v) => v.round().toString(),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 99.0);
    expect(find.text('99'), findsOneWidget);
    expect(find.text('150'), findsNothing); // must not linger above the cap
  });

  testWidgets('a typed value below min is clamped up', (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 8,
      step: 1,
      min: 1,
      max: 99,
      format: (v) => v.round().toString(),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changed, 1.0);
  });

  testWidgets('stepping also respects max', (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 99,
      step: 1,
      min: 1,
      max: 99,
      format: (v) => v.round().toString(),
      onChanged: (v) => changed = v,
    )));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stepper-inc')));
    await tester.pump();
    expect(changed, 99.0);
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('clearing the field commits emptyValue when one is given',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 90,
      step: 15,
      emptyValue: 0,
      format: (v) => v == 0 ? 'Default' : '${v.round()}s',
      formatForEdit: (v) => v == 0 ? '' : v.round().toString(),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('90s'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 0.0);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('clearing the field changes nothing without emptyValue',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(WStepper(
      value: 90,
      step: 15,
      format: (v) => v.round().toString(),
      onChanged: (v) => changed = v,
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, isNull);
    expect(find.text('90'), findsOneWidget);
  });

  testWidgets('allowDecimal false requests an integer keypad and blocks a dot',
      (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 8,
      step: 1,
      allowDecimal: false,
      format: (v) => v.round().toString(),
      onChanged: (_) {},
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    final args = tester.testTextInput.setClientArgs!;
    final inputType = args['inputType'] as Map<String, dynamic>;
    expect(inputType['name'], 'TextInputType.number');
    expect(inputType['decimal'], isFalse);

    // The formatter rejects a separator outright.
    await tester.enterText(find.byType(TextField), '1.5');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isNot(contains('.')));
  });

  testWidgets('allowDecimal true requests a decimal keypad', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 80,
      step: 2.5,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (_) {},
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();

    final inputType =
        tester.testTextInput.setClientArgs!['inputType'] as Map<String, dynamic>;
    expect(inputType['decimal'], isTrue);
  });

  testWidgets('the formatter rejects a second separator', (tester) async {
    await tester.pumpWidget(host(WStepper(
      value: 1,
      step: 1,
      format: (v) => v.toStringAsFixed(1),
      onChanged: (_) {},
      editable: true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.0'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1.2');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1.2.3');
    await tester.pumpAndSettle();
    // The rejected edit leaves the previous text in place, it does NOT wipe it.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1.2');
  });

  testWidgets('an unrelated parent rebuild does not clobber a stepped value',
      (tester) async {
    // Regression guard: the internal copy exists so consecutive taps compound.
    // A rebuild from an unrelated source must not snap the label back.
    double? changed;
    var extra = 0;
    late StateSetter setOuter;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return Column(children: [
          Text('extra $extra'),
          WStepper(
            value: 10,
            step: 1,
            format: (v) => v.round().toString(),
            onChanged: (v) => changed = v,
          ),
        ]);
      },
    )));
    await tester.pump();

    await tester.tap(find.byKey(const Key('stepper-inc')));
    await tester.pump();
    expect(changed, 11.0);
    expect(find.text('11'), findsOneWidget);

    // Parent rebuilds for an unrelated reason, still passing value: 10.
    setOuter(() => extra = 1);
    await tester.pump();
    expect(find.text('11'), findsOneWidget,
        reason: 'an unrelated rebuild must not revert the stepped value');
  });
```

The last test needs `import 'package:flutter/material.dart';` for `StateSetter`/`Column` — check whether the file already imports it and only add what is missing (unused imports are fatal).

- [ ] **Step 2: Run to verify they fail**

```
timeout 200 make -C app test TEST=test/widgets/stepper_input_test.dart > /tmp/t2.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/t2.log
```
Expected: compile failure — `min`, `max`, `emptyValue`, `allowDecimal`, `formatForEdit` are not named parameters of `WStepper`.

- [ ] **Step 3: Extend the widget**

In `app/lib/widgets/stepper.dart`:

Add the import:
```dart
import '../util/number_input.dart';
```

Extend the constructor and fields (keep every existing parameter and its order; add the new ones after `parseDisplay`):

```dart
    this.formatForEdit,
    this.min = 0,
    this.max,
    this.emptyValue,
    this.allowDecimal = true,
```

```dart
  /// Formats the value for the inline edit field's initial text. Defaults to
  /// [format]. Provide a bare-number formatter when [format] appends a unit or
  /// a sentinel word ("80kg", "180s", "Default", "—") that would not round-trip
  /// through the numeric parser on commit.
  final String Function(double)? formatForEdit;

  /// Lower bound, enforced inside the widget for BOTH stepping and typing, so
  /// the label can never show a value the widget did not emit.
  final double min;

  /// Upper bound; null means unbounded.
  final double? max;

  /// Value committed when the field is submitted empty. Null means an empty
  /// field leaves the value unchanged. Set this only where a sentinel exists
  /// (rest "Default", target "—").
  final double? emptyValue;

  /// When false the field requests an integer keypad and refuses a decimal
  /// separator.
  final bool allowDecimal;
```

Replace `_round2` usage with the shared helper. Delete the private `_round2` (`stepper.dart:111`) and change `_step` (`:113-122`) to:

```dart
  void _step(int dir) {
    final clamped = clampRound2(
      _internalValue + dir * widget.step,
      min: widget.min,
      max: widget.max,
    );
    setState(() {
      _up = clamped > _internalValue;
      _internalValue = clamped;
    });
    HapticFeedback.selectionClick();
    widget.onChanged(clamped);
  }
```

Change `_beginEdit` (`:73-79`) to seed from `formatForEdit` when provided:

```dart
  void _beginEdit() {
    if (!widget.editable) return;
    final initial = (widget.formatForEdit ?? widget.format)(_internalValue);
    _editCtrl = TextEditingController(text: initial);
    _editCtrl!.selection =
        TextSelection(baseOffset: 0, extentOffset: _editCtrl!.text.length);
    setState(() => _editing = true);
  }
```

Change `_commitEdit` (`:81-97`) to use the helper, and call `onChanged` **outside** the `setState` closure so it matches `_step`:

```dart
  void _commitEdit() {
    if (!_editing) return;
    final committed = parseNumberInput(
      _editCtrl?.text ?? '',
      min: widget.min,
      max: widget.max,
      emptyValue: widget.emptyValue,
      parseDisplay: widget.parseDisplay,
    );
    setState(() {
      _editing = false;
      if (committed != null) {
        _up = committed > _internalValue;
        _internalValue = committed;
      }
    });
    if (committed != null) widget.onChanged(committed);
    _editCtrl?.dispose();
    _editCtrl = null;
  }
```

Add the keypad and formatter to the `TextField` (`:165-182`), replacing the existing `keyboardType:` line:

```dart
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
                          final ok = widget.allowDecimal
                              ? RegExp(r'^\d*[.,]?\d*$')
                                  .hasMatch(newValue.text)
                              : RegExp(r'^\d*$').hasMatch(newValue.text);
                          return ok ? newValue : oldValue;
                        }),
                      ],
```

Note `keyboardType` can no longer be `const` because it reads `widget.allowDecimal`.

Leave `didUpdateWidget` (`:100-108`) EXACTLY as it is. Do not change its guard to compare `_internalValue` — that shipped once and makes any unrelated rebuild clobber an in-flight value. The last test in Step 1 pins that.

- [ ] **Step 4: Run the stepper tests**

```
timeout 200 make -C app test TEST=test/widgets/stepper_input_test.dart > /tmp/t2b.log 2>&1; echo "EXIT=$?"; tail -20 /tmp/t2b.log
timeout 200 make -C app test TEST=test/widgets/stepper_test.dart > /tmp/t2c.log 2>&1; echo "EXIT=$?"; tail -10 /tmp/t2c.log
```
Expected: PASS. For the two keypad tests, **report the literal value you observed for `inputType['decimal']`** — no SDK test asserts it, so it is worth recording.

- [ ] **Step 5: Analyze and full suite**

```
timeout 200 make -C app analyze > /tmp/t2-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t2-a.log
timeout 400 make -C app test > /tmp/t2-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t2-f.log | tail -4
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/stepper.dart app/test/widgets/stepper_input_test.dart app/test/widgets/stepper_test.dart
git commit -m "feat(app): stepper bounds, empty-value sentinel and integer keypad"
```

---

### Task 3: Commit on every exit path

The user's actual complaint: dismissing the Android keyboard discards what was typed. Cause — commit happens only on `onSubmitted` or focus loss, `textInputAction` is unset (Android numeric IMEs frequently ship no action key), and hiding the keyboard does **not** drop focus.

**Files:**
- Modify: `app/lib/widgets/stepper.dart`
- Test: `app/test/widgets/stepper_commit_test.dart` (new)

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: no new public API. `WStepper`'s State becomes a `WidgetsBindingObserver` and owns a `FocusNode`.

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/stepper_commit_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/theme/app_theme.dart';
import 'package:workout_tracker/widgets/stepper.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.dark, accents[0]),
        home: Scaffold(body: Center(child: SizedBox(width: 160, child: child))),
      );

  Widget stepper(void Function(double) onChanged) => WStepper(
        value: 80,
        step: 2.5,
        format: (v) => v.toStringAsFixed(1),
        onChanged: onChanged,
        editable: true,
      );

  testWidgets('the field requests the done action', (tester) async {
    await tester.pumpWidget(host(stepper((_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.done');
  });

  testWidgets('dismissing the keyboard commits the typed value',
      (tester) async {
    // THE reported defect. Hiding the Android keyboard does not drop focus, so
    // without an inset-collapse listener the typed text is silently discarded.
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();

    // Keyboard comes up.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '92.5');
    await tester.pump();
    expect(changed, isNull, reason: 'not committed until an exit path fires');

    // System dismisses the keyboard; focus is deliberately untouched.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changed, 92.5);
    expect(find.text('92.5'), findsOneWidget);
  });

  testWidgets('losing focus commits the typed value', (tester) async {
    // NOTE: tester.tap on another widget does NOT unfocus in a widget test
    // (tap-outside only unfocuses for touch on web, and tests force Android),
    // so drive focus loss explicitly.
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '85');
    await tester.pump();

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changed, 85.0);
  });

  testWidgets('being disposed mid-edit commits the typed value',
      (tester) async {
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '77.5');
    await tester.pump();

    // Replacing the root deactivates and unmounts the stepper in one pump.
    await tester.pumpWidget(host(const Text('gone')));
    await tester.pump();

    expect(changed, 77.5);
  });

  testWidgets('text that is not a number commits nothing', (tester) async {
    double? changed;
    await tester.pumpWidget(host(stepper((v) => changed = v)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, isNull);
    expect(find.text('80.0'), findsOneWidget);
  });

  testWidgets('committing only fires onChanged once', (tester) async {
    // Four exit paths can each call _commitEdit; the re-entrancy guard must
    // keep that to a single emission.
    final emitted = <double>[];
    await tester.pumpWidget(host(stepper(emitted.add)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(host(const Text('gone')));
    await tester.pump();

    expect(emitted, [99.0]);
  });
}
```

If `enterText` on a formatter-guarded field rejects `'abc'` outright so the field still holds `80.0`, that test still asserts the right outcome (nothing committed, value unchanged) — note in your report which mechanism prevented it.

- [ ] **Step 2: Run to verify they fail**

```
timeout 200 make -C app test TEST=test/widgets/stepper_commit_test.dart > /tmp/t3.log 2>&1; echo "EXIT=$?"; tail -25 /tmp/t3.log
```
Expected: the done-action test and the keyboard-dismissal test fail (no `textInputAction`, no inset listener). Report exactly which failed and how.

- [ ] **Step 3: Implement the four exit paths**

In `app/lib/widgets/stepper.dart`:

Make the State an observer and own its focus node. Replace the State class header and lifecycle:

```dart
class _WStepperState extends State<WStepper> with WidgetsBindingObserver {
  late double _internalValue;
  bool _up = true;

  bool _editing = false;
  TextEditingController? _editCtrl;
  final FocusNode _focusNode = FocusNode();

  /// Whether the soft keyboard has actually been up during this edit. The
  /// inset-collapse check is only armed after we have seen insets, so it stays
  /// inert on desktop and in widget tests where insets are always zero.
  bool _sawKeyboard = false;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.value;
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _editCtrl?.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Sheet closed, route popped, or row recycled while editing — keep the
    // value rather than discarding it.
    if (_editing) _commitEdit();
    super.deactivate();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) _commitEdit();
  }

  @override
  void didChangeMetrics() {
    if (!_editing || !mounted) return;
    final insets = View.of(context).viewInsets.bottom;
    if (insets > 0) {
      _sawKeyboard = true;
      return;
    }
    if (_sawKeyboard) {
      // The keyboard was dismissed by the system. Focus is NOT dropped by that
      // on Android, so nothing else would ever commit this edit.
      _sawKeyboard = false;
      _commitEdit();
      _focusNode.unfocus();
    }
  }
```

Reset `_sawKeyboard` when an edit begins — in `_beginEdit`, before `setState`:
```dart
    _sawKeyboard = false;
```

Wire the node and the action into the `TextField`, and REMOVE the `Focus(onFocusChange: …)` wrapper now that the node carries a listener (the wrapper and the node would otherwise both fire):

```dart
              child: _editing
                  ? TextField(
                      controller: _editCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.numberWithOptions(
                          decimal: widget.allowDecimal),
                      inputFormatters: [ /* unchanged from the previous task */ ],
                      onSubmitted: (_) => _commitEdit(),
                      style: WorkoutType.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: tokens.text,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  : GestureDetector( /* unchanged */ ),
```

**Fix the controller lifecycle bug while here.** `_commitEdit` currently calls `setState` (async rebuild) and then *synchronously* disposes the controller, leaving the still-mounted `TextField` holding a disposed controller and transitioning `controller:` to null mid-life. Since `_editing` flips to false in the same `setState`, the `TextField` is gone from the tree on the next build — but the disposal must not race it. Keep the controller alive until the next frame:

```dart
    final old = _editCtrl;
    _editCtrl = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
```
Replace the current `_editCtrl?.dispose(); _editCtrl = null;` tail of `_commitEdit` with that. If a test surfaces a "used after dispose" or a leak assertion, say so in your report rather than papering over it.

`View.of(context)` needs `package:flutter/widgets.dart`, already available via the existing `material.dart` import — do not add a second import.

- [ ] **Step 4: Run the commit tests**

```
timeout 200 make -C app test TEST=test/widgets/stepper_commit_test.dart > /tmp/t3b.log 2>&1; echo "EXIT=$?"; tail -25 /tmp/t3b.log
timeout 200 make -C app test TEST=test/widgets/stepper_input_test.dart > /tmp/t3c.log 2>&1; echo "EXIT=$?"; tail -12 /tmp/t3c.log
```
Expected: PASS. The five pre-existing `stepper_input_test.dart` tests must still pass — the old `Focus` wrapper's focus-loss commit is now the node listener's job, and one of those tests relies on commit-on-submit.

- [ ] **Step 5: Analyze and full suite**

```
timeout 200 make -C app analyze > /tmp/t3-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t3-a.log
timeout 400 make -C app test > /tmp/t3-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t3-f.log | tail -4
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/stepper.dart app/test/widgets/stepper_commit_test.dart
git commit -m "fix(app): a typed stepper value survives every way of leaving the field"
```

---

### Task 4: Opt in the day editor (4 sites)

**Files:**
- Modify: `app/lib/ui/day_editor.dart` — the four `WStepper`s at `:628`, `:640`, `:657`, `:669`
- Test: `app/test/ui/day_editor_steppers_test.dart` (new)

**Interfaces:** consumes `WStepper`'s new params. Produces nothing.

All four already format a bare number (`(v) => v.round().toString()`), so **none needs `formatForEdit`**. Their bounds mirror the existing clamp helpers at `day_editor.dart:443-475`, which stay in place (they own the cross-field rep bump).

- [ ] **Step 1: Add the parameters**

| Site | Add |
|---|---|
| `:628` working sets | `editable: true, allowDecimal: false, min: 1, max: 99,` |
| `:640` warm-ups | `editable: true, allowDecimal: false, min: 0, max: 99,` |
| `:657` rep low | `editable: true, allowDecimal: false, min: 1, max: 99,` |
| `:669` rep high | `editable: true, allowDecimal: false, min: (d.repLow ?? 1).toDouble(), max: 99,` |

Rep high takes a **dynamic** `min` so the widget itself enforces the same floor `_updateRepHigh` does (`day_editor.dart:469-470`). Leave every `onChanged` and all four clamp helpers untouched.

- [ ] **Step 2: Write the test**

Create `app/test/ui/day_editor_steppers_test.dart`. `_SlotRow` is private, so drive the smallest public surface that renders it — read `day_editor.dart` to find the public widget and what it requires. **If rendering it needs a real database or a repository the test cannot construct, do not force it: say so in your report and instead assert the four steppers' configuration through a focused test of the public widget you CAN mount, or report that this task's verification is analyze + the shared stepper tests only.** Do not invent a fake database.

If it is mountable, assert: typing `150` into working sets commits `99`, typing `0` commits `1`, and the field opens an integer keypad (`setClientArgs!['inputType']['decimal'] == false`).

- [ ] **Step 3: Verify**

```
timeout 200 make -C app analyze > /tmp/t4-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t4-a.log
timeout 400 make -C app test > /tmp/t4-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t4-f.log | tail -4
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/ui/day_editor.dart app/test/ui/day_editor_steppers_test.dart
git commit -m "feat(app): tap-to-type the day-editor slot steppers"
```

---

### Task 5: Opt in the exercise editor (6 sites)

**Files:**
- Modify: `app/lib/ui/exercise_editor.dart` — `:483`, `:506`, `:524`, `:544`, `:558`, `:575`

**THE TRAP IN THIS TASK.** Start weight (`:483`) holds its value in **display units**, not kg — `_baseWeightDisplay` (`:60`), stepped by `_stepDisplay` (`:61`), converted to kg only on save (`:206-209`) and re-converted on unit change by `_syncUnit` (`:187-196`). It is the ONLY weight stepper that works this way. Therefore it must **NOT** get `parseDisplay: UnitService.toKg` — the typed number is already in display space and converting it would halve or double the value. Leave `parseDisplay` unset on this site.

- [ ] **Step 1: Add the parameters**

| Site | Add |
|---|---|
| `:483` start weight | `editable: true, formatForEdit: (v) => fmtPlain(v), min: 0,` — NO `parseDisplay`, and `allowDecimal` stays true (2.5 kg plates) |
| `:506` rep low | `editable: true, allowDecimal: false, min: 1, max: 99,` |
| `:524` rep high | `editable: true, allowDecimal: false, min: _repLow.toDouble(), max: 99,` |
| `:544` working sets | `editable: true, allowDecimal: false, min: 1, max: 99,` |
| `:558` warm-ups | `editable: true, allowDecimal: false, min: 0, max: 99,` |
| `:575` rest | `editable: true, allowDecimal: false, min: 0, emptyValue: 0, formatForEdit: (v) => v == 0 ? '' : v.round().toString(),` |

`fmtPlain` is already imported in this file (it is used by the current `format` at `:486`); confirm rather than adding a duplicate import.

The rest stepper's `formatForEdit` returning `''` for 0 plus `emptyValue: 0` is what finally makes "type it back to Default" work — the previous attempt had the empty prefill but no way to commit an empty field. Leave all six inline `onChanged` clamps untouched.

- [ ] **Step 2: Verify the start-weight round trip by hand**

Read `_syncUnit` (`:187-196`) and the save path (`:204-209`) and confirm in your report, in your own words, that a value typed into the start-weight field is stored as display units and converted once on save. State explicitly that you did not add `parseDisplay` and why. This is the single most likely place for a silent unit bug.

- [ ] **Step 3: Verify**

```
timeout 200 make -C app analyze > /tmp/t5-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t5-a.log
timeout 400 make -C app test > /tmp/t5-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t5-f.log | tail -4
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/ui/exercise_editor.dart
git commit -m "feat(app): tap-to-type the exercise-editor fields including rest default"
```

---

### Task 6: Opt in the session and history set rows (4 sites)

**Files:**
- Modify: `app/lib/session/set_row.dart` — `:213` (weight, already editable), `:230` (reps)
- Modify: `app/lib/ui/history_screen.dart` — `:1173` (weight, already editable), `:1190` (reps)
- Test: `app/test/session/set_row_overflow_test.dart` (extend)

- [ ] **Step 1: Add the parameters**

Weight sites (`set_row.dart:213`, `history_screen.dart:1173`): keep `editable: true` and `parseDisplay: UnitService.toKg(...)` exactly as they are — these hold **kg** and genuinely need the conversion. Add `min: 0` only (no max: a heavy lifter's ceiling is not ours to pick).

Reps sites (`set_row.dart:230`, `history_screen.dart:1190`): add `editable: true, allowDecimal: false, min: 0,`. Do **not** add a max — the current +/- behaviour is unbounded above and changing that is out of scope.

- [ ] **Step 2: Extend the overflow test**

`app/test/session/set_row_overflow_test.dart` already renders `SetRow` at 300px and asserts `tester.takeException()` is null. A `TextField` now enters those flex rows when editing, so add a case that taps into the weight field and re-asserts no overflow while the field is open:

```dart
  testWidgets('working set does not overflow while typing', (tester) async {
    await tester.pumpWidget(/* the existing 300px wrapper from this file */);
    await tester.pumpAndSettle();

    // Open the inline editor on the weight column.
    await tester.tap(find.byType(WStepper).first);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```
Reuse this file's existing wrapper verbatim rather than writing a new one — it already supplies `wrapL10n` and the `UnitService` provider.

- [ ] **Step 3: Verify**

```
timeout 200 make -C app test TEST=test/session/set_row_overflow_test.dart > /tmp/t6.log 2>&1; echo "EXIT=$?"; tail -12 /tmp/t6.log
timeout 200 make -C app analyze > /tmp/t6-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t6-a.log
timeout 400 make -C app test > /tmp/t6-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t6-f.log | tail -4
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/session/set_row.dart app/lib/ui/history_screen.dart app/test/session/set_row_overflow_test.dart
git commit -m "feat(app): tap-to-type reps and bound the set-row steppers"
```

---

### Task 7: Opt in targets and the global rest steppers (3 sites)

**Files:**
- Modify: `app/lib/ui/targets_tab.dart` — `:140`
- Modify: `app/lib/ui/profile_screen.dart` — `:760`, `:775`

- [ ] **Step 1: Add the parameters**

| Site | Add |
|---|---|
| `targets_tab.dart:140` weekly sets | `editable: true, allowDecimal: false, min: 0, max: 40, emptyValue: 0, formatForEdit: (v) => v.round() == 0 ? '' : v.round().toString(),` |
| `profile_screen.dart:760` compound rest | `editable: true, allowDecimal: false, min: 0, formatForEdit: (v) => v.round().toString(),` — **no `emptyValue`** |
| `profile_screen.dart:775` isolation rest | same as above |

Why the asymmetry: targets renders `'—'` at 0 meaning "no goal" (and 0 deletes the row), so clearing the field must be able to reach 0. The two profile rest steppers have **no sentinel** — their format is a bare `'${v.round()}s'` — so an empty field must mean "no change"; committing 0 there would silently set "no rest" with no visual cue that a sentinel was involved. All three need `formatForEdit` because all three formats carry a suffix or a glyph.

Note both profile setters (`settings_service.dart:144-157`) are unclamped and have no max today; `min: 0` preserves current behaviour without inventing a ceiling.

- [ ] **Step 2: Verify**

```
timeout 200 make -C app test TEST=test/ui/targets_tab_test.dart > /tmp/t7.log 2>&1; echo "EXIT=$?"; tail -10 /tmp/t7.log
timeout 200 make -C app analyze > /tmp/t7-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t7-a.log
timeout 400 make -C app test > /tmp/t7-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t7-f.log | tail -4
```
`test/ui/targets_tab_test.dart:16` taps `find.byIcon(Icons.add).first` and expects `('chest', 13)` — that must still pass unchanged.

- [ ] **Step 3: Commit**

```bash
git add app/lib/ui/targets_tab.dart app/lib/ui/profile_screen.dart
git commit -m "feat(app): tap-to-type weekly targets and the global rest defaults"
```

---

### Task 8: Bodyweight sheet inline edit

**Files:**
- Modify: `app/lib/ui/add_weight_sheet.dart`
- Test: `app/test/ui/add_weight_sheet_test.dart` (new)

The sheet is not a `WStepper` — it is two 56px round buttons flanking a 52px display-font number (`_RoundButton` at `:246`, `_bump` at `:84`, the value `Text` at `:188`). Keep that layout; make the number tappable.

- [ ] **Step 1: Fix the banned parse calls first**

`add_weight_sheet.dart:51` and `:77` use `double.parse`. Both parse `toStringAsFixed` output so neither can realistically throw, but `double.parse` is the call that caused the project's worst data-visibility bug and must not survive in a file being edited. Replace with `double.tryParse(...) ?? <the pre-rounding value>`:

```dart
    // line 51
    _val = double.tryParse(
            UnitService.fromKg(70.0, Unit.kg).toStringAsFixed(1)) ??
        70.0;
```
```dart
    // line 77
    final rounded = display.toStringAsFixed(1);
    setState(() {
      _val = double.tryParse(rounded) ?? display;
    });
```
Also `_bump` (`:84-91`) uses `double.parse` on `toStringAsFixed(2)` — replace it the same way, falling back to the unrounded `next`.

- [ ] **Step 2: Add the inline editor**

Add to `_AddWeightSheetState`:

```dart
  bool _editing = false;
  TextEditingController? _editCtrl;
  final FocusNode _focusNode = FocusNode();
```

with `initState` adding `_focusNode.addListener(_onFocusChange)` and `dispose` removing it and disposing both. Mirror Task 3's exit paths — focus loss, IME done, `deactivate`, and the inset-collapse check via `WidgetsBindingObserver.didChangeMetrics` with the same `_sawKeyboard` arming. Commit through the shared helper so the semantics match the stepper exactly:

```dart
  void _commitEdit() {
    if (!_editing) return;
    final committed = parseNumberInput(_editCtrl?.text ?? '', min: 0);
    setState(() {
      _editing = false;
      if (committed != null) _val = committed;
    });
    // dispose the controller after the frame, as in the stepper
  }
```

Replace the value `Text` at `:188` with a tap target that swaps to a `TextField` while editing, keeping the same `WorkoutType.display(size: 52, weight: FontWeight.w700, letterSpacing: 52 * -0.03)` style so the number does not jump, `textAlign: TextAlign.center`, `keyboardType: const TextInputType.numberWithOptions(decimal: true)`, `textInputAction: TextInputAction.done`, and the same `withFunction` formatter as the stepper. Seed the field with `_val.toStringAsFixed(1)` and select all. Leave the separate unit label span and both `_RoundButton`s exactly as they are.

- [ ] **Step 3: Write the test**

Create `app/test/ui/add_weight_sheet_test.dart`. The sheet reads the global `db` in `_seedFromLastEntry`, so use the `dbForTests` seam (`app/lib/sync/db.dart`) with a temp `PowerSyncDatabase`, following `app/test/ui/progress_screen_target_test.dart`'s setUp/tearDown exactly, and provide `UnitService` inside `wrapL10n`. Assert: tapping the number opens a field seeded with the current value; typing `81.4` and submitting shows `81.4`; typing a negative clamps to `0`; and the kg path stores what was typed. **Do not use a fixed `Future.delayed`** — use `pumpUntilFound` from `app/test/support/pump_until.dart` if you must wait for the seed query.

- [ ] **Step 4: Verify**

```
timeout 200 make -C app test TEST=test/ui/add_weight_sheet_test.dart > /tmp/t8.log 2>&1; echo "EXIT=$?"; tail -15 /tmp/t8.log
timeout 200 make -C app analyze > /tmp/t8-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t8-a.log
timeout 400 make -C app test > /tmp/t8-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t8-f.log | tail -4
```

- [ ] **Step 5: Commit**

```bash
git add app/lib/ui/add_weight_sheet.dart app/test/ui/add_weight_sheet_test.dart
git commit -m "feat(app): type the bodyweight value directly and drop double.parse"
```

---

### Task 9: Perceptible, consistent haptics

**Files:**
- Modify: `app/lib/widgets/stepper.dart` (`:120`)
- Modify: `app/lib/ui/add_weight_sheet.dart` (`_bump`)
- Modify: `app/lib/widgets/rir_picker.dart`
- Modify: the rest-timer `+30s` handler (find it in `app/lib/session/rest_timer.dart` / `app/lib/session/active_session_screen.dart`)

`+`/`−` **already** fires `HapticFeedback.selectionClick()` at `stepper.dart:120`. That maps to Android's `CLOCK_TICK`, the faintest constant, and is suppressed entirely when system touch-vibration is off — which is why it reads as absent next to the set-done checkbox's `mediumImpact`/`heavyImpact` (`set_row.dart:150-155`).

- [ ] **Step 1: Make the changes**

- `stepper.dart:120`: `HapticFeedback.selectionClick()` → `HapticFeedback.lightImpact()`.
- In `_commitEdit`, fire `HapticFeedback.lightImpact()` when a value was actually committed (inside the `if (committed != null)` branch), so typing and stepping feel alike.
- `add_weight_sheet.dart` `_bump`: add `HapticFeedback.lightImpact()`, and the same on a committed typed value. Needs `import 'package:flutter/services.dart';` — check it is not already imported.
- `rir_picker.dart`: fire `HapticFeedback.lightImpact()` in the segment tap handler, before `onChanged`.
- The `+30s` control: same, in its tap handler. Do **not** touch the rest-countdown haptics at `active_session_screen.dart:106,110` — those are a different signal (a tick and an end-of-rest buzz) and are deliberately distinct.

No settings toggle — the platform already owns that preference.

- [ ] **Step 2: Verify**

Haptics cannot be asserted in a widget test (no observable side effect in the tree), so this task's gate is analyze plus no regression:

```
timeout 200 make -C app analyze > /tmp/t9-a.log 2>&1; echo "EXIT=$?"; tail -6 /tmp/t9-a.log
timeout 400 make -C app test > /tmp/t9-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed|^Failing" /tmp/t9-f.log | tail -4
```
State plainly in your report that perceptibility is device-verified, not tested.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/stepper.dart app/lib/ui/add_weight_sheet.dart app/lib/widgets/rir_picker.dart app/lib/session
git commit -m "feat(app): perceptible haptics on every numeric control"
```

---

### Task 10: Documentation, version bump and release

**Files:**
- Modify: `app/CLAUDE.md`
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Update the stepper rule in `app/CLAUDE.md`**

The existing rule reads "Steppers (`WStepper`) hold values in the CALLER's space (kg); `format` converts to display units; typed input converts back via `parseDisplay`." Extend it with what this increment establishes, in the file's existing dense voice:
- the widget clamps locally via `min`/`max`, so a parent clamp is belt-and-braces rather than the only bound;
- `formatForEdit` is REQUIRED on any site whose `format` emits a suffix or sentinel, or typed input silently no-ops;
- `emptyValue` is what lets a sentinel ("Default", "—") be typed back, and must only be set where a sentinel actually exists;
- exercise-editor start weight is the one weight stepper held in DISPLAY units, so it must not get `parseDisplay`;
- do NOT change `didUpdateWidget` to compare `_internalValue` — it makes any unrelated rebuild clobber an in-flight value;
- `FilteringTextInputFormatter.allow` with an anchored pattern wipes the field; use `TextInputFormatter.withFunction`.

- [ ] **Step 2: Bump the version**

`app/pubspec.yaml` line 4: `version: 0.13.0+29`

```bash
git add app/CLAUDE.md app/pubspec.yaml
git commit -m "chore(app): bump version to 0.13.0"
```

- [ ] **Step 3: Final verification**

```
timeout 200 make -C app analyze > /tmp/t10-a.log 2>&1; echo "EXIT=$?"; tail -5 /tmp/t10-a.log
timeout 400 make -C app test > /tmp/t10-f.log 2>&1; echo "EXIT=$?"; grep -E "All tests passed|Some tests failed" /tmp/t10-f.log | tail -2
timeout 900 make -C app build > /tmp/t10-b.log 2>&1; echo "BUILD=$?"; tail -3 /tmp/t10-b.log
```
The Linux release build is this project's compile smoke test (it builds the PowerSync native libs).

- [ ] **Step 4: Adversarial whole-branch review, then merge and tag**

Request a whole-branch review on the most capable model. Press hardest on: whether any site's `min`/`max` contradicts its parent clamp in a way that makes a value untypeable; whether the four commit paths can double-emit or emit after dispose; and whether the start-weight site double-converts units.

Then push the branch, open a PR so `app-ci` runs (its `push` trigger is scoped to main, so a branch push alone runs nothing), merge `--no-ff` with `(v0.13.0)` in the subject once green, and tag `v0.13.0`. **Ask the user before pushing or tagging** — tagging publishes a signed APK publicly.

- [ ] **Step 5: Device verification (none of this is provable in CI)**

- The Android numeric keypad's action key commits.
- **Dismissing the keyboard keeps the typed value** — the reported defect.
- Tapping another field commits the first.
- Typing in a session set row survives the row collapsing to its done state.
- Clearing the per-exercise rest field shows "Default"; clearing a weekly target shows "—".
- Start weight in lb mode: type `176`, save, reopen — it must still read `176`, not `80` or `388`.
- The `lightImpact` haptic is actually perceptible.
- The editable rows do not overflow at the device's font scale.

---

## Self-Review

**Spec coverage:** §1 API additions → Tasks 2, 3. §2 commit-on-every-exit → Task 3. §3 shared helper → Task 1. §4 call sites → Tasks 4, 5, 6, 7 (17 sites: 4+6+4+3). §5 bodyweight sheet → Task 8. §6 haptics → Task 9. §7 the rejected `didUpdateWidget` change → Task 2 Step 3 plus its regression test. §8 existing bugs (controller disposal, `onChanged` timing, input filtering) → Tasks 2 and 3. §9 l10n (no ARB edits) → Global Constraints. §10 testing → distributed. §11 risks → Task 3 (deactivate) and Task 10 Step 5 (lb precision). §12 release → Task 10.

**Type consistency:** `parseNumberInput` and `clampRound2` keep the Task 1 signatures wherever used (Tasks 2, 3, 8). `WStepper`'s five new params keep the Task 2 names and types at every call site in Tasks 4-7. `min` is a non-nullable `double` defaulting to 0; `max`/`emptyValue`/`formatForEdit` are nullable.

**Known soft spots, stated rather than hidden:**
- Task 4's widget test may not be mountable if `_SlotRow`'s public host needs a database; the task explicitly permits reporting that instead of faking one.
- `inputType['decimal']` has no in-SDK precedent as an assertion; Task 2 requires reporting the observed literal.
- Sites 1/3 already round-trip imprecisely in lb mode because `fmtWt` rounds to whole pounds (`unit_service.dart:50-52`). Pre-existing, accepted, listed as a device check rather than silently inherited.
