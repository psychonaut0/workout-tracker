import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/w_dialog.dart';
import 'update_installer.dart';
import 'update_service.dart';

/// Longest update-notes body we render in the dialog (truncated with an
/// ellipsis past this), so long GitHub release bodies don't overflow.
const _maxNotesChars = 400;

String _truncateNotes(String notes) {
  final t = notes.trim();
  if (t.length <= _maxNotesChars) return t;
  return '${t.substring(0, _maxNotesChars).trimRight()}…';
}

/// Entry point for the "update available" flow. Shows the available-update
/// dialog; on Install, checks install permission (explainer round-trip if
/// missing) and otherwise drives the download/install progress dialog.
///
/// Import-safe off-Android: the channel calls inside [UpdateInstaller] only run
/// on Android, and callers gate the entry points (Profile Check button, launch
/// auto-check) to Android.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final l = AppLocalizations.of(context);

  final proceed = await showWDialog<bool>(
    context,
    title: l.updatesAvailableTitle(info.version),
    message: _truncateNotes(info.notes),
    actions: [
      WDialogAction(label: l.updatesLater, value: false),
      WDialogAction(label: l.updatesInstall, value: true),
    ],
  );
  if (proceed != true) return;
  if (!context.mounted) return;

  final installer = UpdateInstaller();
  if (!await installer.canInstall()) {
    if (!context.mounted) return;
    await _showPermissionExplainer(context, installer);
    // Do NOT await the system settings screen — the user re-taps Install after
    // granting the permission.
    return;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(installer: installer, apkUrl: info.apkUrl),
  );
}

Future<void> _showPermissionExplainer(
  BuildContext context,
  UpdateInstaller installer,
) async {
  final l = AppLocalizations.of(context);
  final open = await showWDialog<bool>(
    context,
    title: l.updatesPermissionTitle,
    message: l.updatesPermissionMessage,
    actions: [
      WDialogAction(label: l.updatesLater, value: false),
      WDialogAction(label: l.updatesOpenSettings, value: true),
    ],
  );
  if (open == true) await installer.openInstallSettings();
}

/// Non-dismissible progress dialog: a linear bar + label driven by
/// [UpdateInstaller.install]. Owns the stream subscription so it cancels on
/// dispose, and pops itself when the installer launches or on error.
class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.installer, required this.apkUrl});

  final UpdateInstaller installer;
  final String apkUrl;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  StreamSubscription<int>? _sub;
  int _percent = 0; // -1 == installing (OS installer launched)
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.installer.install(widget.apkUrl).listen(
      (p) {
        if (mounted) setState(() => _percent = p);
      },
      onError: _onError,
      onDone: () {
        // Stream completed (installer launched / cancelled / done) — close the
        // progress dialog so the OS installer is in front.
        _pop();
      },
    );
  }

  void _onError(Object error) {
    if (error is UpdatePermissionException) {
      _pop();
      final ctx = context;
      if (ctx.mounted) _showPermissionExplainer(ctx, widget.installer);
      return;
    }
    // UpdateInstallException / any other error.
    _pop();
    final ctx = context;
    if (ctx.mounted) {
      final l = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.updatesError)),
      );
    }
  }

  void _pop() {
    if (_popped) return;
    _popped = true;
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() {
    OtaUpdate().cancel();
    _pop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l = AppLocalizations.of(context);
    final installing = _percent < 0;
    final label = installing
        ? l.updatesInstalling
        : l.updatesDownloading(_percent);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: WorkoutType.body(size: 14, color: tokens.text)),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: installing ? null : _percent / 100,
                    minHeight: 6,
                    backgroundColor: tokens.surface3,
                    valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cancel,
                  child: Text(
                    l.commonCancel,
                    style: WorkoutType.mono(size: 13, color: tokens.dim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
