import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../session/active_session_controller.dart';

/// Persists the active [SessionDraft] to a local JSON file in the app-support
/// directory. This store is local-only and is never synced via PowerSync.
///
/// File location: `<applicationSupportDirectory>/workout-draft.json`
///
/// Usage:
/// ```dart
/// final store = DraftStore();
/// await store.save(controller.draft);     // on every mutation
/// final draft = await store.load();       // on app resume
/// await store.clear();                    // after finish() / discard()
/// ```
class DraftStore {
  static const _filename = 'workout-draft.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _filename));
  }

  /// Serialises [draft] to JSON and writes it atomically via a temp file.
  Future<void> save(SessionDraft draft) async {
    final file = await _file();
    final json = jsonEncode(draft.toJson());
    // Write to a temp file first, then rename (atomic on most platforms).
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }

  /// Reads and deserialises the draft, or returns null if no draft exists or
  /// the file is corrupt.
  Future<SessionDraft?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SessionDraft.fromJson(json);
    } on Exception {
      // Corrupt draft — clear it and start fresh.
      await clear();
      return null;
    }
  }

  /// Deletes the persisted draft file.
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
