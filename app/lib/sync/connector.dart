import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

import '../auth/auth_store.dart';

/// Bridges PowerSync to the Go API.
///
/// - [fetchCredentials] mints a short-lived PowerSync token via
///   POST /auth/powersync-token (Bearer = ACCESS token). The response's
///   `endpoint` is POWERSYNC_URL (dev: http://localhost:8090) and `token` is an
///   RS256 JWT (aud workout-tracker-powersync, 5m). The SDK caches it and only
///   calls this again near expiry.
/// - [uploadData] drains the local CRUD queue and POSTs it to /sync/upload
///   using the ACCESS token (NOT the PowerSync token).
///
/// UPLOAD CONTRACT: the server always returns 2xx for bad/ownership-rejected
/// data (a thrown error or 4xx here would PERMANENTLY block the upload queue).
/// We therefore only rethrow on transient failures (network / 5xx) so the SDK
/// retries the same batch; on 2xx we complete the transaction.
class WorkoutConnector extends PowerSyncBackendConnector {
  WorkoutConnector(this.auth, {http.Client? client})
      : _http = client ?? http.Client();

  final AuthStore auth;
  final http.Client _http;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final access = await auth.ensureAccessToken();
    if (access == null) return null; // logged out -> SDK stays disconnected

    var res = await _postPowerSyncToken(access);
    if (res.statusCode == 401) {
      // Access token expired: rotate once and retry.
      final fresh = await auth.refresh();
      if (fresh == null) return null;
      res = await _postPowerSyncToken(fresh);
    }
    if (res.statusCode != 200) {
      throw Exception('powersync-token failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PowerSyncCredentials(
      endpoint: body['endpoint'] as String,
      token: body['token'] as String,
    );
  }

  Future<http.Response> _postPowerSyncToken(String accessToken) {
    return _http.post(
      Uri.parse('$apiBaseUrl/auth/powersync-token'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final tx = await database.getNextCrudTransaction();
    if (tx == null) return;

    // Build the batch in the exact shape the server expects:
    // {"batch":[{"op":"PUT|PATCH|DELETE","table":"<t>","id":"<uuid>","data":{...}}]}
    // CrudEntry.op.toJson() already yields "PUT"/"PATCH"/"DELETE".
    final batch = tx.crud
        .map((op) => {
              'op': op.op.toJson(),
              'table': op.table,
              'id': op.id,
              'data': op.opData ?? <String, dynamic>{},
            })
        .toList();

    final access = await auth.ensureAccessToken();
    if (access == null) {
      // No way to authenticate right now; throw so the SDK retries later
      // (transient from the queue's perspective — nothing is dropped).
      throw Exception('no access token for upload');
    }

    // A network error throws here and propagates: that is the transient case,
    // we do NOT complete, and the SDK retries the same batch later.
    final res = await _http.post(
      Uri.parse('$apiBaseUrl/sync/upload'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $access',
      },
      body: jsonEncode({'batch': batch}),
    );

    if (res.statusCode == 401) {
      // Access token expired mid-upload: refresh and let the SDK retry.
      await auth.refresh();
      throw Exception('upload unauthorized; refreshed, will retry');
    }
    if (res.statusCode >= 500) {
      // Transient server error: do not complete -> SDK retries the same batch.
      throw Exception('upload transient error (${res.statusCode})');
    }
    // Any 2xx (including silently-skipped bad ops) => batch accepted. Complete
    // so these ops leave the queue. 4xx is not expected per the contract, but
    // we also treat it as "accepted" to avoid permanently wedging the queue.
    await tx.complete();
  }
}
