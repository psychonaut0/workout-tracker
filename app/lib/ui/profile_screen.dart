import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../data/bodyweight_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../settings/settings_service.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../units/unit_service.dart';
import '../widgets/plan_form.dart';
import '../widgets/w_dialog.dart';
import 'login_screen.dart';

/// First-sign-in reconciliation choice when local data already exists.
enum _ReconcileChoice { keep, discard }

// ── Group + Row helpers (mirror screen-profile.jsx) ──────────────────────────

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text(
              label.toUpperCase(),
              style: WorkoutType.mono(
                size: 10.5,
                weight: FontWeight.w600,
                color: tokens.faint,
                letterSpacing: 0.1 * 10.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border.all(color: tokens.line),
              borderRadius: BorderRadius.circular(AppRadius.radius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, thickness: 1, color: tokens.line),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.sub,
    this.right,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? sub;
  final Widget? right;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final r = AppRadius.radius * 0.5;

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.surface3,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Icon(
              icon,
              size: 18,
              color: danger ? tokens.danger : tokens.accent,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: WorkoutType.body(
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: danger ? tokens.danger : tokens.text,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkoutType.mono(size: 10.5, color: tokens.faint),
                  ),
                ],
              ],
            ),
          ),
          if (right != null) ...[
            const SizedBox(width: 8),
            right!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      row = GestureDetector(onTap: onTap, child: row);
    }

    return row;
  }
}

