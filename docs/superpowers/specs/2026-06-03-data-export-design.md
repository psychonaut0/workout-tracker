# Data export (Profile) — full backup + history range

**Date:** 2026-06-03
**Status:** Approved (design)
**Scope:** Two JSON exports launched from a new "Data" group in Profile, delivered via the Android share sheet (`share_plus` — the one new dependency). (1) **Full export**: every user table + settings, versioned for a future import feature. (2) **History export**: sessions in a user-picked date range, denormalized and LLM-friendly. Import itself is OUT of scope.

## Module layout

`app/lib/export/` — pure-vs-IO split (same pattern as `sync/sync_status_ui.dart`):

### `export_builder.dart` — pure, fully unit-testable

No DB, no IO, no Flutter imports. Plain data in, `Map<String, dynamic>` out.

**`buildFullExport`** — lossless backup envelope:
```dart
Map<String, dynamic> buildFullExport({
  required Map<String, List<Map<String, Object?>>> tables, // table name → raw rows
  required Map<String, Object?> settings,                  // pre-built snapshot
  required DateTime exportedAt,
})
```
Output:
```json
{ "format": "reps-export", "version": 1, "kind": "full",
  "exported_at": "2026-06-03T18:00:00.000",
  "settings": { "unit": "kg", "mode": "dark", "accent": "#FFB7F343", "profile_name": "..." },
  "data": { "exercises": [...], "day_templates": [...], "day_template_items": [...],
            "sessions": [...], "sets": [...], "bodyweight_logs": [...], "muscle_targets": [...] } }
```
Rules:
- Rows pass through as stored (kg canonical, ids kept for referential integrity) EXCEPT `user_id` is stripped from every row (import re-stamps; keeps the file portable). The builder strips it itself so callers can pass raw `SELECT *` rows.
- `settings` is a caller-built snapshot: `unit` (kg/lb), `mode`, `accent` (hex `#AARRGGBB` from `toARGB32()`), `profile_name`. NO server URL, NO sync flag, NO tokens — backup is about the user's data, not this device's wiring.
- `version: 1` is the import-compatibility contract; bump on breaking schema changes. (No `app_version` field — it would require `package_info_plus` for a value `version` already covers.)

