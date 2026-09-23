import 'dart:convert';

import '../session/active_session_controller.dart';
import 'json_file_store.dart';

/// Snapshot of the last workout finished on this device, kept so an
/// accidental Finish can be undone from History.
class FinishedSession {
  /// The `sessions.id` the finish wrote.
  final String sessionId;

  /// The `sessions.date` the finish wrote (`YYYY-MM-DD`).
  final String sessionDate;

  /// Local wall clock at finish.
  final DateTime finishedAt;

  /// Workout time at finish (what `duration_min` rounds).
  final int elapsedSeconds;

  /// The draft exactly as it was when Finish was tapped.
  final SessionDraft draft;

  const FinishedSession({
    required this.sessionId,
    required this.sessionDate,
    required this.finishedAt,
    required this.elapsedSeconds,
    required this.draft,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'sessionDate': sessionDate,
        'finishedAt': finishedAt.toIso8601String(),
        'elapsedSeconds': elapsedSeconds,
        'draft': draft.toJson(),
      };

  factory FinishedSession.fromJson(Map<String, dynamic> json) => FinishedSession(
        sessionId: json['sessionId'] as String,
        sessionDate: json['sessionDate'] as String,
        finishedAt: DateTime.parse(json['finishedAt'] as String),
        elapsedSeconds: json['elapsedSeconds'] as int,
        draft: SessionDraft.fromJson(json['draft'] as Map<String, dynamic>),
      );

  /// Decodes a snapshot file's contents, or null if it is not a valid one.
  /// Catches everything, including the `TypeError` of a mistyped field.
  static FinishedSession? tryDecode(String raw) {
    try {
      return FinishedSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Single-slot, local-only store for the [FinishedSession] snapshot, at
/// `<applicationSupportDirectory>/workout-last-finished.json`. Never synced.
/// A later finish overwrites it.
class FinishedSessionStore {
  final JsonFileStore<FinishedSession> _store = JsonFileStore<FinishedSession>(
    filename: 'workout-last-finished.json',
    encode: (f) => f.toJson(),
    tryDecode: FinishedSession.tryDecode,
  );

  /// Writes [f] atomically via a temp file.
  Future<void> save(FinishedSession f) => _store.save(f);

  /// The stored snapshot, or null if there is none or it is unreadable (an
  /// unreadable file is cleared).
  Future<FinishedSession?> load() => _store.load();

  Future<void> clear() => _store.clear();
}
