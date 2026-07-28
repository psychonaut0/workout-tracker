import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../util/number_input.dart';

/// A numeric stepper with − / + buttons flanking a formatted value label.
///
/// Values are clamped to ≥ 0. Button taps call [onChanged] with the new value
/// and do NOT bubble to enclosing widgets (stopPropagation via [GestureDetector]
/// with [HitTestBehavior.opaque]).
///
/// The stepper maintains an internal copy of [value] so that consecutive taps
/// without a parent-triggered rebuild still compound correctly (each tap steps
/// from the *previous tap's* value, not the last-rendered [value]).
///
/// Visual spec: `docs/design_handoff_workout_tracker/design/app/screen-log.jsx`
/// `Stepper`.
class WStepper extends StatefulWidget {
  const WStepper({
    super.key,
    required this.value,
    required this.step,
    required this.format,
    required this.onChanged,
    this.editable = false,
    this.parseDisplay,
    this.formatForEdit,
    this.min = 0,
    this.max,
    this.emptyValue,
    this.allowDecimal = true,
  });

  final double value;
  final double step;

  /// Formats the current value for display.
  final String Function(double) format;

  final ValueChanged<double> onChanged;

  /// When true, tapping the value label opens an inline text field so the user
  /// can type a value directly.
  final bool editable;

  /// Converts a typed value (in display space, as produced by [format]) back to
  /// the internal value space. When null, the typed value is used as-is.
  final double Function(double display)? parseDisplay;

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

  @override
  State<WStepper> createState() => _WStepperState();
}

class _WStepperState extends State<WStepper> {
  late double _internalValue;

  /// Direction of the most recent value change, used to slide the label in the
  /// direction of change (true = value went up).
  bool _up = true;

  bool _editing = false;
  TextEditingController? _editCtrl;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.value;
  }

  @override
  void dispose() {
    _editCtrl?.dispose();
    super.dispose();
  }

  void _beginEdit() {
    if (!widget.editable) return;
    final initial = (widget.formatForEdit ?? widget.format)(_internalValue);
    _editCtrl = TextEditingController(text: initial);
    _editCtrl!.selection =
        TextSelection(baseOffset: 0, extentOffset: _editCtrl!.text.length);
    setState(() => _editing = true);
  }

  void _commitEdit() {
    if (!_editing) return;
    final previous = _internalValue;
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
    // Skip onChanged when the edit produced no actual change — e.g. an edit
    // where every keystroke was rejected by the input formatter (below)
    // reverts to the pre-edit text, which still parses to a valid number and
    // must not be mistaken for a genuine commit.
    if (committed != null && committed != previous) widget.onChanged(committed);
    _editCtrl?.dispose();
    _editCtrl = null;
  }

  @override
  void didUpdateWidget(WStepper old) {
    super.didUpdateWidget(old);
    // Keep internal value in sync when the parent provides a new value
    // (e.g. after an undo or external reset).
    if (widget.value != old.value) {
      _up = widget.value > old.value;
      _internalValue = widget.value;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final buttonDecoration = BoxDecoration(
      color: tokens.surface3,
      borderRadius: BorderRadius.circular(AppRadius.radius * 0.4),
    );

    Widget btn({
      required Key key,
      required IconData icon,
      required int dir,
    }) {
      return GestureDetector(
        key: key,
        // Stop tap from propagating to parent (e.g. accordion header).
        behavior: HitTestBehavior.opaque,
        onTap: () => _step(dir),
        child: Container(
          width: 25,
          height: 34,
          decoration: buttonDecoration,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: tokens.text),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        btn(key: const Key('stepper-dec'), icon: Icons.remove, dir: -1),
        const SizedBox(width: 4),
        Expanded(
          child: Center(
            child: _editing
                ? Focus(
                    onFocusChange: (f) {
                      if (!f) _commitEdit();
                    },
                    child: TextField(
                      controller: _editCtrl,
                      autofocus: true,
                      textAlign: TextAlign.center,
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
                          // A leading '-' is allowed through (no on-screen
                          // numeric keypad exposes one, but callers/tests can
                          // still supply it) so a negative value reaches
                          // clampRound2/parseNumberInput and gets clamped to
                          // [min], instead of being wiped by the formatter.
                          final ok = widget.allowDecimal
                              ? RegExp(r'^-?\d*[.,]?\d*$')
                                  .hasMatch(newValue.text)
                              : RegExp(r'^-?\d*$').hasMatch(newValue.text);
                          return ok ? newValue : oldValue;
                        }),
                      ],
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
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _beginEdit,
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: Offset(0, _up ? 0.4 : -0.4),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        widget.format(_internalValue),
                        key: ValueKey(widget.format(_internalValue)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.mono(
                          size: 15,
                          weight: FontWeight.w700,
                          color: tokens.text,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        btn(key: const Key('stepper-inc'), icon: Icons.add, dir: 1),
      ],
    );
  }
}
