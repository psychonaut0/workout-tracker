import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/json_file_store.dart';

/// [JsonFileStore] holds the atomic-save/tolerant-load/clear shape that
/// [DraftStore] and [FinishedSessionStore] each build on; this pins that
/// shared logic directly instead of only through its two callers.
JsonFileStore<String> _store(Directory dir) => JsonFileStore<String>(
      filename: 'value.json',
      directory: () async => dir,
      encode: (v) => {'v': v},
      tryDecode: (raw) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return json['v'] as String;
        } catch (_) {
          return null;
        }
      },
    );

void main() {
  group('JsonFileStore', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('json_file_store_test');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('load returns null when no file exists', () async {
      expect(await _store(tmp).load(), isNull);
    });

    test('save then load round-trips the value', () async {
      final store = _store(tmp);
      await store.save('hello');
      expect(await store.load(), 'hello');
    });

    test('save writes atomically, leaving no temp file behind', () async {
      await _store(tmp).save('hello');
      expect(File('${tmp.path}/value.json.tmp').existsSync(), isFalse);
      expect(File('${tmp.path}/value.json').existsSync(), isTrue);
    });

    test('load clears and returns null for a malformed file', () async {
      final file = File('${tmp.path}/value.json');
      await file.writeAsString('not json');
      expect(await _store(tmp).load(), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('load clears and returns null for a mistyped file', () async {
      // A cast failure inside tryDecode is a TypeError, not an Exception;
      // this pins that load() still clears it rather than rethrowing.
      final file = File('${tmp.path}/value.json');
      await file.writeAsString(jsonEncode({'v': 3}));
      expect(await _store(tmp).load(), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('clear deletes the file and is a no-op when absent', () async {
      final store = _store(tmp);
      await store.save('hello');
      await store.clear();
      expect(File('${tmp.path}/value.json').existsSync(), isFalse);
      await store.clear();
    });
  });
}
