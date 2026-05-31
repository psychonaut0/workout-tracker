import 'package:powersync/powersync.dart';

import '../util/dates.dart';

/// Repository for aggregate stats derived from sets + sessions.
///
/// All week-bounded queries accept a [weekStart] (Monday 00:00) and bind
/// its ISO-8601 string via the NAMED `parameters:` argument — consistent
/// with [PowerSyncDatabase.watch]'s API.  The scalar streams map the
/// first row's `n` column; the list streams use the nested `.map` pattern.
class StatsRepository {
  final PowerSyncDatabase db;

  const StatsRepository(this.db);

  // ── Scalar week-bounded counts ────────────────────────────────────────────

  /// Live count of working sets logged since [weekStart] (Monday of current week).
  Stream<int> watchSetsThisWeek({required DateTime weekStart}) {
    return db
        .watch(
          'SELECT COUNT(*) AS n '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'WHERE s.is_warmup = 0 AND se.date >= ?',
          parameters: [isoDate(weekStart)],
        )
        .map((rs) => rs.first['n'] as int? ?? 0);
  }

  /// Live count of distinct muscle groups trained since [weekStart].
  Stream<int> watchDistinctMusclesThisWeek({required DateTime weekStart}) {
    return db
        .watch(
          'SELECT COUNT(DISTINCT ex.muscle_group) AS n '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'JOIN exercises ex ON ex.id = s.exercise_id '
          'WHERE s.is_warmup = 0 AND se.date >= ?',
          parameters: [isoDate(weekStart)],
        )
        .map((rs) => rs.first['n'] as int? ?? 0);
  }

  /// Live count of PR sets logged since [weekStart].
  Stream<int> watchPrsThisWeek({required DateTime weekStart}) {
    return db
        .watch(
          'SELECT COUNT(*) AS n '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'WHERE s.is_pr = 1 AND se.date >= ?',
          parameters: [isoDate(weekStart)],
        )
        .map((rs) => rs.first['n'] as int? ?? 0);
  }

  // ── List streams ──────────────────────────────────────────────────────────

  /// Live stream of the most-recent [limit] PR sets, newest session first.
  ///
  /// `weight_kg` is TEXT on the client; the CAST produces a real value
  /// aliased as `weight`.
  Stream<List<({String exerciseId, double weight, int reps, String date})>>
      watchRecentPrs({int limit = 6}) {
    return db
        .watch(
          'SELECT s.exercise_id, CAST(s.weight_kg AS REAL) AS weight, '
          's.reps, se.date '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'WHERE s.is_pr = 1 AND s.is_warmup = 0 '
          'ORDER BY se.date DESC, se.created_at DESC '
          'LIMIT ?',
          parameters: [limit],
        )
        .map(
          (rs) => rs
              .map(
                (row) => (
                  exerciseId: row['exercise_id'] as String,
                  weight: (row['weight'] as num).toDouble(),
                  reps: row['reps'] as int? ?? 0,
                  date: row['date'] as String,
                ),
              )
              .toList(),
        );
  }

  /// Live stream of working-set volume by muscle group since [weekStart].
  Stream<List<({String muscle, int sets})>> watchWeeklyVolumeByMuscle({
    required DateTime weekStart,
  }) {
    return db
        .watch(
          'SELECT ex.muscle_group AS muscle, COUNT(*) AS sets '
          'FROM sets s '
          'JOIN sessions se ON se.id = s.session_id '
          'JOIN exercises ex ON ex.id = s.exercise_id '
          'WHERE s.is_warmup = 0 AND se.date >= ? '
          'GROUP BY ex.muscle_group '
          'ORDER BY sets DESC',
          parameters: [isoDate(weekStart)],
        )
        .map(
          (rs) => rs
              .map(
                (row) => (
                  muscle: row['muscle'] as String,
                  sets: row['sets'] as int? ?? 0,
                ),
              )
              .toList(),
        );
  }
}
