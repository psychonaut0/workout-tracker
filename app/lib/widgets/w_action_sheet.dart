import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One row in a [showWActionSheet].
class WSheetAction<T> {
  const WSheetAction({
    required this.label,
    required this.value,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData icon;
  final bool destructive;
  final bool enabled;
}

/// Tokens-styled bottom action sheet: a small caps [title] over 56dp rows.
/// Returns the tapped action's value, or null on dismiss. Disabled rows render
/// faint and ignore taps.
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
            for (var i = 0; i < actions.length; i++)
              _row(context, tokens, i, actions[i]),
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
    return Semantics(
      button: true,
      enabled: a.enabled,
      child: GestureDetector(
        key: ValueKey('sheet-action-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: a.enabled ? () => Navigator.of(context).pop(a.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(a.icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    a.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkoutType.body(size: 15, weight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
