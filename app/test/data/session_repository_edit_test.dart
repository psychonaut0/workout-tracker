import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/session_repository.dart';

void main() {
  test('updateSetOp builds an UPDATE with weight/reps/rir', () {
    final op = updateSetOp('set-1', weightKg: '82.50', reps: 5, rir: 1);
    expect(op.sql, contains('UPDATE sets SET'));
    expect(op.sql, contains('weight_kg'));
    expect(op.sql, contains('WHERE id = ?'));
    expect(op.args, ['82.50', 5, 1, 'set-1']);
  });
  test('deleteSetOp targets the id', () {
    final op = deleteSetOp('set-9');
    expect(op.sql, 'DELETE FROM sets WHERE id = ?');
    expect(op.args, ['set-9']);
  });
  test('deleteSessionOp targets the id', () {
    final op = deleteSessionOp('sess-3');
    expect(op.sql, 'DELETE FROM sessions WHERE id = ?');
    expect(op.args, ['sess-3']);
  });
}
