import 'package:powersync/powersync.dart';

/// Given raw `sets` rows, return the ids to stamp is_top_set=1: for each
/// (session, exercise) group with NO non-warmup set already flagged, the
/// heaviest non-warmup set (tie-break weight DESC, reps DESC, set_number ASC,
/// id ASC). weight_kg is TEXT → compare numerically.
Set<String> topSetIdsToStamp(List<Map<String, Object?>> rows) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final key = '${r['session_id']}|${r['exercise_id']}';
    (groups[key] ??= []).add(r);
  }
  final out = <String>{};
  for (final g in groups.values) {
    final working = g.where((r) => (r['is_warmup'] as int? ?? 0) == 0).toList();
    if (working.isEmpty) continue;
    if (working.any((r) => (r['is_top_set'] as int? ?? 0) == 1)) continue;
    Map<String, Object?>? best;
    for (final r in working) {
      if (best == null) { best = r; continue; }
      final rw = double.tryParse(r['weight_kg']?.toString() ?? '') ?? 0;
      final bw = double.tryParse(best['weight_kg']?.toString() ?? '') ?? 0;
      final rr = r['reps'] as int? ?? 0, br = best['reps'] as int? ?? 0;
      final rn = r['set_number'] as int? ?? 0, bn = best['set_number'] as int? ?? 0;
      final rid = r['id'] as String, bid = best['id'] as String;
      if (rw > bw ||
          (rw == bw && rr > br) ||
          (rw == bw && rr == br && rn < bn) ||
          (rw == bw && rr == br && rn == bn && rid.compareTo(bid) < 0)) {
        best = r;
      }
    }
    out.add(best!['id'] as String);
  }
  return out;
}

/// One-time, idempotent backfill of is_top_set for existing local sessions
/// (no-op once every group already has a top set). Safe to run every launch.
Future<void> backfillTopSets(PowerSyncDatabase db) async {
  final rows = await db.getAll(
    'SELECT id, session_id, exercise_id, weight_kg, reps, set_number, is_warmup, is_top_set FROM sets');
  final ids = topSetIdsToStamp(rows.map((r) => Map<String, Object?>.from(r)).toList());
  if (ids.isEmpty) return;
  await db.writeTransaction((tx) async {
    for (final id in ids) {
      await tx.execute('UPDATE sets SET is_top_set = 1 WHERE id = ?', [id]);
    }
  });
}
