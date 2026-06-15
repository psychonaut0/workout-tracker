import 'package:powersync/powersync.dart';

/// One-time, idempotent backfill of `is_template` for owned rows.
///
/// Builds before the create-exercise/day fix omitted `is_template` on INSERT,
/// so rows created offline (or while sync was erroring) were stored with
/// `is_template = NULL`. The list filters hid them, and — more subtly — the
/// [absorbTemplates] de-dup queries match on the exact `is_template = 0`, so a
/// NULL owned row is invisible to them and a same-named server template/seed
/// could be absorbed a SECOND time, producing a duplicate.
///
/// Normalizing every NULL to 0 makes all owned content canonical: visible in
/// lists and seen by the absorb de-dup. Server template rows (`is_template = 1`)
/// and synced rows (the server forces the column) are untouched. Guarded so it
/// only writes when there is something to fix; safe to run on every launch and
/// MUST run before [absorbTemplates].
Future<void> backfillIsTemplate(PowerSyncDatabase db) async {
  final row = await db.get(
    'SELECT '
    '(SELECT COUNT(*) FROM exercises WHERE is_template IS NULL) + '
    '(SELECT COUNT(*) FROM day_templates WHERE is_template IS NULL) + '
    '(SELECT COUNT(*) FROM day_template_items WHERE is_template IS NULL) AS n',
  );
  if ((row['n'] as num? ?? 0) == 0) return;

  await db.writeTransaction((tx) async {
    await tx.execute(
        'UPDATE exercises SET is_template = 0 WHERE is_template IS NULL');
    await tx.execute(
        'UPDATE day_templates SET is_template = 0 WHERE is_template IS NULL');
    await tx.execute(
        'UPDATE day_template_items SET is_template = 0 WHERE is_template IS NULL');
  });
}
