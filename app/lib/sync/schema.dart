import 'package:powersync/powersync.dart';

/// Local-first PowerSync schema for the six synced tables.
///
/// Mapping rules (server is the source of truth; see sync rules + migrations):
/// - The `id` column is implicit (PowerSync always adds a TEXT `id`); never
///   declare it here.
/// - `weight_kg` is NUMERIC in Postgres and arrives CLIENT-SIDE AS TEXT, so it
///   is [Column.text]. Parse to a number only at the edges; write it back as a
///   string.
/// - Booleans (`is_template`, `is_warmup`, `is_top_set`, `is_pr`) are
///   [Column.integer] (0/1) — SQLite has no native bool.
/// - Dates / timestamps (`date`, `created_at`, `updated_at`) are [Column.text]
///   (ISO-8601 strings).
/// - Counts / small ints (`set_number`, `reps`, `rir`, `position`, `target_*`)
///   are [Column.integer].
const schema = Schema([
  Table('exercises', [
    Column.text('name'),
    Column.text('slug'),
    Column.text('muscle_group'),
    Column.integer('is_template'),
    Column.text('created_by'),
    Column.text('created_at'),
    Column.text('equip'),
    Column.integer('compound'),
    Column.text('base_weight_kg'),
    Column.text('plate_step_kg'),
    Column.integer('default_rep_low'),
    Column.integer('default_rep_high'),
    Column.integer('default_warmup_sets'),
    Column.integer('default_working_sets'),
    Column.integer('default_rir_low'),
    Column.integer('default_rir_high'),
  ]),
  Table('sessions', [
    Column.text('user_id'),
    Column.text('date'),
    Column.text('split_label'),
    Column.text('notes'),
    Column.text('day_template_id'),
    Column.text('created_at'),
    Column.integer('duration_min'),
  ]),
  Table('sets', [
    Column.text('session_id'),
    Column.text('exercise_id'),
    Column.text('user_id'),
    Column.integer('set_number'),
    Column.text('weight_kg'), // NUMERIC -> TEXT on the client
    Column.integer('reps'),
    Column.integer('rir'),
    Column.integer('is_warmup'),
    Column.integer('is_top_set'),
    Column.integer('is_pr'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ], indexes: [
    // Local read pattern: list a session's sets in order.
    Index('sets_session', [IndexedColumn('session_id')]),
  ]),
  Table('bodyweight_logs', [
    Column.text('user_id'),
    Column.text('date'),
    Column.text('weight_kg'), // NUMERIC -> TEXT
    Column.text('created_at'),
  ]),
  Table('day_templates', [
    Column.text('slug'),
    Column.text('name'),
    Column.text('notes'),
    Column.integer('position'),
    Column.integer('is_template'),
    Column.text('created_by'),
    Column.text('created_at'),
    Column.text('focus'),
    Column.integer('scheduled_weekday'),
  ]),
  Table('day_template_items', [
    Column.text('day_template_id'),
    Column.text('exercise_id'),
    Column.integer('position'),
    Column.integer('target_warmup_sets'),
    Column.integer('target_working_sets'),
    Column.integer('target_rep_low'),
    Column.integer('target_rep_high'),
    Column.integer('target_rir_low'),
    Column.integer('target_rir_high'),
    Column.integer('is_template'),
    Column.text('created_by'),
    Column.text('created_at'),
  ], indexes: [
    Index('dti_template', [IndexedColumn('day_template_id')]),
  ]),
  Table('muscle_targets', [
    Column.text('user_id'),
    Column.text('muscle'),
    Column.integer('target_sets'),
    Column.text('created_at'),
  ]),
]);
