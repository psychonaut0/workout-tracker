import 'package:powersync/powersync.dart';

import 'models.dart';

/// Repository for per-exercise progress series — one [ProgressPoint] per
/// session, aggregated from the top set and all working sets.
class ProgressRepository {
  final PowerSyncDatabase db;

  const ProgressRepository(this.db);

  /// A live stream of per-session [ProgressPoint]s for [exerciseId], ordered
  /// oldest-first.
  ///
  /// `top_weight` / `top_reps` / `is_pr` are scoped to the row flagged
  /// `is_top_set=1`; `volume` sums weight×reps across ALL working sets.
  /// Values are kept in kg; the view layer converts to display units.
  Stream<List<ProgressPoint>> watchSeriesFor(String exerciseId) => db.watch(
        '''SELECT se.date AS date,
            MAX(CASE WHEN s.is_top_set=1 THEN CAST(s.weight_kg AS REAL) END) AS top_weight,
            MAX(CASE WHEN s.is_top_set=1 THEN s.reps END) AS top_reps,
            MAX(CASE WHEN s.is_top_set=1 THEN s.is_pr ELSE 0 END) AS is_pr,
            SUM(CAST(s.weight_kg AS REAL) * s.reps) AS volume
       FROM sets s JOIN sessions se ON se.id=s.session_id
      WHERE s.exercise_id = ? AND s.is_warmup = 0
      GROUP BY se.id, se.date ORDER BY se.date ASC, se.created_at ASC''',
        parameters: [exerciseId],
      ).map((rs) => rs.map(ProgressPoint.fromRow).toList());
}
