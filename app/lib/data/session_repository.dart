import 'package:powersync/powersync.dart';

import 'models.dart';

// ── Mutation builders (pure) ──────────────────────────────────────────────────
//
// These build the SQL + args for editing logged history. They never touch
// is_top_set / is_pr — the server recomputes those on sync.

({String sql, List<Object?> args}) updateSetOp(String id,
        {required String weightKg, required int reps, required int? rir}) =>
    (
      sql: 'UPDATE sets SET weight_kg = ?, reps = ?, rir = ? WHERE id = ?',
      args: [weightKg, reps, rir, id]
    );

({String sql, List<Object?> args}) deleteSetOp(String id) =>
    (sql: 'DELETE FROM sets WHERE id = ?', args: [id]);

({String sql, List<Object?> args}) deleteSessionOp(String id) =>
    (sql: 'DELETE FROM sessions WHERE id = ?', args: [id]);

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

  // ── User id ───────────────────────────────────────────────────────────────

  /// Returns the user_id from any synced session row, or null if no sessions
  /// exist yet.  Used to seed per-user data (e.g. muscle targets) when an
  /// auth identity is not threaded through the widget tree.
  Future<String?> anyUserId() async =>
      (await db.getOptional('SELECT user_id FROM sessions LIMIT 1'))?['user_id']
          as String?;

  // ── Session list ──────────────────────────────────────────────────────────

  /// A live stream of all sessions with aggregated stats (exercise count,
  /// PR count, tonnage), ordered newest first.
  ///
  /// Uses a LEFT JOIN so sessions with no sets still appear. `pr_count` counts
  /// distinct exercises where any set is a PR. `tonnage` excludes warm-up sets.
  Stream<List<HistorySessionRow>> watchSessionStats() => db.watch(
        '''SELECT se.id, se.date, se.split_label, se.duration_min,
                  COUNT(DISTINCT s.exercise_id) AS ex_count,
                  COUNT(DISTINCT CASE WHEN s.is_pr = 1 THEN s.exercise_id END) AS pr_count,
                  COALESCE(SUM(CASE WHEN s.is_warmup = 0 THEN CAST(s.weight_kg AS REAL) * s.reps ELSE 0 END), 0) AS tonnage
             FROM sessions se LEFT JOIN sets s ON s.session_id = se.id
            GROUP BY se.id, se.date, se.split_label, se.duration_min
            ORDER BY se.date DESC''',
      ).map((rs) => rs.map(HistorySessionRow.fromRow).toList());

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

  // ── Edit / delete (history) ───────────────────────────────────────────────

  /// Updates a single set's weight/reps/rir. Never writes is_top_set/is_pr —
  /// the server recomputes those on sync.
  Future<void> updateSet(
    String id, {
    required String weightKg,
    required int reps,
    required int? rir,
  }) async {
    final op = updateSetOp(id, weightKg: weightKg, reps: reps, rir: rir);
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }

  /// Deletes a single set by id.
  Future<void> deleteSet(String id) async {
    final op = deleteSetOp(id);
    await db.writeTransaction((tx) => tx.execute(op.sql, op.args));
  }

  /// Deletes a whole session and its sets.
  Future<void> deleteSession(String id) async {
    await db.writeTransaction((tx) async {
      await tx.execute(
          'DELETE FROM sets WHERE session_id = ?', [id]); // clean local view
      await tx.execute('DELETE FROM sessions WHERE id = ?', [id]);
    });
  }
}
