import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A slim danger-tinted card telling the user sync has stopped because the
/// server ended the session. Tapping it starts the sign-in-again flow. It
/// renders nothing while [expired] is false, so it disappears on its own
/// once a login clears the flag.
class SyncPausedBanner extends StatelessWidget {
  const SyncPausedBanner({
    super.key,
    required this.expired,
    required this.onTap,
  });

  final ValueListenable<bool> expired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: expired,
      builder: (context, isExpired, _) {
        if (!isExpired) return const SizedBox.shrink();
        final tokens = context.tokens;
        final l = AppLocalizations.of(context);
        return Semantics(
          button: true,
          label: l.todaySyncPaused,
          onTap: onTap,
          excludeSemantics: true,
          child: PressableScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: tokens.danger.withValues(alpha: 0.12),
                  border: Border.all(color: tokens.danger),
                  borderRadius: BorderRadius.circular(AppRadius.radius),
                ),
                child: Row(
                  children: [
                    Icon(WIcons.cloud, size: 18, color: tokens.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l.todaySyncPaused,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WorkoutType.body(
                          size: 13,
                          weight: FontWeight.w600,
                          color: tokens.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(WIcons.chevron, size: 18, color: tokens.danger),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
