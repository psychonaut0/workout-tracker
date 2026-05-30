import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import '../auth/auth_store.dart';
import 'connector.dart';
import 'schema.dart';

/// The single app-wide PowerSyncDatabase. PowerSync requires exactly one
/// instance per database file.
PowerSyncDatabase? _db;

PowerSyncDatabase get db {
  final d = _db;
  if (d == null) {
    throw StateError('PowerSync not opened; call openDatabase() first');
  }
  return d;
}

/// Opens (or returns) the local PowerSync database. As of PowerSync v2 the
/// `powersync` package loads its SQLite extension via build hooks, so no
/// separate libs package or native path wiring is needed on Linux desktop.
Future<PowerSyncDatabase> openDatabase() async {
  if (_db != null) return _db!;
  final dir = await getApplicationSupportDirectory();
  final path = p.join(dir.path, 'workout-tracker.db');
  final database = PowerSyncDatabase(schema: schema, path: path);
  await database.initialize();
  _db = database;
  return database;
}

/// Connect the open database to the sync service using [auth]'s credentials.
Future<void> connectSync(AuthStore auth) async {
  await db.connect(connector: WorkoutConnector(auth));
}

/// Stop syncing and wipe ALL local data (used on logout).
Future<void> disconnectAndClear() async {
  await db.disconnectAndClear();
}
