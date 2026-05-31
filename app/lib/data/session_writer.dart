import 'package:sqlite_async/sqlite_async.dart';

// ── SqlExecutor abstraction ───────────────────────────────────────────────────

/// Minimal write-only SQL interface used by [persistSession].
///
/// The production implementation wraps a PowerSync `SqliteWriteContext`
/// (obtained from `db.writeTransaction`). The test implementation ([FakeExec])
/// records calls without touching any database.
abstract class SqlExecutor {
  Future<void> execute(String sql, [List<Object?> params = const []]);
}

/// Production executor: wraps a PowerSync `SqliteWriteContext` so the entire
/// session + all sets commit as a single local transaction (and are uploaded as
/// one CRUD batch). The caller runs:
///
/// ```dart
/// await db.writeTransaction(
///   (tx) => persistSession(PowerSyncTxExecutor(tx), write),
/// );
/// ```
class PowerSyncTxExecutor implements SqlExecutor {
  final SqliteWriteContext _tx;

  const PowerSyncTxExecutor(this._tx);

  @override
  Future<void> execute(String sql, [List<Object?> params = const []]) async {
    await _tx.execute(sql, params);
  }
}

// ── Data transfer objects ─────────────────────────────────────────────────────

/// Describes one set to be persisted at session finish.
class SetWrite {
  final String id;
  final String exerciseId;
  final int setNumber;

  /// Weight stored as TEXT (e.g. `'60.00'`) — consistent with the schema rule
  /// that NUMERIC columns are TEXT on the client.
  final String weightKg;

  final int reps;

  /// RIR is null for warm-up sets (not persisted; the server leaves it NULL).
  final int? rir;

  final bool isWarmup;

  const SetWrite({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.isWarmup,
  });
}

/// Describes one session to be persisted at session finish.
class SessionWrite {
  final String id;
  final String dateIso;
  final String? dayTemplateId;
  final String? splitLabel;
  final int? durationMin;
  final List<SetWrite> sets;

  const SessionWrite({
    required this.id,
    required this.dateIso,
    this.dayTemplateId,
    this.splitLabel,
    this.durationMin,
    required this.sets,
  });
}

// ── persistSession ────────────────────────────────────────────────────────────

/// Writes [write] to the database via [executor]: one `sessions` INSERT +
/// one `sets` INSERT per set.
///
/// The server stamps `user_id` and recomputes `is_top_set`/`is_pr`; this
/// function never writes those columns.
///
/// **Atomicity:** always call this inside `db.writeTransaction` via
/// [PowerSyncTxExecutor]; that ensures the session row and all set rows commit
/// as one local transaction and are uploaded as one CRUD batch.
Future<void> persistSession(SqlExecutor executor, SessionWrite write) async {
  // 1. Insert the session row.
  await executor.execute(
    'INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      write.id,
      write.dateIso,
      write.dayTemplateId,
      write.splitLabel,
      write.durationMin,
    ],
  );

  // 2. Insert each set.
  for (final s in write.sets) {
    await executor.execute(
      'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        s.id,
        write.id,
        s.exerciseId,
        s.setNumber,
        s.weightKg, // TEXT — never cast here; the schema maps NUMERIC → text
        s.reps,
        s.isWarmup ? null : s.rir, // warm-up RIR → null
        s.isWarmup ? 1 : 0,
      ],
    );
  }
}
