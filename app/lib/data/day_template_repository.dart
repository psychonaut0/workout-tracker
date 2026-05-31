import 'package:powersync/powersync.dart';

import 'models.dart';

// ── resolveSlot ───────────────────────────────────────────────────────────────

// Hardcoded fallbacks (last resort when slot and exercise both lack a value).
const _defaultWorkSets = 3;
const _defaultWarmupSets = 0;
const _defaultRepLow = 8;
const _defaultRepHigh = 12;
const _defaultRirLow = 1;
const _defaultRirHigh = 1;

/// Resolves a [Slot] + [Exercise] pair into a fully-specified [ResolvedSlot].
///
/// Fallback chain (matches `data.jsx` `resolveSlot`):
///   1. Slot value (if non-null) wins.
///   2. Exercise default (if non-null) wins.
///   3. Hardcoded fallback: workSets 3, warmupSets 0, repLow 8, repHigh 12,
///      rirLow 1, rirHigh 1.
ResolvedSlot resolveSlot(Slot slot, Exercise exercise) {
  int pick(int? slotVal, int? exDefault, int hardcoded) {
    if (slotVal != null) return slotVal;
    if (exDefault != null) return exDefault;
    return hardcoded;
  }

  return ResolvedSlot(
    exercise: exercise,
    workSets: pick(slot.workSets, exercise.defaultWorkingSets, _defaultWorkSets),
    warmupSets: pick(slot.warmupSets, exercise.defaultWarmupSets, _defaultWarmupSets),
    repLow: pick(slot.repLow, exercise.defaultRepLow, _defaultRepLow),
    repHigh: pick(slot.repHigh, exercise.defaultRepHigh, _defaultRepHigh),
    rirLow: pick(slot.rirLow, exercise.defaultRirLow, _defaultRirLow),
    rirHigh: pick(slot.rirHigh, exercise.defaultRirHigh, _defaultRirHigh),
  );
}

// ── DayTemplateRepository ────────────────────────────────────────────────────

/// Repository for day_templates and their items (slots).
///
/// PowerSync sync-rules cannot JOIN, but local SQLite CAN. The watch methods
/// use a single query over the two tables, assembling [Slot] lists in Dart.
class DayTemplateRepository {
  final PowerSyncDatabase db;

  const DayTemplateRepository(this.db);

  /// A live stream of all day templates with their slots, ordered by position.
  ///
  /// The items are fetched in a separate query and grouped by template id in
  /// Dart, which avoids duplicating template columns for each item row.
  Stream<List<DayTemplate>> watchDays() {
    // Watch day_templates; rebuild when either table changes.
    return db
        .watch(
          'SELECT dt.id, dt.slug, dt.name, dt.focus, dt.scheduled_weekday, dt.position '
          'FROM day_templates dt ORDER BY dt.position',
        )
        .asyncMap((templateRows) async {
          // One-shot read of all items; fine — they change far less than live sets.
          final itemRows = await db.getAll(
            'SELECT * FROM day_template_items ORDER BY day_template_id, position',
          );

          // Group items by template id.
          final slotsByTemplate = <String, List<Slot>>{};
          for (final row in itemRows) {
            final tid = row['day_template_id'] as String;
            slotsByTemplate.putIfAbsent(tid, () => []).add(Slot.fromRow(row));
          }

          return templateRows.map((row) {
            final id = row['id'] as String;
            return DayTemplate(
              id: id,
              slug: row['slug'] as String?,
              name: row['name'] as String? ?? '',
              focus: row['focus'] as String?,
              scheduledWeekday: row['scheduled_weekday'] as int?,
              position: row['position'] as int? ?? 0,
              slots: slotsByTemplate[id] ?? [],
            );
          }).toList();
        });
  }

  /// Fetches a single day template by id, including its slots.
  Future<DayTemplate?> byId(String id) async {
    final row = await db.getOptional(
      'SELECT id, slug, name, focus, scheduled_weekday, position '
      'FROM day_templates WHERE id = ?',
      [id],
    );
    if (row == null) return null;

    final itemRows = await db.getAll(
      'SELECT * FROM day_template_items WHERE day_template_id = ? ORDER BY position',
      [id],
    );

    return DayTemplate(
      id: row['id'] as String,
      slug: row['slug'] as String?,
      name: row['name'] as String? ?? '',
      focus: row['focus'] as String?,
      scheduledWeekday: row['scheduled_weekday'] as int?,
      position: row['position'] as int? ?? 0,
      slots: itemRows.map(Slot.fromRow).toList(),
    );
  }
}
