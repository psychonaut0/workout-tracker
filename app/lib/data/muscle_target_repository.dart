import 'package:powersync/powersync.dart' show PowerSyncDatabase, uuid;

import 'models.dart';

/// Default weekly set targets by muscle group.
const _defaults = [
  ('quads', 16),
  ('back', 14),
  ('hamstrings', 12),
  ('chest', 12),
  ('shoulders', 12),
  ('biceps', 10),
  ('calves', 9),
  ('triceps', 9),
];

/// Repository for muscle_targets — targets per muscle group for the weekly
/// volume bars.
class MuscleTargetRepository {
  final PowerSyncDatabase db;

  const MuscleTargetRepository(this.db);

  /// A live stream of all muscle targets ordered alphabetically by muscle.
  Stream<List<MuscleTarget>> watchTargets() {
    return db
        .watch(
          'SELECT id, muscle, target_sets FROM muscle_targets ORDER BY muscle',
        )
        .map((rs) => rs.map(MuscleTarget.fromRow).toList());
  }

  /// Inserts the 8 default muscle targets for [userId] if the table is empty.
  ///
  /// The `muscle_targets` table has UNIQUE(user_id, muscle); inserting only
  /// when count=0 prevents duplicates on re-open without needing INSERT OR IGNORE.
  /// If no sessions exist yet (userId is null), seeding is skipped; the
  /// dashboard handles empty targets gracefully.
  Future<void> seedDefaultsIfEmpty(String userId) async {
    final count =
        (await db.get('SELECT COUNT(*) AS n FROM muscle_targets'))['n'] as int?
            ?? 0;
    if (count > 0) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      for (final (muscle, targetSets) in _defaults) {
        await tx.execute(
          'INSERT INTO muscle_targets (id, user_id, muscle, target_sets, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [uuid.v4(), userId, muscle, targetSets, nowIso],
        );
      }
    });
  }
}
