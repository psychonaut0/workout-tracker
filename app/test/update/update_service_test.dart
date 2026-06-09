import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_tracker/update/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isNewer', () {
    test('numeric semver, v-prefix and +build/-suffix tolerant', () {
      expect(isNewer('0.12.0', '0.11.0'), isTrue);
      expect(isNewer('v0.12.0', '0.11.0'), isTrue);
      expect(isNewer('0.12.0+12', '0.12.0+11'), isFalse); // build ignored
      expect(isNewer('0.11.0', '0.11.0'), isFalse);
      expect(isNewer('0.10.9', '0.11.0'), isFalse);
      expect(isNewer('1.0.0', '0.11.0'), isTrue);
      expect(isNewer('0.12.0-beta', '0.11.0'), isTrue); // suffix ignored
      expect(isNewer('garbage', '0.11.0'), isFalse); // malformed → no update
      expect(isNewer('0.12.0', 'garbage'), isFalse);
    });
  });

  String releaseJson(String tag) => '''
  {"tag_name":"$tag","name":"$tag","body":"Notes for $tag",
   "assets":[
     {"name":"something.txt","browser_download_url":"https://example/x.txt","size":10},
     {"name":"reps-$tag.apk","browser_download_url":"https://example/reps-$tag.apk","size":65000000}
   ]}''';

  group('checkForUpdate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
          appName: 'Reps', packageName: 'io.github.psychonaut0.reps',
          version: '0.11.0', buildNumber: '11', buildSignature: '', installerStore: null);
    });

    test('returns UpdateInfo (apk asset) when remote is newer', () async {
      final svc = UpdateService(
        client: MockClient((req) async => http.Response(releaseJson('v0.12.0'), 200)),
        isAndroidOverride: true,
      );
      final info = await svc.checkForUpdate(force: true);
      expect(info, isNotNull);
      expect(info!.version, '0.12.0');
      expect(info.apkUrl, 'https://example/reps-v0.12.0.apk');
      expect(info.sizeBytes, 65000000);
      expect(info.notes, contains('Notes'));
    });

    test('null when remote equals running', () async {
      final svc = UpdateService(
        client: MockClient((req) async => http.Response(releaseJson('v0.11.0'), 200)),
        isAndroidOverride: true,
      );
      expect(await svc.checkForUpdate(force: true), isNull);
    });

    test('null on 304 Not Modified', () async {
      final svc = UpdateService(
        client: MockClient((req) async => http.Response('', 304)),
        isAndroidOverride: true,
      );
      expect(await svc.checkForUpdate(force: true), isNull);
    });

    test('force:true rethrows on real error; auto-path swallows to null', () async {
      final svc = UpdateService(
        client: MockClient((req) async => throw const SocketException('down')),
        isAndroidOverride: true,
      );
      expect(() => svc.checkForUpdate(force: true), throwsA(anything));
      expect(await svc.checkForUpdate(force: false), isNull);
    });

    test('null off-Android regardless of remote', () async {
      final svc = UpdateService(
        client: MockClient((req) async => http.Response(releaseJson('v9.9.9'), 200)),
        isAndroidOverride: false,
      );
      expect(await svc.checkForUpdate(force: true), isNull);
    });

    test('auto-check sends stored ETag and persists the new one on 200',
        () async {
      SharedPreferences.setMockInitialValues({'update.etag': 'old-etag'});
      String? sentIfNoneMatch;
      final svc = UpdateService(
        client: MockClient((req) async {
          sentIfNoneMatch = req.headers['If-None-Match'];
          return http.Response(
            releaseJson('v0.12.0'),
            200,
            headers: {'etag': 'new-etag'},
          );
        }),
        isAndroidOverride: true,
      );
      final info = await svc.checkForUpdate(); // auto path (force:false)
      expect(info, isNotNull);
      expect(sentIfNoneMatch, 'old-etag');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('update.etag'), 'new-etag');
    });

    test('manual check ignores stored ETag so a deferred update re-surfaces',
        () async {
      // After tapping "Later" the ETag is still stored; a 304 would otherwise
      // hide the (still uninstalled) update. The manual button must NOT send
      // If-None-Match, so it always re-evaluates against a fresh 200 body.
      SharedPreferences.setMockInitialValues({'update.etag': 'deferred-etag'});
      String? sentIfNoneMatch;
      var headerSeen = false;
      final svc = UpdateService(
        client: MockClient((req) async {
          headerSeen = true;
          sentIfNoneMatch = req.headers['If-None-Match'];
          return http.Response(releaseJson('v0.12.0'), 200);
        }),
        isAndroidOverride: true,
      );
      final info = await svc.checkForUpdate(force: true);
      expect(headerSeen, isTrue);
      expect(sentIfNoneMatch, isNull); // no conditional request on the manual path
      expect(info, isNotNull);
      expect(info!.version, '0.12.0');
    });
  });
}
