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

  final bool isTopSet;

  final bool isPr;

  const SetWrite({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.isWarmup,
    this.isTopSet = false,
    this.isPr = false,
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

// ── Top set ───────────────────────────────────────────────────────────────────

/// Index into [sets] of the top set for ONE exercise: heaviest non-warmup set,
/// tie-break weight DESC, reps DESC, set_number ASC, id ASC (mirrors the server).
/// Returns -1 if there is no non-warmup set. weightKg is TEXT → compare numerically.
int topSetIndex(List<SetWrite> sets) {
  var best = -1;
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];
    if (s.isWarmup) continue;
    if (best == -1) { best = i; continue; }
    final b = sets[best];
    final sw = double.tryParse(s.weightKg) ?? 0;
    final bw = double.tryParse(b.weightKg) ?? 0;
    if (sw > bw ||
        (sw == bw && s.reps > b.reps) ||
        (sw == bw && s.reps == b.reps && s.setNumber < b.setNumber) ||
        (sw == bw && s.reps == b.reps && s.setNumber == b.setNumber && s.id.compareTo(b.id) < 0)) {
      best = i;
    }
  }
  return best;
}

// ── persistSession / replaceSession ───────────────────────────────────────────

/// The session INSERT. The training day is bound through a subquery so a day
/// deleted locally (mid-workout, or while a finished workout was resumed)
/// becomes NULL instead of an id the server's day_templates foreign key would
/// reject — a rejected session PUT makes the server skip every set PUT of the
/// batch as an orphan, and the whole workout then vanishes on sync-down.
const _insertSessionSql =
    'INSERT INTO sessions (id, date, day_template_id, split_label, duration_min) '
    'SELECT ?, ?, (SELECT id FROM day_templates WHERE id = ?), ?, ?';

List<Object?> _sessionArgs(SessionWrite w) =>
    [w.id, w.dateIso, w.dayTemplateId, w.splitLabel, w.durationMin];

Future<void> _insertSets(SqlExecutor executor, SessionWrite write) async {
  for (final s in write.sets) {
    await executor.execute(
      'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, rir, is_warmup, is_top_set, is_pr) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        s.id,
        write.id,
        s.exerciseId,
        s.setNumber,
        s.weightKg, // TEXT — never cast here; the schema maps NUMERIC → text
        s.reps,
        s.isWarmup ? null : s.rir, // warm-up RIR → null
        s.isWarmup ? 1 : 0,
        s.isTopSet ? 1 : 0,
        s.isPr ? 1 : 0,
      ],
    );
  }
}

/// Writes [write] to the database via [executor]: one `sessions` INSERT + one
/// `sets` INSERT per set.
///
/// The server stamps `user_id`; `is_top_set`/`is_pr` are stamped client-side
/// (see [topSetIndex]) so offline-logged data is correct before sync.
///
/// **Atomicity:** always call this inside `db.writeTransaction` via
/// [PowerSyncTxExecutor]; that ensures the session row and all set rows commit
/// as one local transaction and are uploaded as one CRUD batch.
Future<void> persistSession(SqlExecutor executor, SessionWrite write) async {
  await executor.execute(_insertSessionSql, _sessionArgs(write));
  await _insertSets(executor, write);
}

/// Replaces an already-finished session in place — finishing a resumed
/// workout: same session id and date, a new set of sets.
///
/// The session row is UPDATEd, never deleted. Uploaded as a PATCH of
/// `split_label`/`duration_min` only, it cannot be rejected by the server;
/// a DELETE + re-INSERT would instead lose the whole, already-synced workout
/// whenever the re-insert PUT is rejected (for example, its training day was
/// deleted since). The guarded INSERT re-creates the row only if it vanished
/// (deleted by a sync during the resumed workout) and otherwise inserts
/// nothing and uploads nothing. The sets are DELETE + INSERT with the same
/// ids, which PowerSync uploads as DELETE then PUT; the server recomputes the
/// top-set and PR flags for both.
///
/// Same atomicity rule as [persistSession].
Future<void> replaceSession(SqlExecutor executor, SessionWrite write) async {
  await executor.execute(
    'UPDATE sessions SET split_label = ?, duration_min = ? WHERE id = ?',
    [write.splitLabel, write.durationMin, write.id],
  );
  await executor.execute(
    '$_insertSessionSql WHERE NOT EXISTS (SELECT 1 FROM sessions WHERE id = ?)',
    [..._sessionArgs(write), write.id],
  );
  await executor.execute('DELETE FROM sets WHERE session_id = ?', [write.id]);
  await _insertSets(executor, write);
}
