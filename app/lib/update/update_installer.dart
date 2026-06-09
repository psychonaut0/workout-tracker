import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';

/// Progress callback: 0..100 download percent, or -1 once the OS installer is
/// launched (treat as success — the standard path doesn't emit a done event).
typedef OtaProgress = void Function(int percent);

class UpdateInstaller {
  static const _channel = MethodChannel('reps/updates');

  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    return (await _channel.invokeMethod<bool>('canRequestInstalls')) ?? false;
  }

  Future<void> openInstallSettings() =>
      _channel.invokeMethod('openInstallSettings');

  /// Downloads [apkUrl] and launches the installer. Yields the download percent,
  /// then -1 when installing. Throws on download/permission errors so the UI can react.
  Stream<int> install(String apkUrl) async* {
    final controller =
        OtaUpdate().execute(apkUrl, destinationFilename: 'reps-update.apk');
    await for (final e in controller) {
      switch (e.status) {
        case OtaStatus.DOWNLOADING:
          yield int.tryParse(e.value ?? '') ?? 0;
        case OtaStatus.INSTALLING:
          yield -1; // installer launched
          return;
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          throw const UpdatePermissionException();
        case OtaStatus.DOWNLOAD_ERROR:
        case OtaStatus.INTERNAL_ERROR:
        case OtaStatus.CHECKSUM_ERROR:
        case OtaStatus.INSTALLATION_ERROR:
          throw UpdateInstallException(e.status.toString());
        case OtaStatus.ALREADY_RUNNING_ERROR:
        case OtaStatus.CANCELED:
        case OtaStatus.INSTALLATION_DONE:
          return;
      }
    }
  }
}

class UpdatePermissionException implements Exception {
  const UpdatePermissionException();
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.detail);
  final String detail;
}
