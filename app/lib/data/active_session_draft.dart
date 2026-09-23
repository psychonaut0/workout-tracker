import 'dart:convert';

import '../session/active_session_controller.dart';
import 'json_file_store.dart';

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
  final JsonFileStore<SessionDraft> _store = JsonFileStore<SessionDraft>(
    filename: 'workout-draft.json',
    encode: (draft) => draft.toJson(),
    tryDecode: DraftStore.tryDecode,
  );

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

  /// Serialises [draft] to JSON and writes it atomically via a temp file.
  Future<void> save(SessionDraft draft) => _store.save(draft);

  /// Reads and deserialises the draft, or returns null if no draft exists or
  /// the file is corrupt (a corrupt file is cleared).
  Future<SessionDraft?> load() => _store.load();

  /// Deletes the persisted draft file.
  Future<void> clear() => _store.clear();
}
