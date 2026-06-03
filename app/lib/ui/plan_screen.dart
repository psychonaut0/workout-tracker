import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'day_editor.dart';
import 'exercise_editor.dart';
import 'exercise_library_tab.dart';
import 'split_tab.dart';
import 'targets_tab.dart';

// ── Editor-route state ────────────────────────────────────────────────────

/// Describes which in-place editor is currently open.
/// [kind] is `'day'` or `'exercise'`; [id] is the row id (null = new).
class _EditorRoute {
  const _EditorRoute({required this.kind, required this.id});
  final String kind; // 'day' | 'exercise'
  final String? id;
}

// ── PlanScreen ────────────────────────────────────────────────────────────

/// The Plan tab: a header + Split|Exercises segmented toggle + in-place
/// editor routing — all within the one IndexedStack slot (no root Navigator
/// push).
///
/// Body routing via [_editor]:
///   - null              → list level: shows SplitTab or LibraryTab
///   - kind=='day'       → DayEditor
///   - kind=='exercise'  → ExerciseEditor
///
/// [_activeTab] tracks 'split' | 'exercises' while at the list level.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => PlanScreenState();
}

class PlanScreenState extends State<PlanScreen> {
  /// Currently open in-place editor (null = list view).
  _EditorRoute? _editor;

  /// Active sub-tab while at the list level.
  String _activeTab = 'split';

  void _openEditor(_EditorRoute route) => setState(() => _editor = route);

  void _onBack() => setState(() => _editor = null);

  /// Consumes a back press when the in-tab editor is open. Returns true if handled.
  bool handleBack() {
    if (_editor == null) return false;
    _onBack();
    return true;
  }

  // ── Derived title ─────────────────────────────────────────────────────────

  String get _title {
    if (_editor == null) return 'Plan';
    if (_editor!.kind == 'day') {
      return _editor!.id != null ? 'Edit training day' : 'New training day';
    }
    return _editor!.id != null ? 'Edit exercise' : 'New exercise';
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, WorkoutTokens tokens) {
    final topPad = MediaQuery.paddingOf(context).top;

    return Container(
      color: tokens.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top safe-area + title row
          Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  // Leading: back chevron (editor open) or plan icon tile
                  if (_editor != null)
                    _BackButton(tokens: tokens, onBack: _onBack)
                  else
                    _PlanIconTile(tokens: tokens),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: WorkoutType.display(
                        size: 19,
                        weight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Segmented toggle — shown only at list level
          if (_editor == null)
            _SegmentedToggle(
              activeTab: _activeTab,
              tokens: tokens,
              onSelect: (tab) => setState(() => _activeTab = tab),
            ),

          // Bottom border
          Divider(height: 1, thickness: 1, color: tokens.line),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_editor != null) {
      if (_editor!.kind == 'day') {
        return DayEditor(id: _editor!.id, onBack: _onBack);
      }
      return ExerciseEditor(id: _editor!.id, onBack: _onBack);
    }
    if (_activeTab == 'split') {
      return SplitTab(
        onOpenEditor: (id) => _openEditor(_EditorRoute(kind: 'day', id: id)),
      );
    }
    if (_activeTab == 'targets') {
      return const TargetsTab();
    }
    return LibraryTab(
      onOpenEditor: (id) => _openEditor(_EditorRoute(kind: 'exercise', id: id)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.bg,
      child: Column(
        children: [
          _buildHeader(context, tokens),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton({required this.tokens, required this.onBack});
  final WorkoutTokens tokens;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onBack,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.line),
          color: tokens.surface,
        ),
        child: Transform.rotate(
          angle: 3.14159, // 180° = point left
          child: Icon(WIcons.chevron, size: 18, color: tokens.dim),
        ),
      ),
    );
  }
}

class _PlanIconTile extends StatelessWidget {
  const _PlanIconTile({required this.tokens});
  final WorkoutTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36 * 0.55),
        color: tokens.surface3,
      ),
      child: Icon(WIcons.plan, size: 20, color: tokens.accent),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle({
    required this.activeTab,
    required this.tokens,
    required this.onSelect,
  });

  final String activeTab;
  final WorkoutTokens tokens;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _SegBtn(
            label: 'Split',
            active: activeTab == 'split',
            tokens: tokens,
            onTap: () => onSelect('split'),
          ),
          const SizedBox(width: 6),
          _SegBtn(
            label: 'Exercises',
            active: activeTab == 'exercises',
            tokens: tokens,
            onTap: () => onSelect('exercises'),
          ),
          const SizedBox(width: 6),
          _SegBtn(
            label: 'Targets',
            active: activeTab == 'targets',
            tokens: tokens,
            onTap: () => onSelect('targets'),
          ),
        ],
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool active;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36 * 0.6),
            color: active ? tokens.surface3 : Colors.transparent,
            border: Border.all(color: active ? tokens.lineStrong : tokens.line),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: tokens.lineStrong,
                      blurRadius: 0,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: WorkoutType.mono(
              size: 12.5,
              weight: FontWeight.w700,
              color: active ? tokens.text : tokens.faint,
            ),
          ),
        ),
      ),
    );
  }
}
