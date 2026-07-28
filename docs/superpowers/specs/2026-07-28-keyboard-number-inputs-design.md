# v0.13.0 — keyboard-editable number inputs and haptics

**Date:** 2026-07-28
**Status:** Approved (design)
**Scope:** Every numeric control in the app becomes typeable, not just +/-. All 17 `WStepper` instances gain tap-to-type; the bodyweight sheet's big ± number becomes tappable. Typed values commit on **every** way of leaving the field, including dismissing the keyboard. Haptics become perceptible and consistent across all numeric controls. Ships as v0.13.0, after the v0.12.16 crash-class fix.

---

## 0. Current state

`WStepper` (`app/lib/widgets/stepper.dart`) already has `editable` and `parseDisplay`, added in the ownership overhaul. They are wired at exactly **two** of 17 call sites — the weight steppers at `session/set_row.dart:217` and `ui/history_screen.dart:1175`. Everything else is +/- only: reps in both of those screens, all four day-editor steppers, all six exercise-editor steppers, weekly targets, and both profile rest steppers.

A plan-editor opt-in did ship once, in v0.12.8, and was removed wholesale by the catalog-crash revert (`0a58737`). `stepper.dart` has not been touched since. Two of that attempt's pieces are worth reusing (`formatForEdit`, opting in the editors) and one is not (see §7).

The visual handoff spec (`docs/design_handoff_workout_tracker/`) is **silent** on typed number entry: its `Stepper` prototype has a plain non-interactive value span, and the only `<input type="number">` in the bundle is in the tweaks panel, which the README marks "prototype scaffolding only (do not port)". So tap-to-type is a deliberate deviation from the handoff — as it already was for weight — and there is no spec-defined "editing" visual state to match. The closest precedent in the bundle is the profile-name inline edit (surface-3 fill, `line-strong` border), which the existing borderless mono field already approximates. Keep the current look.

## 1. `WStepper` API additions

Four new parameters:

| Param | Default | Purpose |
|---|---|---|
| `formatForEdit` | null → falls back to `format` | Bare-number prefill for the edit field. `format` emits `"80kg"`, `"120s"`, `"Default"` and `"—"` at various sites, none of which round-trip through `double.tryParse` — today they would silently discard every edit. |
| `min` | `0` | Lower bound, enforced **inside** the widget. `0` preserves today's floor. |
| `max` | null (unbounded) | Upper bound, enforced inside the widget. |
| `emptyValue` | null | Committing an empty field yields this value. `0` on the three rest steppers and weekly targets, so clearing the field returns to "Default" / "—". Null elsewhere: empty commits nothing and the value is unchanged. |
| `allowDecimal` | `true` | `false` → `TextInputType.number`, digits-only keypad with no separator, for reps / sets / rep ranges. |

`min`/`max` are clamped in **both** `_step` and `_commitEdit`, so stepping and typing agree and the widget never displays a value it did not emit. This is the real fix for the long-standing display-desync bug where a parent clamp that returns a value it already held left the out-of-range number on screen while the clamped value was what got saved.

## 2. Commit on every exit

The reported defect: dismissing the keyboard discards what was typed. Cause — commit currently happens only on `onSubmitted` or focus loss, `textInputAction` is unset (Android numeric IMEs frequently ship no action key at all), and hiding the Android keyboard does **not** drop focus, so the typed text sits in an uncommitted field until something else throws it away.

Every exit path must commit:

| Trigger | Mechanism |
|---|---|
| keyboard done / checkmark | `textInputAction: TextInputAction.done` (currently missing) |
| tap anywhere else | focus loss, via a state-owned `FocusNode` |
| **keyboard dismissed, field still focused** | `WidgetsBindingObserver.didChangeMetrics`: when editing and the bottom view inset collapses to 0 **after having been > 0**, commit and unfocus. Gating on "having been > 0" keeps the check inert on desktop and in widget tests, where insets are always 0. |
| sheet closed, route popped, row recycled | `deactivate()` |

The only input that does not commit is text that is not a number at all.

`_commitEdit` is already re-entrant-safe via its `if (!_editing) return;` guard, which matters now that four paths can call it.

## 3. Shared parse/clamp helper

Extract the value semantics into one pure function (`app/lib/util/number_input.dart`) so the stepper and the bodyweight sheet cannot drift apart, and so the semantics are unit-testable without pumping a widget:

