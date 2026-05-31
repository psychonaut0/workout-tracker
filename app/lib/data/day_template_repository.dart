import 'package:powersync/powersync.dart';

import '../util/dates.dart';
import 'models.dart';
import 'session_repository.dart';

// ── selectNextDay ─────────────────────────────────────────────────────────────

/// Pure rotation-selection logic: given an ordered list of [days] and the
/// [lastId] of the most-recently-trained day template (or null), returns the
/// next [DayTemplate] in the rotation.
///
/// Rules:
/// - [days] empty → null.
/// - [lastId] null (no history or custom session) → `days.first`.
/// - [lastId] not found in [days] (unknown id) → `days.first`.
/// - Otherwise → `days[(indexOf(lastId) + 1) % days.length]` (wraps around).
DayTemplate? selectNextDay(List<DayTemplate> days, String? lastId) {
  if (days.isEmpty) return null;
  if (lastId == null) return days.first;
  final i = days.indexWhere((d) => d.id == lastId);
  if (i < 0) return days.first;
  return days[(i + 1) % days.length];
}

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

  // ── Rotation helpers ──────────────────────────────────────────────────────

  /// Returns the next day template in position-based rotation.
  ///
  /// Algorithm:
  /// 1. No days → null.
  /// 2. No session history, or last session had no template (custom), or the
  ///    last template id is unknown → first day.
  /// 3. Otherwise → the successor of the most-recent session's day_template_id
  ///    (wraps around to the first day after the last).
  ///
  /// The pure selection logic is exposed via [selectNextDay] so it can be
  /// unit-tested without a live database.
  Future<DayTemplate?> nextInRotation(SessionRepository sessionRepo) async {
    final days = await watchDays().first;
    if (days.isEmpty) return null;
    final recent = await sessionRepo.watchRecentSessions(limit: 1).first;
    final lastId = recent.isEmpty ? null : recent.first.dayTemplateId;
    return selectNextDay(days, lastId);
  }

  /// Returns the set of day_template_ids that were trained during the week
  /// beginning at [weekStart] (Monday 00:00).
  ///
  /// Custom sessions (day_template_id IS NULL) are excluded.
  Future<Set<String>> templateIdsTrainedThisWeek({
    required DateTime weekStart,
  }) async {
    final rows = await db.getAll(
      'SELECT DISTINCT day_template_id FROM sessions '
      'WHERE date >= ? AND day_template_id IS NOT NULL',
      [isoDate(weekStart)],
    );
    return rows.map((r) => r['day_template_id'] as String).toSet();
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
