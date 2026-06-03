import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/shell/back_dispatch.dart';

void main() {
  test('a tab that handled back wins (stay put)', () {
    expect(decideBack(tabHandled: true, tabIndex: 3), BackAction.none);
  });
  test('non-home tab goes home', () {
    for (final i in [1, 2, 3]) {
      expect(decideBack(tabHandled: false, tabIndex: i), BackAction.goHome);
    }
  });
  test('home exits', () {
    expect(decideBack(tabHandled: false, tabIndex: 0), BackAction.exit);
  });
}
