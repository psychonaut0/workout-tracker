import 'dart:math';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../util/dates.dart';

// ── Dashed-border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const double strokeWidth = 1.0;
  static const double dashLength = 6.0;
  static const double gapLength = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    // Approximate the perimeter as a path and dash it.
    final path = Path()..addRRect(rrect);
    final dashPath = _dashPath(path, dashLength, gapLength);
    canvas.drawPath(dashPath, paint);
  }

  static Path _dashPath(Path source, double dash, double gap) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = min(distance + dash, metric.length);
        out.addPath(
          metric.extractPath(distance, end),
          Offset.zero,
        );
        distance += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ── DaySlide ──────────────────────────────────────────────────────────────────

/// One page of the split-picker pager showing a single day template.
///
/// [index] is the slide's position among all slides (0-based).
/// [nextIndex] is the rotation target so the eyebrow can be keyed off it.
class DaySlide extends StatelessWidget {
  const DaySlide({
    super.key,
    required this.day,
    required this.exerciseCount,
    required this.lastAgo,
    required this.index,
    required this.nextIndex,
  });

  final DayTemplate day;
  final int exerciseCount;
  final String lastAgo;

  /// Position of this slide within the full slides list.
  final int index;

  /// Index of the rotation target (passed through from [SplitCard]).
  final int nextIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Eyebrow keyed off the rotation target, NOT literal index 0.
    final isNext = index == nextIndex;
    final eyebrow = isNext
        ? 'NEXT IN ROTATION'
        : 'SWITCH TO · ${(day.scheduledWeekday != null ? weekdayShort(day.scheduledWeekday!) : day.name).toUpperCase()}';

    // Estimated time: max(20, (exerciseCount * 9 + 10).round())m
    final est = max(20, exerciseCount * 9 + 10);

    final accentInk = tokens.accentInk;
    // Sub-accent: accentInk @ ~58% (matching cd: color-mix(in srgb, accent-ink 58%))
    final accentDim = accentInk.withValues(alpha: 0.58);

    return Stack(
      children: [
        // Decorative dumbbell — day slides only, positioned top-right.
        // Positioned at the edge; clip is handled by the parent PageView.
        Positioned(
          right: -28,
          top: -28,
          child: IgnorePointer(
            child: Icon(
              WIcons.dumbbell,
              size: 150,
              color: accentInk.withValues(alpha: 0.08),
            ),
          ),
        ),
        // Content column
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Eyebrow
            Text(
              eyebrow,
              style: WorkoutType.mono(
                size: 11,
                weight: FontWeight.w700,
                color: accentDim,
                letterSpacing: 11 * 0.1,
              ),
            ),
            const SizedBox(height: 10),
            // Name
            Text(
              day.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkoutType.display(
                size: 40,
                weight: FontWeight.w700,
                color: accentInk,
                letterSpacing: 40 * -0.03,
              ),
            ),
            // Focus
            if (day.focus != null && day.focus!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                day.focus!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkoutType.display(
                  size: 19,
                  weight: FontWeight.w600,
                  color: accentDim,
                  letterSpacing: 19 * -0.025,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                _StatCol(
                  value: '$exerciseCount',
                  label: 'Exercises',
                  valueColor: accentInk,
                  labelColor: accentDim,
                ),
                const SizedBox(width: 18),
                _StatCol(
                  value: '~${est}m',
                  label: 'Est. time',
                  valueColor: accentInk,
                  labelColor: accentDim,
                ),
                const SizedBox(width: 18),
                _StatCol(
                  value: lastAgo.isEmpty ? '—' : lastAgo,
                  label: 'Last',
                  valueColor: accentInk,
                  labelColor: accentDim,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
  });

  final String value;
  final String label;
  final Color valueColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: WorkoutType.mono(
            size: 16,
            weight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: WorkoutType.mono(
            size: 9.5,
            color: labelColor,
            letterSpacing: 9.5 * 0.06,
          ),
        ),
      ],
    );
  }
}

// ── CustomSlide ───────────────────────────────────────────────────────────────