- trim, and normalise `,` → `.` (Italian/German/Spanish keyboards produce a comma)
- `double.tryParse` — **never** `double.parse`; the project's hardest-won rule
- empty → `emptyValue` if provided, otherwise "no change"
- apply `parseDisplay` to convert display space → caller space
- clamp to `[min, max]`, then round to 2 decimals

## 4. Call sites

All 17 steppers opt in, each with real bounds so the widget clamps locally instead of relying on a parent round-trip. Parent clamps stay as belt-and-braces and because some own cross-field rules.

| Site | Bounds | Notes |
|---|---|---|
| `session/set_row.dart:213` weight | ≥0 | already editable; gains bounds |
| `session/set_row.dart:230` reps | ≥0, integer | `allowDecimal: false` |
| `history_screen.dart:1171` weight | ≥0 | already editable |
| `history_screen.dart:1188` reps | ≥0, integer | |
| `day_editor.dart:628` work sets | 1–99, integer | |
| `day_editor.dart:640` warmups | 0–99, integer | |
| `day_editor.dart:657` rep low | 1–99, integer | parent still bumps rep high |
| `day_editor.dart:669` rep high | `repLow`–99, integer | dynamic `min` |
| `exercise_editor.dart:483` start weight | ≥0 | `formatForEdit: fmtPlain` — `format` bakes in the unit label |
| `exercise_editor.dart:506` rep low | 1–99, integer | |
| `exercise_editor.dart:524` rep high | `repLow`–99, integer | |
| `exercise_editor.dart:544` work sets | 1–99, integer | |
| `exercise_editor.dart:558` warmups | 0–99, integer | |
| `exercise_editor.dart:575` rest | ≥0, integer, `emptyValue: 0` | `format` emits `"Default"`/`"90s"` → `formatForEdit` returns `''` for 0, else the bare number; clearing the field means "Default" |
| `targets_tab.dart:134` weekly sets | 0–40, integer, `emptyValue: 0` | `format` emits `"—"` for 0 → `formatForEdit` returns `''` for 0; clearing means "no goal", which deletes the row |
| `profile_screen.dart:760` compound rest | ≥0, integer, **no `emptyValue`** | `format` emits `"120s"` → needs `formatForEdit`. No sentinel exists here, so an empty field must mean "no change"; committing 0 would silently set "no rest" |
| `profile_screen.dart:775` isolation rest | ≥0, integer, **no `emptyValue`** | same |

The three sites with a sentinel need `emptyValue`; the two profile rest steppers have no sentinel and deliberately do not get one. `emptyValue` is what makes the standing "rest stepper can't be typed back to Default" item finally work — the v0.12.8 attempt prefilled `''` but had no way to commit an empty field, so the value was unreachable.

Every site whose `format` emits anything other than a bare number needs `formatForEdit`: `exercise_editor.dart:483` (unit label), `exercise_editor.dart:575` and `profile_screen.dart:760,775` (seconds suffix), `targets_tab.dart:134` (em-dash sentinel). The remaining twelve already format bare numbers and need nothing.

## 5. Bodyweight sheet

`ui/add_weight_sheet.dart` is not a `WStepper` — it is two 56px round buttons flanking a 52px display-font number. Keep that layout; make the number tappable, opening an inline field in the same display font, sharing §3's semantics and §2's commit paths. Bounds ≥0, decimals allowed, existing 0.1kg / 0.2lb steps unchanged.

While in this file, replace `double.parse` at `:51` and `:77` with `double.tryParse` plus a fallback. Both currently parse `toStringAsFixed(1)` output so neither can realistically throw, but `double.parse` is the banned call that caused the worst data-visibility bug in the project's history, and it should not survive in a file being edited anyway.

## 6. Haptics

`+`/`−` **already** fires `HapticFeedback.selectionClick()` (`stepper.dart:120`). That constant maps to Android's `CLOCK_TICK`, the faintest available, and is suppressed entirely when system touch-vibration is off — which is why it reads as "no haptic" next to the set-done checkbox's `mediumImpact`/`heavyImpact` (`set_row.dart:150-155`).

- Stepper `+`/`−` → `HapticFeedback.lightImpact()`: clearly perceptible, still subtle enough for twenty consecutive taps while ramping weight, and not dependent on the CLOCK_TICK path.
- Fire the same on a **committed typed value**, so typing and stepping feel alike.
- Add it to the three numeric controls that have none today: the bodyweight sheet's ± (`add_weight_sheet.dart:173,207`), the RIR segments (`widgets/rir_picker.dart`), and the rest timer's `+30s`.

