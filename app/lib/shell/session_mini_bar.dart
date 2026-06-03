import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';
import '../widgets/pressable.dart';

/// Docked "workout in progress" pill shown by the shell while a session is
/// active but its screen is minimized. Ticks elapsed time; swaps to an accent
/// rest countdown while resting. Tap → reopen the session screen.
class SessionMiniBar extends StatefulWidget {
  const SessionMiniBar({
    super.key,
    required this.name,
    required this.startedAt,
    required this.restStart,
    required this.restTotal,
    required this.onTap,
  });

  final String name;
  final DateTime startedAt;
  final DateTime? restStart;
  final int restTotal;
  final VoidCallback onTap;

  @override
  State<SessionMiniBar> createState() => _SessionMiniBarState();
}

class _SessionMiniBarState extends State<SessionMiniBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();

    int restRemaining = 0;
    final restStart = widget.restStart;
    if (restStart != null) {
      restRemaining = widget.restTotal - now.difference(restStart).inSeconds;
      if (restRemaining < 0) restRemaining = 0;
    }
    final resting = restRemaining > 0;

    return Reveal(
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: PressableScale(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: tokens.lineStrong),
            ),
            child: Row(
              children: [
                Icon(WIcons.dumbbell, size: 15, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkoutType.mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: tokens.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  resting
                      ? 'Rest ${_fmt(Duration(seconds: restRemaining))}'
                      : _fmt(now.difference(widget.startedAt)),
                  style: WorkoutType.mono(
                    size: 13,
                    weight: FontWeight.w700,
                    color: resting ? tokens.accent : tokens.dim,
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
