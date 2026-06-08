/// Formats a duration as `M:SS` (or `H:MM:SS` past an hour). Shared by the
/// in-progress indicator and the Today resume hero.
String fmtClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
