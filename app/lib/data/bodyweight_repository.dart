import 'package:powersync/powersync.dart';

import 'models.dart';

/// Repository for bodyweight_logs — read-only (write path deferred).
class BodyweightRepository {
  final PowerSyncDatabase db;

  const BodyweightRepository(this.db);

  /// A live stream of all bodyweight entries ordered oldest-first.
  ///
  /// `weight_kg` is stored as TEXT on the client; the CAST produces a real
  /// value aliased as `weight` so [BodyweightEntry.fromRow] can read it.
  Stream<List<BodyweightEntry>> watchSeriesAsc() {
    return db
        .watch(
          'SELECT date, CAST(weight_kg AS REAL) AS weight '
          'FROM bodyweight_logs ORDER BY date ASC',
        )
        .map((rs) => rs.map(BodyweightEntry.fromRow).toList());
  }
}
