import 'package:powersync/powersync.dart';

import 'models.dart';

/// Repository for the exercises table (template catalog + custom exercises).
///
/// All methods accept the app-wide [PowerSyncDatabase] injected at construction.
class ExerciseRepository {
  final PowerSyncDatabase db;

  const ExerciseRepository(this.db);

  /// A live stream of all exercises, ordered by name.
  ///
  /// Emits a new list on every local DB change (sync down, user edits).
  Stream<List<Exercise>> watchCatalog() {
    return db
        .watch('SELECT * FROM exercises ORDER BY name')
        .map((rs) => rs.map(Exercise.fromRow).toList());
  }

  /// Fetches a single exercise by id, or null if not found.
  Future<Exercise?> byId(String id) async {
    final row = await db
        .getOptional('SELECT * FROM exercises WHERE id = ?', [id]);
    return row == null ? null : Exercise.fromRow(row);
  }

  /// One-shot fetch of all exercises (for pickers, etc.).
  Future<List<Exercise>> all() async {
    final rows = await db.getAll('SELECT * FROM exercises ORDER BY name');
    return rows.map(Exercise.fromRow).toList();
  }

  /// Returns a map of exercise_id → all-time best top-set weight (kg).
  ///
  /// Mirrors [SessionRepository.bestTopSet] but returns all exercises at once
  /// for the library list (avoids N per-exercise queries).
  Future<Map<String, double>> prTopSets() async {
    final rows = await db.getAll(
      'SELECT exercise_id, MAX(CAST(weight_kg AS REAL)) AS pr '
      'FROM sets WHERE is_top_set = 1 AND is_warmup = 0 GROUP BY exercise_id',
    );
    return {
      for (final r in rows)
        r['exercise_id'] as String: (r['pr'] as num?)?.toDouble() ?? 0,
    };
  }
}