**`buildHistoryExport`** — LLM-friendly nested view:
```dart
Map<String, dynamic> buildHistoryExport({
  required List<Map<String, Object?>> sessions,        // rows in range, date ASC
  required Map<String, List<Map<String, Object?>>> setsBySession,
  required Map<String, ({String name, String muscleGroup})> exerciseById,
  required DateTime from,
  required DateTime to,
})
```
Output:
```json
{ "format": "reps-export", "version": 1, "kind": "history",
  "unit": "kg",
  "date_range": { "from": "2026-01-01", "to": "2026-06-03" },
  "sessions": [ { "date": "2026-06-01", "label": "Upper A", "duration_min": 62,
    "exercises": [ { "name": "Bench Press", "muscle_group": "chest",
      "sets": [ { "weight_kg": 80.0, "reps": 8, "rir": 1, "warmup": false, "top_set": true, "pr": false } ] } ] } ] }
```
Rules:
- Exercises grouped within a session in first-set order (reuse the ordering semantics of the existing `groupIntoBlocks`/set_number conventions: group by exercise_id, exercises ordered by their first set's appearance, sets by set_number).
- Warm-ups included with `"warmup": true`, `"rir": null`.
- Weights always kg (`weight_kg`, numeric); the envelope's `"unit": "kg"` makes that explicit for LLM consumers.
- Unknown exercise_id (shouldn't happen) → `"name": "<exercise_id>"` fallback, no crash.
- Date range inclusive on both ends.

### `export_service.dart` — IO shell

```dart
class ExportService {
  ExportService(this.db);           // PowerSync db (the global getter at call site)
  Future<ExportResult> exportFull({required SettingsService settings, required UnitService units});
  Future<ExportResult> exportHistory({required DateTime from, required DateTime to});
}
```
- **Full**: `SELECT *` from the 7 tables (exercises, day_templates, day_template_items, sessions, sets, bodyweight_logs, muscle_targets), build the settings snapshot, call `buildFullExport`, encode.
- **History**: sessions where `date >= from AND date <= to` (match the column's actual stored format — inspect; dates are ISO strings) ordered ASC, their sets ordered by exercise/set_number, exercise names from the catalog; call `buildHistoryExport`. If zero sessions in range → return `ExportResult.empty` (no file, UI shows a notice).
- Encode with `JsonEncoder.withIndent('  ')` (human/LLM-readable; size is trivial at this scale).
- Write to `getTemporaryDirectory()` as `reps-full-<yyyy-MM-dd>.json` / `reps-history-<from>_<to>.json`.
- **Share**: `Share.shareXFiles([XFile(path, mimeType: 'application/json')])` via `share_plus`.
- **Linux fallback** (dev builds): `Platform.isLinux` → write to `getApplicationDocumentsDirectory()` instead and return the path in `ExportResult.savedTo`; the UI shows it in a dialog. (share_plus does not support file sharing on Linux.)
- `ExportResult`: `enum ExportOutcome { shared, saved, empty }` + `class ExportResult { final ExportOutcome outcome; final String? path; }` (`path` set only for `saved`).

## UI (Profile)

New `_Group(label: 'Data')` between Sync & Backend and Account in `profile_screen.dart`:
- `_Row(icon: WIcons.export, title: 'Export all data', sub: 'Full backup · JSON')` — tap → row shows a small spinner (busy flag, double-tap guarded) → share sheet (or Linux path dialog). `WIcons` has no export glyph today — add `static const IconData export = Icons.ios_share;` and `static const IconData history = Icons.history;` to `theme/icons.dart` (WIcons is a thin Material-icon alias table; follow its style).
- `_Row(icon: WIcons.history, title: 'Export history', sub: 'Sessions in a date range · JSON')` — tap → `showDateRangePicker` (Material, themed by the app's `buildTheme`; `firstDate` = first session date (fallback: 1 year ago), `lastDate` = today, `initialDateRange` = first session → today) → busy → share sheet.
- Empty history result → notice via the existing dialog/snackbar language: `showWDialog`-style notice or SnackBar — use a SnackBar ('No sessions in that range').
- Errors (file write/share throws) → `showWConfirm`-family notice: a single-action `showWDialog<void>` with title 'Export failed' and the error message, one 'OK' action.
- Export is available signed-in or not (purely local reads).

## Dependency

`share_plus` (latest compatible with Flutter 3.44) added to `app/pubspec.yaml`. No other new packages (`path_provider` already present).

## Error handling

- Share-sheet cancel: share_plus resolves normally → treat as success, no message.
- Any exception in query/encode/write/share → caught in the UI handler → error dialog; busy flag always cleared in `finally`.
- Empty full export (fresh install) still produces a valid file (empty arrays) — useful as a schema sample.

## Testing

Builder tests (`app/test/export/export_builder_test.dart`) carry the weight:
- Full: envelope fields (`format`/`version`/`kind`), `user_id` stripped from every table's rows (and absent even when input rows lack it), table passthrough otherwise intact, settings snapshot embedded verbatim.
- History: date_range echo, session nesting (grouping by exercise, first-set order, sets by set_number), warm-up flag + null rir, kg numbers, unknown-exercise fallback, empty-sessions → `"sessions": []`.
- Service: covered by the builder tests + analyze (no DB-mocking framework in the project; keep service thin enough that its only logic is SQL + plumbing).
- On-device (user): both exports from Profile, share to an app, file content sanity.

## Out of scope

Import flow (the `version` field exists for it); CSV; scheduled/automatic backups; exporting in display units (lb).
