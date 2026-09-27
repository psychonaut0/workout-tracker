import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/l10n/app_localizations_en.dart';
import 'package:workout_tracker/ui/progress_change.dart';

void main() {
  final l = AppLocalizationsEn();
  String f(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  test('weight change wins when the weight moved', () {
    final c = topSetChange(prevWeight: 100, prevReps: 6, curWeight: 102.5, curReps: 4);
    expect(changeLabel(l, c, fmtVal: f), '+2.5');
  });
  test('equal weight reports the rep change', () {
    final c = topSetChange(prevWeight: 100, prevReps: 6, curWeight: 100, curReps: 7);
    expect(changeLabel(l, c, fmtVal: f), '+1 rep');
    final d = topSetChange(prevWeight: 100, prevReps: 8, curWeight: 100, curReps: 6);
    expect(changeLabel(l, d, fmtVal: f), '−2 reps');
  });
  test('nothing moved reads "same"', () {
    final c = topSetChange(prevWeight: 100, prevReps: 6, curWeight: 100, curReps: 6);
    expect(changeLabel(l, c, fmtVal: f), 'same');
    final n = topSetChange(prevWeight: 100, prevReps: null, curWeight: 100, curReps: null);
    expect(changeLabel(l, n, fmtVal: f), 'same');
  });
  test('negatives use the real minus sign', () {
    final c = topSetChange(prevWeight: 100, prevReps: 6, curWeight: 97.5, curReps: 6);
    expect(changeLabel(l, c, fmtVal: f), '−2.5');
  });
}
