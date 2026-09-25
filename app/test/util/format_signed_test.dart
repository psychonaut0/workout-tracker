import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/format.dart';

void main() {
  test('fmtSigned signs gains and losses with a true minus, and zero plain', () {
    expect(fmtSigned(0.3), '+0.3');
    expect(fmtSigned(-1), '−1');
    expect(fmtSigned(-1.04), '−1');
    expect(fmtSigned(0), '0');
    expect(fmtSigned(-0.04), '0'); // rounds to zero → unsigned
  });
}
