import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'fit_label.dart';

/// One row in a [showWActionSheet].
class WSheetAction<T> {
  const WSheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.selected = false,
    this.labelLocale,
  });

  final String label;
  final T value;

  /// The leading icon; a row without one is text only.
  final IconData? icon;
  final bool destructive;
  final bool enabled;

  /// The current choice: a trailing check, and a selected semantics state.
  final bool selected;

  /// The language [label] is written in, when it isn't the UI's (a language
  /// named in its own language), so a screen reader voices it in that one.
  final Locale? labelLocale;
}

/// Tokens-styled bottom action sheet: a small caps [title] over 56dp rows.
/// Returns the tapped action's value, or null on dismiss. Disabled rows render
/// faint and ignore taps. The title stays put and the rows scroll when they
/// outgrow the sheet (a six-row menu on a short phone at large text).
Future<T?> showWActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<WSheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _WActionSheetBody<T>(title: title, actions: actions),
  );
}

class _WActionSheetBody<T> extends StatelessWidget {
  const _WActionSheetBody({required this.title, required this.actions});

  final String title;
  final List<WSheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.radius),
          border: Border.all(color: tokens.lineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Text(
                title,
                style: WorkoutType.mono(
                    size: 10.5, color: tokens.faint, letterSpacing: 0.08 * 10.5),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      _row(context, tokens, i, actions[i]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WorkoutTokens tokens, int i, WSheetAction<T> a) {
    final color = !a.enabled
        ? tokens.line
        : a.destructive
            ? tokens.danger
            : tokens.text;
    final icon = a.icon;
    final row = Semantics(
      button: true,
      enabled: a.enabled,
      selected: a.selected ? true : null,
      child: GestureDetector(
        key: ValueKey('sheet-action-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: a.enabled ? () => Navigator.of(context).pop(a.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          // The vertical inset only shows on a two-line label: one line stays
          // under the 56dp floor up to 2.0x text.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: FitLabel(
                    a.label,
                    maxLines: 2,
                    style: WorkoutType.body(size: 15, weight: FontWeight.w600, color: color),
                  ),
                ),
                if (a.selected) ...[
                  const SizedBox(width: 14),
                  Icon(WIcons.check, size: 20, color: tokens.accentText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // A separate outer node only sets the language: on the row's own
    // Semantics it would split the tap off the button.
    final locale = a.labelLocale;
    return locale == null ? row : Semantics(localeForSubtree: locale, child: row);
  }
}
