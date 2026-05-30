import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import 'package:workout_tracker/auth/auth_store.dart';
import 'package:workout_tracker/sync/connector.dart';

/// An AuthStore already holding a known access token, backed by a MockClient
/// for /auth/login + /auth/refresh so no real socket is opened.
Future<AuthStore> _loggedInAuth(String access, String refresh) async {
  FlutterSecureStorage.setMockInitialValues({});
  final auth = AuthStore(
    client: MockClient((req) async => http.Response(
          jsonEncode({'access_token': access, 'refresh_token': refresh}),
          200,
        )),
  );
  await auth.login('me@example.com', 'devpassword');
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutConnector.buildUploadBatch', () {
    test('emits {op,table,id,data} with uppercase op and table under "table"', () {
      // NOTE: CrudEntry's positional constructor is expected to be
      //   CrudEntry(clientId, op, table, id, transactionId, opData, {previousValues, metadata}).
      // If the installed SDK differs, this will fail to COMPILE — fix the
      // constructor call to match; the OUTPUT-shape assertions below are the point.
      final crud = <CrudEntry>[
        CrudEntry(1, UpdateType.put, 'sessions', 'sess-1', 1,
            {'date': '2026-05-29', 'split_label': 'Quick test'}),
        CrudEntry(2, UpdateType.patch, 'sets', 'set-1', 1, {'reps': 9}),
        CrudEntry(3, UpdateType.delete, 'sets', 'set-1', 1, null),
      ];

      final batch = WorkoutConnector.buildUploadBatch(crud);

      expect(batch[0]['op'], 'PUT');
      expect(batch[1]['op'], 'PATCH');
      expect(batch[2]['op'], 'DELETE');
      // Table name travels under "table" (the connector hand-builds this key;
      // the Go handler accepts both "table" and "type").
      expect(batch[0]['table'], 'sessions');
      expect(batch[0].containsKey('type'), isFalse);
      expect(batch[0]['id'], 'sess-1');
      expect(batch[0]['data'],
          {'date': '2026-05-29', 'split_label': 'Quick test'});
      // DELETE has no opData -> data defaults to {} (never null on the wire).
      expect(batch[2]['data'], <String, dynamic>{});
    });
  });

  group('WorkoutConnector.uploadBatch', () {
    test('POSTs {"batch":...} to /sync/upload with Bearer ACCESS token; 2xx returns',
        () async {
      late http.Request captured;
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((req) async {
          captured = req;
          return http.Response('{}', 200);
        }),
      );

      await connector.uploadBatch(const []); // no throw on 2xx

      expect(captured.url.path, '/sync/upload');
      expect(captured.headers['authorization'], 'Bearer ACCESS_1');
      expect((jsonDecode(captured.body) as Map).containsKey('batch'), isTrue);
    });

    test('throws on 5xx so the SDK retries the same batch', () async {
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((_) async => http.Response('db down', 503)),
      );
      expect(() => connector.uploadBatch(const []), throwsA(isA<Exception>()));
    });

    test('throws on 401 (triggers a refresh) so the SDK retries', () async {
      final auth = await _loggedInAuth('ACCESS_1', 'REFRESH_1');
      final connector = WorkoutConnector(
        auth,
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      expect(() => connector.uploadBatch(const []), throwsA(isA<Exception>()));
    });
  });
}
