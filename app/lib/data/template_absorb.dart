import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:uuid/uuid.dart';

import 'exercise_repository.dart' show uniqueSlug;

/// Fixed namespace for deterministic absorb ids — never change this value.
const _absorbNamespace = '7d9f0a3c-4b2e-4f81-9c5d-1e6a8b0f2d47';

/// The owned copy's id for template [templateId] under user [userId].
/// Deterministic: same inputs → same id on every boot and every device,
/// which is the entire idempotency mechanism of the absorb migration.
String absorbCopyId(String userId, String templateId) =>
    const Uuid().v5(_absorbNamespace, '$userId:$templateId');

typedef AbsorbOp = ({String sql, List<Object?> args});

/// Builds the SQL ops that absorb synced template rows into user-owned rows:
/// owned copies (deterministic ids, ownership stamped) + reference rewrites
/// (sets.exercise_id, day_template_items.exercise_id, sessions.day_template_id).
/// Pure: rows in, ops out. Templates whose copy id is in [existingIds] are
/// skipped (already absorbed — possibly by another device).
List<AbsorbOp> absorbOps({
  required String userId,
  required List<Map<String, Object?>> templateExercises,
  required List<Map<String, Object?>> templateDays,
  required List<Map<String, Object?>> templateItems,
  required Set<String> existingIds,
  required String nowIso,
}) {
  final ops = <AbsorbOp>[];

  // Map EVERY template exercise id → its copy id (items re-point through this
  // even for exercises absorbed on an earlier boot — the template rows keep
  // syncing down, so they're always in [templateExercises]).
  final exCopyIds = {
    for (final e in templateExercises)
      e['id'] as String: absorbCopyId(userId, e['id'] as String),
  };

  for (final e in templateExercises) {
    final oldId = e['id'] as String;
    final copyId = exCopyIds[oldId]!;
    if (existingIds.contains(copyId)) continue;
    ops.add((
      sql: 'INSERT INTO exercises '
          '(id, slug, name, muscle_group, equip, compound, base_weight_kg, plate_step_kg, '
          'default_rep_low, default_rep_high, default_warmup_sets, default_working_sets, '
          'default_rir_low, default_rir_high, is_template, created_by, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        copyId,
        uniqueSlug(e['name'] as String, copyId),
        e['name'],
        e['muscle_group'],
        e['equip'],
        e['compound'],
        e['base_weight_kg'],
        e['plate_step_kg'],
        e['default_rep_low'],
        e['default_rep_high'],
        e['default_warmup_sets'],
        e['default_working_sets'],
        e['default_rir_low'],
        e['default_rir_high'],
        0,
        userId,
        nowIso,
      ],
    ));
    ops.add((
      sql: 'UPDATE sets SET exercise_id = ? WHERE exercise_id = ?',
      args: [copyId, oldId],
    ));
    ops.add((
      sql: 'UPDATE day_template_items SET exercise_id = ? WHERE exercise_id = ?',
      args: [copyId, oldId],
    ));
  }

  final itemsByDay = <String, List<Map<String, Object?>>>{};
  for (final it in templateItems) {
    (itemsByDay[it['day_template_id'] as String] ??= []).add(it);
  }

  for (final d in templateDays) {
    final oldId = d['id'] as String;
    final copyId = absorbCopyId(userId, oldId);
    if (existingIds.contains(copyId)) continue;
    ops.add((
      sql: 'INSERT INTO day_templates '
          '(id, name, focus, scheduled_weekday, position, is_template, created_by, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        copyId,
        d['name'],
        d['focus'],
        d['scheduled_weekday'],
        d['position'],
        0,
        userId,
        nowIso,
      ],
    ));
    for (final it in itemsByDay[oldId] ?? const <Map<String, Object?>>[]) {
      final exId = it['exercise_id'] as String;
      ops.add((
        sql: 'INSERT INTO day_template_items '
            '(id, day_template_id, exercise_id, position, target_warmup_sets, '
            'target_working_sets, target_rep_low, target_rep_high, '
            'target_rir_low, target_rir_high, is_template, created_by, created_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        args: [
          absorbCopyId(userId, it['id'] as String),
          copyId,
          exCopyIds[exId] ?? exId, // re-point only known template exercises
          it['position'],
          it['target_warmup_sets'],
          it['target_working_sets'],
          it['target_rep_low'],
          it['target_rep_high'],
          it['target_rir_low'],
          it['target_rir_high'],
          0,
          userId,
          nowIso,
        ],
      ));
    }
    ops.add((
      sql: 'UPDATE sessions SET day_template_id = ? WHERE day_template_id = ?',
      args: [copyId, oldId],
    ));
  }

  return ops;
}

/// Boot-time executor: absorbs all visible templates. Returns the number of
/// ops applied (0 = nothing to do — the common case).
Future<int> absorbTemplates(PowerSyncDatabase db, String userId) async {
  final exRows =
      await db.getAll('SELECT * FROM exercises WHERE is_template = 1');
  final dayRows =
      await db.getAll('SELECT * FROM day_templates WHERE is_template = 1');
  if (exRows.isEmpty && dayRows.isEmpty) return 0;
  final itemRows =
      await db.getAll('SELECT * FROM day_template_items WHERE is_template = 1');

  final existingExercise =
      await db.getAll('SELECT id FROM exercises WHERE is_template = 0');
  final existingDays =
      await db.getAll('SELECT id FROM day_templates WHERE is_template = 0');
  final existingIds = {
    ...existingExercise.map((r) => r['id'] as String),
    ...existingDays.map((r) => r['id'] as String),
  };

  final ops = absorbOps(
    userId: userId,
    templateExercises: [for (final r in exRows) Map<String, Object?>.from(r)],
    templateDays: [for (final r in dayRows) Map<String, Object?>.from(r)],
    templateItems: [for (final r in itemRows) Map<String, Object?>.from(r)],
    existingIds: existingIds,
    nowIso: DateTime.now().toUtc().toIso8601String(),
  );
  if (ops.isEmpty) return 0;

  await db.writeTransaction((tx) async {
    for (final op in ops) {
      await tx.execute(op.sql, op.args);
    }
  });
  return ops.length;
}