// ── Quick-stats card ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(AppRadius.radius),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: WorkoutType.display(
                size: 20,
                weight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label.toUpperCase(),
              style: WorkoutType.mono(
                size: 9,
                color: tokens.faint,
                letterSpacing: 0.06 * 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ProfileScreen ─────────────────────────────────────────────────────────────

/// Full-screen Profile & Settings overlay, pushed on the root navigator.
///
/// Exposes:
///   • Editable profile name → SettingsService
///   • Quick stats (Sessions / PRs / Bodyweight) from the local DB
///   • Units chip (kg / lb) → UnitService
///   • Theme chip (Dark / Light) + 4 accent swatches → SettingsService
///   • Configurable server URL → confirm → setServerUrl + apiBaseUrl, then
///     onLogout first, onClose second (safe teardown order)
///   • Account: signed-in email + Sign out (danger, confirm)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onClose,
    required this.onLogout,
    required this.auth,
  });

  final VoidCallback onClose;
  final Future<void> Function() onLogout;
  final AuthStore auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Name editing state
  bool _editingName = false;
  late final TextEditingController _nameCtrl;

  // Server URL field
  late final TextEditingController _serverCtrl;
  String _currentServerUrl = '';

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _nameCtrl = TextEditingController(text: settings.profileName);
    _serverCtrl = TextEditingController(text: settings.serverUrl);
    _currentServerUrl = settings.serverUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    final letters = words
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();
    return letters.isEmpty ? 'A' : letters.toUpperCase();
  }

  void _submitName(SettingsService settings) {
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isNotEmpty) {
      settings.setProfileName(trimmed);
    }
    setState(() => _editingName = false);
  }

  // ── Server-switch flow ────────────────────────────────────────────────────

  Future<void> _applyServer(SettingsService settings) async {
    final url = _serverCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) return;

    final confirmed = await showWConfirm(
      context,
      title: 'Switch server?',
      message: 'This signs you out and clears local data on this device.',
      confirmLabel: 'Switch',
      destructive: true,
    );

    if (confirmed != true) return;

    // Persist new URL and update the global apiBaseUrl.
    await settings.setServerUrl(url);
    apiBaseUrl = url;

    // onLogout first (flips _loggedIn → swaps AppShell for LoginScreen while
    // AppShell is still live), then onClose (pops overlay — harmless no-op
    // once the parent route is gone).
    await widget.onLogout();
    widget.onClose();
  }

  // ── Sign-in flow (when signed out) ─────────────────────────────────────────

  Future<void> _signIn(SettingsService settings) async {
    final url = _serverCtrl.text.trim();
    // Login (auth_store) hits the global apiBaseUrl, so it must point at the
    // entered URL before we push LoginScreen. We do NOT persist it yet —
    // settings.setServerUrl is deferred into onLoggedIn so abandoning login
    // leaves no persisted change.
    apiBaseUrl = url;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute(
      builder: (_) => LoginScreen(
        auth: widget.auth,
        onLoggedIn: () async {
          // Persist the URL only now that login succeeded.
          await settings.setServerUrl(url);
          apiBaseUrl = url;

          // Reconcile local data before enabling sync. If anything exists on
          // this device (a session's user_id, or any exercise), ask whether to
          // keep it (merge) or use the account's data (discard local).
          final hasLocal =
              (await SessionRepository(db).anyUserId()) != null ||
              (await db.getOptional('SELECT 1 FROM exercises LIMIT 1')) != null;

          if (hasLocal) {
            // The captured NavigatorState outlives the async gaps; guard its
            // context before using it so we don't trip
            // use_build_context_synchronously.
            if (!navigator.mounted) return;
            final choice = await showWDialog<_ReconcileChoice>(
              navigator.context,
              title: 'You have local data',
              message:
                  'This device already has workout data. Keep it and merge with '
                  "your account, or replace it with the account's data?",
              actions: const [
                WDialogAction(
                  label: "Use the account's data",
                  value: _ReconcileChoice.discard,
                  destructive: true,
                ),
                WDialogAction(label: 'Keep my data', value: _ReconcileChoice.keep),
              ],
            );

            // Dialog dismissed (barrier/back) → cancel: stay local, no sync.
            if (choice == null) return;

            if (choice == _ReconcileChoice.discard) {
              await disconnectAndClear();
            }
          }

          await settings.setSyncEnabled(true);
          await connectSync(widget.auth);
          navigator.pop();
        },
      ),
    ));

    if (mounted) setState(() {});
  }

  // ── Sign-out flow ─────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    final confirmed = await showWConfirm(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access your data.',
      confirmLabel: 'Sign out',
    );

    if (confirmed != true) return;

    await widget.onLogout();
    widget.onClose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final unitService = context.watch<UnitService>();
    final tokens = context.tokens;

    // Keep _currentServerUrl in sync when settings change externally.
    if (_currentServerUrl != settings.serverUrl &&
        _serverCtrl.text == _currentServerUrl) {
      _serverCtrl.text = settings.serverUrl;
      _currentServerUrl = settings.serverUrl;
    }

    final serverChanged =
        _serverCtrl.text.trim() != settings.serverUrl &&
        _serverCtrl.text.trim().isNotEmpty;

    final signedIn = widget.auth.email != null;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: tokens.bg,
              border: Border(bottom: BorderSide(color: tokens.line)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.line),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          color: tokens.surface,
                        ),
                        child: Icon(
                          WIcons.back,
                          size: 18,
                          color: tokens.dim,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Profile',
                      style: WorkoutType.display(
                        size: 19,
                        weight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 104),
              children: [
                // ── Profile header ──────────────────────────────────────────
                _buildProfileHeader(settings, tokens),

                const SizedBox(height: 22),

                // ── Quick stats ─────────────────────────────────────────────
                _buildQuickStats(unitService, tokens),

                const SizedBox(height: 22),

                // ── Units ───────────────────────────────────────────────────
                _Group(
                  label: 'Units',
                  children: [
                    _Row(
                      icon: WIcons.scale,
                      title: 'Weight unit',
                      sub: 'Applies everywhere',
                      right: ChipSelect<Unit>(
                        items: Unit.values,
                        selected: unitService.unit,
                        labelOf: (u) => u == Unit.kg ? 'kg' : 'lb',
                        onSelect: unitService.setUnit,
                      ),
                    ),
                  ],
                ),

                // ── Appearance ──────────────────────────────────────────────
                _Group(
                  label: 'Appearance',
                  children: [
                    _Row(
                      icon: settings.mode == 'dark'
                          ? WIcons.flame
                          : WIcons.bolt,
                      title: 'Theme',
                      right: ChipSelect<String>(
                        items: const ['dark', 'light'],
                        selected: settings.mode,
                        labelOf: (m) => m == 'dark' ? 'Dark' : 'Light',
                        onSelect: settings.setMode,
                      ),
                    ),
                    _Row(
                      icon: WIcons.target,
                      title: 'Accent',
                      sub: 'App highlight color',
                      right: _buildAccentSwatches(settings, tokens),
                    ),
                  ],
                ),

                // ── Sync & Backend ──────────────────────────────────────────
                _Group(
                  label: 'Sync & Backend',
                  children: [
                    _Row(
                      icon: WIcons.cloud,
                      title: 'Sync server',
                      sub: settings.serverUrl,
                      right: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: signedIn ? tokens.accent : tokens.faint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            signedIn ? 'Connected' : 'Not connected',
                            style: WorkoutType.mono(
                              size: 11,
                              weight: FontWeight.w600,
                              color: tokens.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextInput(
                            controller: _serverCtrl,
                            placeholder: 'https://sync.example.dev',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Local-first · data stays on device · syncs when connected',
                            style: WorkoutType.mono(
                              size: 10.5,
                              color: tokens.faint,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (signedIn)
                            PrimaryBtn(
                              'Apply / Switch server',
                              enabled: serverChanged,
                              onTap: () => _applyServer(settings),
                            )
                          else
                            PrimaryBtn(
                              'Sign in to sync',
                              enabled: true,
                              onTap: () => _signIn(settings),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Account ─────────────────────────────────────────────────
                if (signedIn)
                  _Group(
                    label: 'Account',
                    children: [
                      _Row(
                        icon: WIcons.user,
                        title: 'Signed in',
                        sub: widget.auth.email ?? '–',
                      ),
                      _Row(
                        icon: WIcons.logout,
                        title: 'Sign out',
                        danger: true,
                        onTap: _signOut,
                      ),
                    ],
                  ),

                // ── Version footer ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'workout-tracker · v1.0.0',
                    textAlign: TextAlign.center,
                    style: WorkoutType.mono(size: 10.5, color: tokens.faint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _buildProfileHeader(SettingsService settings, WorkoutTokens tokens) {
    return Row(
      children: [
        // 66px accent avatar
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: tokens.accent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(settings.profileName),
            style: WorkoutType.display(
              size: 26,
              weight: FontWeight.w700,
              color: tokens.accentInk,
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editingName)
                TextInput(
                  controller: _nameCtrl,
                  placeholder: 'Your name',
                  onChanged: (_) => setState(() {}),
                )
              else
                GestureDetector(
                  onTap: () => setState(() => _editingName = true),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          settings.profileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkoutType.display(
                            size: 23,
                            weight: FontWeight.w700,
                            color: tokens.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(WIcons.edit, size: 15, color: tokens.faint),
                    ],
                  ),
                ),
              if (_editingName) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _submitName(settings),
                  child: Text(
                    'Save',
                    style: WorkoutType.mono(
                      size: 11,
                      weight: FontWeight.w600,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 3),
                Text(
                  'Training since Mar 2026 · 4-day split',
                  style: WorkoutType.mono(size: 11, color: tokens.faint),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(UnitService unitService, WorkoutTokens tokens) {
    final sessionRepo = SessionRepository(db);
    final bwRepo = BodyweightRepository(db);

    return StreamBuilder<List<HistorySessionRow>>(
      stream: sessionRepo.watchSessionStats(),
      builder: (context, sessionSnap) {
        final sessions = sessionSnap.data ?? [];
        final sessionCount = sessions.length.toString();
        final prCount = sessions
            .fold<int>(0, (sum, s) => sum + s.prCount)
            .toString();

        return StreamBuilder<List<BodyweightEntry>>(
          stream: bwRepo.watchSeriesAsc(),
          builder: (context, bwSnap) {
            final bwEntries = bwSnap.data ?? [];
            final bwText = bwEntries.isEmpty
                ? '–'
                : '${unitService.fmtWt(bwEntries.last.weightKg)}${unitService.uLabel}';

            return Row(
              children: [
                _StatCard(label: 'Sessions', value: sessionCount),
                const SizedBox(width: 8),
                _StatCard(label: 'PRs', value: prCount),
                const SizedBox(width: 8),
                _StatCard(label: 'Bodyweight', value: bwText),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAccentSwatches(SettingsService settings, WorkoutTokens tokens) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: accents.map((color) {
        final isSelected = settings.accent == color;
        return Padding(
          padding: const EdgeInsets.only(left: 7),
          child: GestureDetector(
            onTap: () => settings.setAccent(color),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: isSelected ? tokens.text : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: tokens.bg,
                          spreadRadius: 2,
                          blurRadius: 0,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
