import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../sync/sync_health.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'pressable.dart';

/// A quiet Today card shown only while local changes are at risk (see
/// [SyncHealth.atRisk]). The session-expired banner takes the slot when
/// both apply, so this renders nothing while [expired] is true.
class SyncAtRiskCard extends StatelessWidget {
  const SyncAtRiskCard({
    super.key,
    required this.health,
    required this.expired,
    required this.onTap,
  });

  final SyncHealth health;
  final ValueListenable<bool> expired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([health, expired]),
      builder: (context, _) {
        if (!health.atRisk || expired.value) return const SizedBox.shrink();
        final tokens = context.tokens;
        final l = AppLocalizations.of(context);
        final last = health.lastSyncedAt;
        final text = last == null
            ? l.todaySyncAtRiskNever
            : l.todaySyncAtRisk(DateFormat.MMMd(
                    Localizations.localeOf(context).toString())
                .format(last));
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(
            button: true,
            label: text,
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
                    color: tokens.surface,
                    border: Border.all(color: tokens.line),
                    borderRadius: BorderRadius.circular(AppRadius.radius),
                  ),
                  child: Row(
                    children: [
                      Icon(WIcons.cloud, size: 18, color: tokens.faint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: WorkoutType.body(
                                size: 13, color: tokens.dim)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
