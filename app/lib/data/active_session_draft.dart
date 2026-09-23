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

  /// Decodes a draft file's contents, or returns null if it is not a valid
  /// draft. Catches everything: a missing or mistyped field is a `TypeError`
  /// (an Error, not an Exception), which would otherwise escape to `main()`
  /// before `runApp` and stop the app starting.
  static SessionDraft? tryDecode(String raw) {
    try {
      return SessionDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Reads and deserialises the draft, or returns null if no draft exists or
  /// the file is corrupt (a corrupt file is cleared).
  Future<SessionDraft?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    SessionDraft? draft;
    try {
      draft = tryDecode(await file.readAsString());
    } catch (_) {
      draft = null;
    }
    if (draft == null) await clear();
    return draft;
  }

  /// Deletes the persisted draft file.
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