No settings toggle — the platform already owns that preference.

## 7. Deliberately not doing: the `didUpdateWidget` change

The v0.12.8 attempt also changed the resync guard from `widget.value != old.value` to `widget.value != _internalValue`. **Do not re-land that.** The internal copy exists so consecutive taps compound without waiting for a parent rebuild (documented at `stepper.dart:14-16`). Comparing against `_internalValue` makes *any* rebuild from *any* source — `context.watch<UnitService>()`, a sibling `setState`, a stream tick — snap the label back to the parent's prop, so any parent that debounces or async-saves visibly loses the user's in-flight value. The existing stepper test only passes because it fires two taps with no `pump()` between them.

That change was a workaround for the missing bounds. §1 fixes the same symptom at the cause, so the guard stays as it is — and §10 pins the behaviour the change would have broken.

## 8. Existing bugs fixed in passing

- **Controller disposed while mounted.** `_commitEdit` calls `setState(() => _editing = false)` and then *synchronously* `_editCtrl?.dispose(); _editCtrl = null;`. The still-mounted `TextField` holds a disposed controller until the next frame, and `controller:` transitioning to null mid-life is itself illegal. Own a single controller for the state's lifetime, or dispose after the frame.
- **Inconsistent `onChanged` timing.** `_step` calls it outside the `setState` closure, `_commitEdit` inside. Make both call it outside, after the state update.
- **No input filtering.** Letters, `-`, `e` and multiple separators are typeable and then silently dropped. Restrict input to digits plus at most one separator (and no separator at all when `allowDecimal: false`), so the field cannot hold text that will be discarded.

## 9. Localization

No new user-visible strings: `formatForEdit` produces bare numbers or empty text, sentinels reuse the existing `exerciseEditorRestDefault` and the `'—'` literal, and the field has no hint or label. The ARB parity test stays green with no ARB edits.

## 10. Testing

`app/test/widgets/stepper_input_test.dart` has five tests today; extend it, and note that no test currently renders `ExerciseEditor`, `DayEditor`, `HistoryScreen` or `ProfileScreen` at all.

**Stepper:** `formatForEdit` prefills a bare number for a suffixed display; typed values clamp to `max` and to `min`; stepped values clamp the same way; an empty field commits `emptyValue` where set and changes nothing where not; `allowDecimal: false` yields an integer keyboard type and rejects a separator; commit fires via IME action, via focus loss, via a simulated view-inset collapse, and via `deactivate` when a route is popped mid-edit; non-numeric text reverts without firing `onChanged`; comma decimals parse; `parseDisplay` round-trips a lb value back to kg.

**Regression guard:** an unrelated parent rebuild must not clobber an in-flight stepped or typed value — the behaviour §7's rejected change would have broken.

**Pure helper:** the §3 function, table-driven over separators, empties, bounds and rounding.

**Bodyweight sheet:** tap the number, type, commit; kg and lb; the `double.tryParse` fallbacks.

**Layout:** re-check `set_row_overflow_test.dart` at 300px now that a `TextField` enters those flex rows, and add first render tests for the day and exercise editors asserting no overflow with the editable steppers present.

## 11. Risks

- **Committing in `deactivate()`** calls the parent's `onChanged` during teardown, which can reach `setState` on an unmounting widget. Covered by the route-pop test. If it proves unworkable, the fallback is committing on every parseable keystroke — bulletproof, but it emits intermediate values (typing `150` emits 1, 15, 99) into the session write path, which feeds top-set and PR computation. Not the default for that reason.
- **lb precision.** `UnitService.fmtWt` rounds lb to whole pounds, so typing `220.5` lb displays as `221` after commit even though the stored kg is exact. Pre-existing display behaviour, accepted, not changed here.
- **Weight step is in kg even in lb mode** (a lb user steps 5.51 lb per tap). Pre-existing, out of scope, recorded so it is not mistaken for a regression introduced by this work.

## 12. Release

Branch off main after v0.12.16 is merged, TDD per section, adversarial review, `--no-ff` merge whose subject carries `(v0.13.0)`, then tag. Bump `app/pubspec.yaml` to `0.13.0+29` in its own commit first.

**Device verification before tagging** (none of it provable in CI): the Android numeric keypad's action key commits; **dismissing the keyboard keeps the typed value**; tapping another field commits the first; typing in a session set row survives the row collapsing to its done state; the `lightImpact` haptic is actually perceptible on the phone; the editable rows do not overflow at the device's font scale.
