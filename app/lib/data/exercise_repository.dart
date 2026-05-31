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
}