/// The final page of the split-picker pager for a free-form custom session.
class CustomSlide extends StatelessWidget {
  const CustomSlide({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textColor = tokens.text;
    final dimColor = tokens.dim;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow
        Text(
          'NO TEMPLATE',
          style: WorkoutType.mono(
            size: 11,
            weight: FontWeight.w700,
            color: dimColor,
            letterSpacing: 11 * 0.1,
          ),
        ),
        const SizedBox(height: 10),
        // Name
        Text(
          'Custom',
          style: WorkoutType.display(
            size: 40,
            weight: FontWeight.w700,
            color: textColor,
            letterSpacing: 40 * -0.03,
          ),
        ),
        const SizedBox(height: 4),
        // Sub
        Text(
          'Build it as you go',
          style: WorkoutType.display(
            size: 19,
            weight: FontWeight.w600,
            color: dimColor,
            letterSpacing: 19 * -0.025,
          ),
        ),
        const SizedBox(height: 18),
        // Hint row
        Row(
          children: [
            Icon(WIcons.plus, size: 17, color: dimColor),
            const SizedBox(width: 9),
            Text(
              'Add exercises live during the session',
              style: WorkoutType.mono(
                size: 12,
                weight: FontWeight.w600,
                color: dimColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── SplitCard ─────────────────────────────────────────────────────────────────

/// The hero split-picker pager on the Today dashboard.
///
/// Renders a [PageView] of [DaySlide]s plus a final [CustomSlide].
/// The card body animates between accent (day slides) and surface (custom slide)
/// over 250 ms. A fixed Start button sits below the pager inside the card.
/// Dots + left/right arrows sit below the card on the app background.
class SplitCard extends StatefulWidget {
  const SplitCard({
    super.key,
    required this.days,
    required this.nextIndex,
    required this.onStart,
  });

  /// Day slides data. Each entry carries the template, exercise count, and
  /// a human-readable "last trained" label (e.g. '3d ago' or '—').
  final List<({DayTemplate day, int exerciseCount, String lastAgo})> days;

  /// Index (within [days]) of the rotation target.
  ///
  /// The pager opens on this slide. The eyebrow on the matching slide reads
  /// 'NEXT IN ROTATION'; all others read 'SWITCH TO · {WEEKDAY}'.
  final int nextIndex;

  /// Called when the user taps Start.
  ///
  /// Receives the selected [DayTemplate], or `null` if the Custom slide is
  /// active (meaning the user wants an empty free-form session).
  final void Function(DayTemplate?) onStart;

  @override
  State<SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends State<SplitCard> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.nextIndex.clamp(0, widget.days.length);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _totalSlides => widget.days.length + 1; // days + Custom

  bool get _isCustom => _currentPage >= widget.days.length;

  void _goTo(int page) {
    final target = page.clamp(0, _totalSlides - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.ease,
    );
  }

  void _onStart() {
    if (_isCustom) {
      widget.onStart(null);
    } else {
      widget.onStart(widget.days[_currentPage].day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // Animated card theming: accent bg (day) ↔ surface bg (custom)
    final cardBg = _isCustom ? tokens.surface : tokens.accent;

    // Start button colours
    final btnBg = _isCustom ? tokens.accent : tokens.accentInk;
    final btnInk = _isCustom ? tokens.accentInk : tokens.accent;
    final btnIcon = _isCustom ? WIcons.plus : WIcons.bolt;
    final btnLabel = _isCustom ? 'Start empty' : 'Start workout';

    return Column(
      children: [
        // ── Card body ────────────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.radius),
            // Custom slide shows a dashed border; day slides have no border.
          ),
          child: Stack(
            children: [
              // Dashed border overlay for Custom slide
              if (_isCustom)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DashedBorderPainter(
                      color: tokens.lineStrong,
                      radius: AppRadius.radius,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.pad + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Pager ────────────────────────────────────────────────
                    SizedBox(
                      // Fixed height to keep the card stable as slides scroll.
                      height: 180,
                      child: ClipRect(
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _totalSlides,
                          onPageChanged: (page) {
                            setState(() => _currentPage = page);
                          },
                          itemBuilder: (context, i) {
                            if (i < widget.days.length) {
                              final entry = widget.days[i];
                              return DaySlide(
                                day: entry.day,
                                exerciseCount: entry.exerciseCount,
                                lastAgo: entry.lastAgo,
                                index: i,
                                nextIndex: widget.nextIndex,
                              );
                            }
                            return const CustomSlide();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // ── Start button ─────────────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.ease,
                      height: 52,
                      decoration: BoxDecoration(
                        color: btnBg,
                        borderRadius: BorderRadius.circular(
                          AppRadius.radius * 0.8,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _onStart,
                          borderRadius: BorderRadius.circular(
                            AppRadius.radius * 0.8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(btnIcon, size: 18, color: btnInk),
                              const SizedBox(width: 8),
                              Text(
                                btnLabel,
                                style: WorkoutType.display(
                                  size: 17,
                                  weight: FontWeight.w700,
                                  color: btnInk,
                                  letterSpacing: 17 * 0.01,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Dots + arrows (below card, on app bg) ───────────────────────────
        const SizedBox(height: 13),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left arrow
            _ArrowButton(
              icon: WIcons.chevron,
              flip: true,
              enabled: _currentPage > 0,
              onTap: () => _goTo(_currentPage - 1),
            ),
            const SizedBox(width: 12),
            // Pill dots
            Row(
              children: List.generate(_totalSlides, (i) {
                final active = i == _currentPage;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.ease,
                    width: active ? 18.0 : 6.0,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? tokens.accent : tokens.lineStrong,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(width: 12),
            // Right arrow
            _ArrowButton(
              icon: WIcons.chevron,
              flip: false,
              enabled: _currentPage < _totalSlides - 1,
              onTap: () => _goTo(_currentPage + 1),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Arrow button ─────────────────────────────────────────────────────────────

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.flip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool flip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final child = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.line),
        color: tokens.surface,
      ),
      child: Center(
        child: Transform.scale(
          scaleX: flip ? -1 : 1,
          child: Icon(
            icon,
            size: 15,
            color: enabled ? tokens.dim : tokens.faint,
          ),
        ),
      ),
    );

    if (!enabled) {
      return Opacity(opacity: 0.4, child: child);
    }

    return GestureDetector(onTap: onTap, child: child);
  }
}
