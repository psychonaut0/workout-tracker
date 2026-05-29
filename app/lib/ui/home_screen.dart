import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' show uuid; // SDK's crypto-seeded UUID
import 'package:sqlite3/common.dart' show ResultSet;

import '../sync/db.dart';

/// Minimal throwaway round-trip screen:
/// - the list is a live db.watch() over `exercises` — it should populate with
///   the seeded template exercises once download completes (proves DOWNLOAD).
/// - "Log a quick session" does local INSERTs into `sessions` + `sets`, which
///   PowerSync queues and the connector uploads to /sync/upload (proves UPLOAD).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises (synced)'),
        actions: [
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: StreamBuilder<ResultSet>(
        // Live query: re-emits whenever the local `exercises` table changes
        // (including after the initial sync download lands).
        stream: db.watch(
          'SELECT id, name, muscle_group, is_template FROM exercises ORDER BY name',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('No exercises yet (syncing...)'));
          }
          return ListView(
            children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  title: Text(r['name'] as String? ?? '(unnamed)'),
                  subtitle: Text(r['muscle_group'] as String? ?? ''),
                  trailing: (r['is_template'] as int? ?? 0) == 1
                      ? const Text('template')
                      : const Text('custom'),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _logQuickSession(context),
        label: const Text('Log a quick session'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  /// Writes a session plus two sets entirely LOCALLY. PowerSync records these in
  /// its CRUD queue and the connector ships them to /sync/upload -> Postgres.
  ///
  /// Notes that match the backend contract:
  /// - ids are client-generated UUIDv4 (the server upserts by id).
  /// - weight_kg is written AS TEXT (NUMERIC on the server; arrives as text on
  ///   download too).
  /// - booleans are written as 0/1 integers (is_warmup).
  /// - user_id / is_top_set / is_pr are stamped/computed server-side, so we do
  ///   not set them here.
  Future<void> _logQuickSession(BuildContext context) async {
    // Pick any exercise to attach the sets to (first synced row).
    final ex = await db.getOptional('SELECT id FROM exercises ORDER BY name LIMIT 1');
    if (ex == null) {
      _toast(context, 'No exercise to log against yet — wait for sync.');
      return;
    }
    final exerciseId = ex['id'] as String;

    final sessionId = uuid.v4();
    final today = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD

    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO sessions (id, date, split_label) VALUES (?, ?, ?)',
        [sessionId, today, 'Quick test'],
      );
      await tx.execute(
        'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, is_warmup) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [uuid.v4(), sessionId, exerciseId, 1, '60.00', 8, 0],
      );
      await tx.execute(
        'INSERT INTO sets (id, session_id, exercise_id, set_number, weight_kg, reps, is_warmup) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [uuid.v4(), sessionId, exerciseId, 2, '80.00', 6, 0],
      );
    });

    if (context.mounted) {
      _toast(context, 'Queued session $sessionId for upload.');
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
