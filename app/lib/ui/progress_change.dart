import '../data/models.dart';
import '../l10n/app_localizations.dart';

/// The kind of change between a previous and a current top set.
///
/// A weight change always wins; a rep-only change is reported only when
/// the weight is unchanged (within [_weightTolerance]).
sealed class TopSetChange {
  const TopSetChange();
}

/// The weight moved by [delta] kg (display units, via the caller's `fmtVal`).
class WeightChange extends TopSetChange {
  const WeightChange(this.delta);
  final double delta;
}

/// The weight held steady but the rep count moved by [delta].
class RepChange extends TopSetChange {
  const RepChange(this.delta);
  final int delta;
}

/// Neither the weight nor the reps moved.
class NoChange extends TopSetChange {
  const NoChange();
}

const double _weightTolerance = 1e-6;

/// Compares a previous top set to the current one and decides what to show.
TopSetChange topSetChange({
  required double prevWeight,
  required int? prevReps,
  required double curWeight,
  required int? curReps,
}) {
  final weightDelta = curWeight - prevWeight;
  if (weightDelta.abs() > _weightTolerance) {
    return WeightChange(weightDelta);
  }
  if (prevReps != null && curReps != null && prevReps != curReps) {
    return RepChange(curReps - prevReps);
  }
  return const NoChange();
}

/// A signed value string: "+x", "−x" (U+2212), or [AppLocalizations.progressSame]
/// when `fmtVal(delta.abs())` formats the same as `fmtVal(0)` — i.e. [delta]
/// is exactly zero, or rounds away to nothing under the caller's formatter.
String signedChange(double delta, String Function(double) fmtVal, AppLocalizations l) {
  final abs = fmtVal(delta.abs());
  if (abs == fmtVal(0)) return l.progressSame;
  return delta > 0 ? '+$abs' : '−$abs';
}

/// Renders a [TopSetChange] as the label shown in Progress's change column.
///
/// - [WeightChange]: `fmtVal` of the absolute delta, prefixed with the sign
///   and suffixed with [unit] when non-empty (no space before the unit).
/// - [RepChange]: the localized "+N rep(s)" / "−N rep(s)" string.
/// - [NoChange]: [AppLocalizations.progressSame].
String changeLabel(
  AppLocalizations l,
  TopSetChange c, {
  required String Function(double) fmtVal,
  String unit = '',
}) {
  switch (c) {
    case WeightChange(:final delta):
      final abs = fmtVal(delta.abs());
      final sign = delta > 0 ? '+$abs' : '−$abs';
      return unit.isEmpty ? sign : '$sign$unit';
    case RepChange(:final delta):
      final signed = delta > 0 ? '+$delta' : '−${-delta}';
      return l.progressRepDelta(delta.abs(), signed);
    case NoChange():
      return l.progressSame;
  }
}

/// Picks the exercise Progress should open on.
///
/// Returns [lastTrainedId] when it names an exercise still in [catalog];
/// otherwise (no history, or the last-trained exercise was since deleted)
/// falls back to the first catalog entry, or `null` if the catalog is empty.
String? defaultProgressExercise(String? lastTrainedId, List<Exercise> catalog) {
  if (lastTrainedId != null) {
    for (final e in catalog) {
      if (e.id == lastTrainedId) return lastTrainedId;
    }
  }
  return catalog.isEmpty ? null : catalog.first.id;
}
