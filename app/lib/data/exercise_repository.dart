import 'package:powersync/powersync.dart';

import 'models.dart';

// ── slugify ───────────────────────────────────────────────────────────────────

/// Converts [name] to a URL-safe slug: lowercase, non-alphanum → `-`, trim `-`.
String slugify(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'exercise' : s;
}

/// Returns a collision-proof slug by appending the first 8 chars of [id].
///
/// Using the UUID prefix makes the slug globally unique without querying the
/// server: `slugify(name) + '-' + id.substring(0, 8)`.
String uniqueSlug(String name, String id) {
  return '${slugify(name)}-${id.substring(0, 8)}';
}

// ── exerciseUpsertOp ─────────────────────────────────────────────────────────

/// Pure builder: returns the SQL + args for an exercise INSERT or UPDATE.
///
/// - INSERT when [existingId] is null (uses [newId] + [slug]).
/// - UPDATE when [existingId] is non-null (targets that id; slug not changed).
///
/// Value rules (mirror bodyweightUpsertOp pattern):
/// - [ExerciseDraft.baseWeightKg] null → `''` (server NULLIF keeps NULL);
///   non-null → `toStringAsFixed(2)`.
/// - [ExerciseDraft.plateStepKg] always `toStringAsFixed(2)`.
/// - [ExerciseDraft.compound] → `0`/`1`.
/// - OMIT user_id / created_at / is_template (server stamps/forces).
({String sql, List<Object?> args}) exerciseUpsertOp(
  String? existingId,
  String newId,
  ExerciseDraft d,
  String slug,
) {
  final baseWt = d.baseWeightKg == null ? '' : d.baseWeightKg!.toStringAsFixed(2);
  final plateStep = d.plateStepKg.toStringAsFixed(2);
  final compound = d.compound ? 1 : 0;
  final equip = d.equip ?? '';

  if (existingId == null) {
    return (
      sql: 'INSERT INTO exercises '
          '(id, slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg, '
          'default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, '
          'default_rir_low, default_rir_high) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        newId,
        slug,
        d.name,
        d.muscleGroup,
        equip,
        compound,
        baseWt,
        plateStep,
        d.defaultRepLow,
        d.defaultRepHigh,
        d.defaultWarmupSets,
        d.defaultWorkingSets,
        d.defaultRirLow,
        d.defaultRirHigh,
      ],
    );
  } else {
    return (
      sql: 'UPDATE exercises SET '
          'name = ?, muscle_group = ?, equip = ?, compound = ?, base_weight_kg = ?, '
          'plate_step_kg = ?, default_rep_low = ?, default_rep_high = ?, '
          'default_warmup_sets = ?, default_working_sets = ?, '
          'default_rir_low = ?, default_rir_high = ? '
          'WHERE id = ?',
      args: [
        d.name,
        d.muscleGroup,
        equip,
        compound,
        baseWt,
        plateStep,
        d.defaultRepLow,
        d.defaultRepHigh,
        d.defaultWarmupSets,
        d.defaultWorkingSets,
        d.defaultRirLow,
        d.defaultRirHigh,
        existingId,
      ],
    );
  }
}

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

  /// Creates a new custom exercise from [draft].
  ///
  /// Generates a collision-proof slug (`slugify(name)+'-'+id.substring(0,8)`)
  /// then writes via a single [db.writeTransaction].
  Future<String> createExercise(ExerciseDraft draft) async {
    final id = uuid.v4();
    final slug = uniqueSlug(draft.name, id);
    await db.writeTransaction((tx) async {
      final op = exerciseUpsertOp(null, id, draft, slug);
      await tx.execute(op.sql, op.args);
    });
    return id;
  }

  /// Updates an existing owned exercise by [id] from [draft].
  ///
  /// Slug is not changed on update (server does not accept slug changes).
  Future<void> updateExercise(String id, ExerciseDraft draft) async {
    await db.writeTransaction((tx) async {
      final op = exerciseUpsertOp(id, id, draft, '');
      await tx.execute(op.sql, op.args);
    });
  }
}
