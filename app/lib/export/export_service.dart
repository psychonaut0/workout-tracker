import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:share_plus/share_plus.dart';

import '../settings/settings_service.dart';
import '../units/unit_service.dart';
import '../util/dates.dart';
import 'export_builder.dart';

enum ExportOutcome { shared, saved, empty }

class ExportResult {
  const ExportResult(this.outcome, [this.path]);
  final ExportOutcome outcome;
  final String? path; // set only for [ExportOutcome.saved] (Linux fallback)
}

/// Queries the local DB, builds the export JSON, writes it to a temp file and
/// opens the share sheet. On Linux (dev) shares are unsupported → saves into
/// the Documents dir instead and reports the path.
class ExportService {
  ExportService(this.db);
  final PowerSyncDatabase db;

  static const _tableNames = [
    'exercises',
    'day_templates',
    'day_template_items',
    'sessions',
    'sets',
    'bodyweight_logs',
    'muscle_targets',
  ];

  Future<ExportResult> exportFull({
    required SettingsService settings,
    required UnitService units,
  }) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in _tableNames) {
      final rows = await db.getAll('SELECT * FROM $t ORDER BY id');
      tables[t] = [for (final r in rows) Map<String, Object?>.from(r)];
    }
    final accent = settings.accent.toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    final json = buildFullExport(
      tables: tables,
      settings: {
        'unit': units.unit == Unit.kg ? 'kg' : 'lb',
        'mode': settings.mode,
        'accent': '#$accent',
        'profile_name': settings.profileName,
      },
      exportedAt: DateTime.now(),
    );
    return _deliver(json, 'reps-full-${isoDate(DateTime.now())}.json');
  }

  Future<ExportResult> exportHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromS = isoDate(from);
    final toS = isoDate(to);

    // sessions.date is date-only YYYY-MM-DD → inclusive string compare is exact.
    final sessionRows = await db.getAll(
      'SELECT * FROM sessions WHERE date >= ? AND date <= ? '
      'ORDER BY date ASC, created_at ASC',
      [fromS, toS],
    );
    if (sessionRows.isEmpty) return const ExportResult(ExportOutcome.empty);

    final setRows = await db.getAll(
      'SELECT s.* FROM sets s JOIN sessions se ON se.id = s.session_id '
      'WHERE se.date >= ? AND se.date <= ? '
      'ORDER BY s.session_id, s.exercise_id, s.set_number',
      [fromS, toS],
    );
    final setsBySession = <String, List<Map<String, Object?>>>{};
    for (final r in setRows) {
      (setsBySession[r['session_id'] as String] ??= [])
          .add(Map<String, Object?>.from(r));
    }

    final exRows =
        await db.getAll('SELECT id, name, muscle_group FROM exercises');
    final exerciseById = {
      for (final r in exRows)
        r['id'] as String: (
          name: r['name'] as String? ?? r['id'] as String,
          muscleGroup: r['muscle_group'] as String? ?? '',
        ),
    };

    final json = buildHistoryExport(
      sessions: [for (final r in sessionRows) Map<String, Object?>.from(r)],
      setsBySession: setsBySession,
      exerciseById: exerciseById,
      from: from,
      to: to,
    );
    return _deliver(json, 'reps-history-${fromS}_$toS.json');
  }

  Future<ExportResult> _deliver(
      Map<String, dynamic> data, String filename) async {
    final text = const JsonEncoder.withIndent('  ').convert(data);

    if (Platform.isLinux) {
      // share_plus cannot share files on Linux — save where the user can find it.
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, filename));
      await file.writeAsString(text);
      return ExportResult(ExportOutcome.saved, file.path);
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(text);
    // share_plus 11.x: statics (Share.shareXFiles) are deprecated.
    await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
    return const ExportResult(ExportOutcome.shared);
  }
}
