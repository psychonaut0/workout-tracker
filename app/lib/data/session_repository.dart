import 'package:powersync/powersync.dart';

import 'models.dart';

/// Repository for sessions and sets — history reads, last/best top-set lookups.
///
/// Local SQLite CAN JOIN freely; only the PowerSync sync-rules cannot. All
/// JOINs here query the local SQLite DB via [PowerSyncDatabase].
class SessionRepository {
  final PowerSyncDatabase db;

  const SessionRepository(this.db);

  // ── Top-set lookups ───────────────────────────────────────────────────────

  /// Returns the most-recent top set for [exerciseId], optionally restricted
  /// to sessions strictly before [beforeDate] (ISO-8601 date string).
  ///
  /// The `created_at` DESC tie-break makes same-date results deterministic.
  Future<({double weight, int reps, String date})?> lastTopSet(
    String exerciseId, {
    String? beforeDate,
  }) async {
    final String sql;
    final List<Object?> args;

    if (beforeDate != null) {
      sql = '''
        SELECT s.weight_kg, s.reps, se.date
          FROM sets s
          JOIN sessions se ON se.id = s.session_id
         WHERE s.exercise_id = ?
           AND s.is_top_set = 1
           AND s.is_warmup = 0
           AND se.date < ?
         ORDER BY se.date DESC, se.created_at DESC
         LIMIT 1
      ''';
      args = [exerciseId, beforeDate];
    } else {
      sql = '''
        SELECT s.weight_kg, s.reps, se.date
          FROM sets s
          JOIN sessions se ON se.id = s.session_id
         WHERE s.exercise_id = ?
           AND s.is_top_set = 1
           AND s.is_warmup = 0
         ORDER BY se.date DESC, se.created_at DESC
         LIMIT 1
      ''';
      args = [exerciseId];
    }

    final row = await db.getOptional(sql, args);
    if (row == null) return null;

    final wt = row['weight_kg'];
    return (
      weight: wt != null ? double.parse(wt.toString()) : 0.0,
      reps: row['reps'] as int? ?? 0,
      date: row['date'] as String? ?? '',
    );
  }

  /// Returns the all-time best top-set weight (kg) for [exerciseId], or null
  /// if the exercise has never been logged.
  Future<double?> bestTopSet(String exerciseId) async {
    final row = await db.getOptional(
      'SELECT MAX(CAST(weight_kg AS REAL)) AS best '
      'FROM sets WHERE exercise_id = ? AND is_top_set = 1 AND is_warmup = 0',
      [exerciseId],
    );
    if (row == null) return null;
    final best = row['best'];
    if (best == null) return null;
    return (best as num).toDouble();
  }

  // ── Session list ──────────────────────────────────────────────────────────

  /// A live stream of the most-recent [limit] sessions, newest first.
  Stream<List<SessionSummaryRow>> watchRecentSessions({int limit = 30}) {
    return db
        .watch(
          'SELECT id, date, split_label, day_template_id, duration_min '
          'FROM sessions ORDER BY date DESC, created_at DESC LIMIT ?',
          parameters: [limit],
        )
        .map((rs) => rs.map(SessionSummaryRow.fromRow).toList());
  }

  // ── Set reads ─────────────────────────────────────────────────────────────

  /// Returns all sets for a session, in set_number order.
  Future<List<LoggedSet>> setsForSession(String sessionId) async {
    final rows = await db.getAll(
      'SELECT * FROM sets WHERE session_id = ? ORDER BY exercise_id, set_number',
      [sessionId],
    );
    return rows.map(LoggedSet.fromRow).toList();
  }

  /// Groups a flat list of [LoggedSet]s into [ExerciseBlockData] records,
  /// one per unique exercise, in the order they first appear.
  List<ExerciseBlockData> groupIntoBlocks(List<LoggedSet> sets) {
    final order = <String>[];
    final byExercise = <String, List<LoggedSet>>{};

    for (final s in sets) {
      if (!byExercise.containsKey(s.exerciseId)) {
        order.add(s.exerciseId);
        byExercise[s.exerciseId] = [];
      }
      byExercise[s.exerciseId]!.add(s);
    }

    return order.map((exId) {
      final exSets = byExercise[exId]!;
      final workingSets = exSets.where((s) => !s.isWarmup).toList();

      // Top set: the one flagged is_top_set=true by the server; fall back to
      // the set with the highest weight if none is flagged.
      final topSet = workingSets.firstWhere(
        (s) => s.isTopSet,
        orElse: () => workingSets.isEmpty ? exSets.first : workingSets.reduce(
          (a, b) => a.weightKg >= b.weightKg ? a : b,
        ),
      );

      return ExerciseBlockData(
        exerciseId: exId,
        sets: exSets,
        topWeight: topSet.weightKg,
        topReps: topSet.reps,
        isPr: topSet.isPr,
      );
    }).toList();
  }
}
