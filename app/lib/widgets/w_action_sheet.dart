import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/typography.dart';

/// One action item in a [showWActionSheet].
class WSheetAction<T> {
  const WSheetAction({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final T value;
  final IconData icon;
}

/// Tokens-styled bottom action sheet. Returns the tapped action's value, or
/// null on barrier dismiss.
Future<T?> showWActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<WSheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _WActionSheetBody<T>(title: title, actions: actions),
  );
}

class _WActionSheetBody<T> extends StatelessWidget {
  const _WActionSheetBody({
    required this.title,
    required this.actions,
  });

  final String title;
  final List<WSheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: tokens.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Text(
                title,
                style: WorkoutType.display(size: 18, color: tokens.text),
              ),
            ),
            for (final action in actions)
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(action.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(action.icon, color: tokens.dim, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          action.label,
                          style: WorkoutType.body(
                            size: 16,
                            color: tokens.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SizedBox(height: safeBottom + 8),
          ],
        ),
      ),
    );
  }
}
