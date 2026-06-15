import 'package:flutter/material.dart';

import '../data/day_template_repository.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../l10n/app_localizations.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../util/dates.dart';
import '../widgets/plan_form.dart';
import '../widgets/stepper.dart';
import '../widgets/w_dialog.dart';
import 'exercise_sheet.dart';

// ── _SlotState ────────────────────────────────────────────────────────────────

/// Mutable UI state for a single slot row (wraps [SlotDraft] + RIR raw text).
class _SlotState {
  _SlotState({
    required this.draft,
    required this.rirText,
  });

  SlotDraft draft;

  // The RIR field keeps raw text; only parsed via rirTryParse on save.
  String rirText;

  String get exerciseId => draft.exerciseId;
}

_SlotState _slotStateFromResolved(ResolvedSlot r, String? itemId) {
  return _SlotState(
    draft: SlotDraft(
      itemId: itemId,
      exerciseId: r.exercise.id,
      workSets: r.workSets,
      warmupSets: r.warmupSets,
      repLow: r.repLow,
      repHigh: r.repHigh,
      rirLow: r.rirLow,
      rirHigh: r.rirHigh,
    ),
    rirText: rirToString(r.rirLow, r.rirHigh),
  );
}

// ── DayEditor ─────────────────────────────────────────────────────────────────

/// Editor for a single training day (create or edit).
///
/// [id] null → new day; non-null → edit existing.
/// [onBack] is called after save or delete so the parent can return to the list.
class DayEditor extends StatefulWidget {
  const DayEditor({
    super.key,
    required this.id,
    required this.onBack,
  });

  final String? id;
  final VoidCallback onBack;

  @override
  State<DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<DayEditor> {
  // ── lifecycle ─────────────────────────────────────────────────────────────

  bool _loaded = false;
  String? _editId; // null = new day; non-null = existing day

  late final TextEditingController _nameCtrl;
  late final TextEditingController _focusCtrl;
  int? _weekday; // 0=Mon … 6=Sun

  final List<_SlotState> _slots = [];
  String? _expandedExId; // keyed by exerciseId (NOT index)

  List<Exercise> _catalog = [];
  bool _saving = false;

  DayTemplateRepository get _dayRepo => DayTemplateRepository(db);
  ExerciseRepository get _exRepo => ExerciseRepository(db);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _focusCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _focusCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Load exercise catalog (needed for resolveSlot + exercise sheet).
    final catalog = await _exRepo.all();

    if (widget.id == null) {
      // New day — start blank.
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _editId = null;
          _loaded = true;
        });
      }
      return;
    }

    // Load existing day.
    final day = await _dayRepo.byId(widget.id!);
    if (!mounted) return;

    if (day == null) {
      // Day not found (edge case) — treat as new.
      setState(() {
        _catalog = catalog;
        _editId = null;
        _loaded = true;
      });
      return;
    }

    // Build exercise lookup.
    final exById = {for (final e in catalog) e.id: e};

    // Resolve slots.
    final slots = <_SlotState>[];
    for (final slot in day.slots) {
      final ex = exById[slot.exerciseId];
      if (ex == null) continue; // skip orphaned slots
      final resolved = resolveSlot(slot, ex);
      slots.add(_slotStateFromResolved(resolved, slot.id));
    }

    setState(() {
      _catalog = catalog;
      _editId = day.id;
      _nameCtrl.text = day.name;
      _focusCtrl.text = day.focus ?? '';
      _weekday = day.scheduledWeekday;
      _slots.addAll(slots);
      _loaded = true;
    });
  }

  // ── slot actions ──────────────────────────────────────────────────────────

  void _toggleSlot(String exId) {
    setState(() {
      _expandedExId = _expandedExId == exId ? null : exId;
    });
  }

  void _moveSlot(int index, int dir) {
    final j = index + dir;
    if (j < 0 || j >= _slots.length) return;
    setState(() {
      final tmp = _slots[index];
      _slots[index] = _slots[j];
      _slots[j] = tmp;
    });
  }

  void _removeSlot(int index) {
    final exId = _slots[index].exerciseId;
    setState(() {
      _slots.removeAt(index);
      if (_expandedExId == exId) _expandedExId = null;
    });
  }

  Future<void> _addExercise() async {
    final r = await showExerciseSheet(
      context,
      exercises: _catalog,
      current: null,
      showBodyweight: false,
    );
    if (r == null || r == kBodyweightSentinel) return;

    // Dedupe by exerciseId.
    if (_slots.any((s) => s.exerciseId == r)) return;

    final ex = _catalog.firstWhere(
      (e) => e.id == r,
      orElse: () => throw StateError('exercise $r not in catalog'),
    );
    final resolved = resolveSlot(
      Slot(exerciseId: r, position: _slots.length + 1),
      ex,
    );
    setState(() {
      _slots.add(_slotStateFromResolved(resolved, null));
    });
  }

  // ── save / delete ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    // Commit RIR text → rirLow/rirHigh for each slot using rirTryParse.
    for (final slot in _slots) {
      final parsed = rirTryParse(slot.rirText);
      if (parsed != null) {
        slot.draft.rirLow = parsed.low;
        slot.draft.rirHigh = parsed.high;
      }
      // If parse fails, keep existing rirLow/rirHigh values (prior valid state).
    }

    final draft = DayDraft(
      name: _nameCtrl.text.trim(),
      focus: _focusCtrl.text.trim().isEmpty ? null : _focusCtrl.text.trim(),
      weekday: _weekday,
      slots: _slots.map((s) => s.draft).toList(),
    );

    await _dayRepo.saveDay(id: _editId, draft: draft);
    if (mounted) widget.onBack();
  }

  Future<void> _delete() async {
    if (_editId == null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showWConfirm(
      context,
      title: l.dayEditorDeleteTitle,
      message: l.dayEditorDeleteMessage,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    await _dayRepo.deleteDay(_editId!);
    if (mounted) widget.onBack();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.tokens;
    final localeName = Localizations.localeOf(context).toLanguageTag();

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final canSave = _nameCtrl.text.trim().isNotEmpty;
    final isOwned = _editId != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, kBottomNavInset),
      children: [
        // ── Day name ──────────────────────────────────────────────────────
        Field(
          label: l.dayEditorName,
          child: TextInput(
            controller: _nameCtrl,
            placeholder: l.dayEditorNamePlaceholder,
            onChanged: (_) => setState(() {}),
          ),
        ),

        // ── Focus ─────────────────────────────────────────────────────────
        Field(
          label: l.dayEditorFocus,
          child: TextInput(
            controller: _focusCtrl,
            placeholder: l.dayEditorFocusPlaceholder,
          ),
        ),

        // ── Scheduled weekday ─────────────────────────────────────────────
        Field(
          label: l.dayEditorScheduledDay,
          child: ChipSelect<int>(
            items: List.generate(7, (i) => i),
            selected: _weekday,
            onSelect: (v) => setState(() => _weekday = v),
            labelOf: (i) => weekdayShort(i, localeName),
          ),
        ),

        // ── Slots section ─────────────────────────────────────────────────
        PlanSection(
          l.dayEditorExercisesCount(_slots.length),
          hint: l.dayEditorSlotHint,
        ),

        // Slot rows
        ..._slots.asMap().entries.map((entry) {
          final index = entry.key;
          final slot = entry.value;
          final ex = _catalog.firstWhere(
            (e) => e.id == slot.exerciseId,
            orElse: () => Exercise(
              id: slot.exerciseId,
              name: slot.exerciseId,
              slug: '',
              muscleGroup: '',
              compound: false,
              plateStepKg: 2.5,
              isTemplate: true,
            ),
          );
          return Reveal(
            key: ValueKey(slot.exerciseId),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _SlotRow(
                index: index,
                total: _slots.length,
                slot: slot,
                exercise: ex,
                tokens: tokens,
                expanded: _expandedExId == slot.exerciseId,
                onToggle: () => _toggleSlot(slot.exerciseId),
                onMove: (dir) => _moveSlot(index, dir),
                onRemove: () => _removeSlot(index),
                onChanged: () => setState(() {}),
              ),
            ),
          );
        }),

        const SizedBox(height: 3),

        // ── Add exercise button ───────────────────────────────────────────
        _AddExerciseButton(tokens: tokens, onTap: _addExercise),

        const SizedBox(height: 22),

        // ── Save button ───────────────────────────────────────────────────
        PrimaryBtn(
          isOwned ? l.dayEditorSaveChanges : l.dayEditorCreateDay,
          enabled: canSave && !_saving,
          onTap: _save,
        ),

        // ── Delete button (owned days only) ───────────────────────────────
        if (isOwned) ...[
          const SizedBox(height: 10),
          _DeleteButton(tokens: tokens, onTap: _delete),
        ],
      ],
    );
  }
}

// ── SlotRow ───────────────────────────────────────────────────────────────────

class _SlotRow extends StatefulWidget {
  const _SlotRow({
    required this.index,
    required this.total,
    required this.slot,
    required this.exercise,
    required this.tokens,
    required this.expanded,
    required this.onToggle,
    required this.onMove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final int total;
  final _SlotState slot;
  final Exercise exercise;
  final WorkoutTokens tokens;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int dir) onMove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends State<_SlotRow> {
  late final TextEditingController _rirCtrl;

  @override
  void initState() {
    super.initState();
    _rirCtrl = TextEditingController(text: widget.slot.rirText);
  }

  @override
  void didUpdateWidget(_SlotRow old) {
    super.didUpdateWidget(old);
    // Sync controller if the slot state changed externally (e.g. reorder).
    if (old.slot != widget.slot) {
      _rirCtrl.text = widget.slot.rirText;
    }
  }

  @override
  void dispose() {
    _rirCtrl.dispose();
    super.dispose();
  }

  void _updateWork(double v) {
    setState(() {
      widget.slot.draft.workSets = v.round().clamp(1, 99);
    });
    widget.onChanged();
  }

  void _updateWarmup(double v) {
    setState(() {
      widget.slot.draft.warmupSets = v.round().clamp(0, 99);
    });
    widget.onChanged();
  }

  void _updateRepLow(double v) {
    final low = v.round().clamp(1, 99);
    final high = (widget.slot.draft.repHigh ?? low);
    setState(() {
      widget.slot.draft.repLow = low;
      // Bump high if it would fall below low.
      if (high < low) widget.slot.draft.repHigh = low;
    });
    widget.onChanged();
  }

  void _updateRepHigh(double v) {
    final low = widget.slot.draft.repLow ?? 1;
    final high = v.round().clamp(low, 99);
    setState(() {
      widget.slot.draft.repHigh = high;
    });
    widget.onChanged();
  }

  String _collapsedLabel(AppLocalizations l) {
    final d = widget.slot.draft;
    final work = d.workSets ?? 3;
    final repLow = d.repLow ?? 8;
    final repHigh = d.repHigh ?? 12;
    final rirStr = rirToString(
      d.rirLow ?? 1,
      d.rirHigh ?? 1,
    );
    final warm = d.warmupSets ?? 0;
    final warmSuffix = warm > 0 ? ' · ${l.dayEditorWarmupShort(warm)}' : '';
    return '$work×$repLow–$repHigh · RIR $rirStr$warmSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = widget.tokens;
    final d = widget.slot.draft;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(
          color: widget.expanded ? tokens.lineStrong : tokens.line,
        ),
        borderRadius: BorderRadius.circular(AppRadius.radius * 0.6),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Index
                SizedBox(
                  width: 16,
                  child: Text(
                    '${widget.index + 1}',
                    style: WorkoutType.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: tokens.faint,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Name + summary (tappable to expand)
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onToggle,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.exercise.name,
                          overflow: TextOverflow.ellipsis,
                          style: WorkoutType.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _collapsedLabel(l),
                          style: WorkoutType.mono(
                            size: 10,
                            color: tokens.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Up/Down reorder buttons
                _ReorderBtn(
                  dir: -1,
                  disabled: widget.index == 0,
                  tokens: tokens,
                  onTap: () => widget.onMove(-1),
                ),
                _ReorderBtn(
                  dir: 1,
                  disabled: widget.index == widget.total - 1,
                  tokens: tokens,
                  onTap: () => widget.onMove(1),
                ),

                const SizedBox(width: 5),

                // Trash button
                GestureDetector(
                  onTap: widget.onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tokens.surface3,
                      borderRadius:
                          BorderRadius.circular(AppRadius.radius * 0.4),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      WIcons.trash,
                      size: 15,
                      color: tokens.faint,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Chevron (toggles expanded)
                GestureDetector(
                  onTap: widget.onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedRotation(
                    turns: widget.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      WIcons.chevron,
                      size: 16,
                      color: tokens.faint,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Expanded panel ────────────────────────────────────────────
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 13),
              child: Column(
                children: [
                  // Working sets + Warmups
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          label: l.dayEditorWorkingSets,
                          child: WStepper(
                            value: (d.workSets ?? 3).toDouble(),
                            step: 1,
                            format: (v) => v.round().toString(),
                            onChanged: _updateWork,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          label: l.dayEditorWarmups,
                          child: WStepper(
                            value: (d.warmupSets ?? 0).toDouble(),
                            step: 1,
                            format: (v) => v.round().toString(),
                            onChanged: _updateWarmup,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Rep low + Rep high
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          label: l.dayEditorRepLow,
                          child: WStepper(
                            value: (d.repLow ?? 8).toDouble(),
                            step: 1,
                            format: (v) => v.round().toString(),
                            onChanged: _updateRepLow,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          label: l.dayEditorRepHigh,
                          child: WStepper(
                            value: (d.repHigh ?? 12).toDouble(),
                            step: 1,
                            format: (v) => v.round().toString(),
                            onChanged: _updateRepHigh,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // RIR target — raw text field; parsed only on save
                  Field(
                    label: l.dayEditorRirTarget,
                    child: TextInput(
                      controller: _rirCtrl,
                      placeholder: '1',
                      onChanged: (v) {
                        widget.slot.rirText = v;
                        // Do NOT call rirParse here — it throws on partial input.
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Reorder button ────────────────────────────────────────────────────────────

class _ReorderBtn extends StatelessWidget {
  const _ReorderBtn({
    required this.dir,
    required this.disabled,
    required this.tokens,
    required this.onTap,
  });

  final int dir; // -1 = up, 1 = down
  final bool disabled;
  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUp = dir < 0;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          width: 28,
          height: 30,
          decoration: BoxDecoration(
            color: tokens.surface3,
            borderRadius: BorderRadius.only(
              topLeft: isUp
                  ? Radius.circular(AppRadius.radius * 0.4)
                  : Radius.zero,
              bottomLeft: isUp
                  ? Radius.circular(AppRadius.radius * 0.4)
                  : Radius.zero,
              topRight: isUp
                  ? Radius.zero
                  : Radius.circular(AppRadius.radius * 0.4),
              bottomRight: isUp
                  ? Radius.zero
                  : Radius.circular(AppRadius.radius * 0.4),
            ),
          ),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: isUp ? 0 : 2,
            child: Icon(
              WIcons.arrowUp,
              size: 13,
              color: disabled ? tokens.faint : tokens.dim,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add exercise button ───────────────────────────────────────────────────────

class _AddExerciseButton extends StatelessWidget {
  const _AddExerciseButton({required this.tokens, required this.onTap});

  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.radius * 0.6),
          color: Colors.transparent,
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: tokens.lineStrong),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(WIcons.plus, size: 15, color: tokens.dim),
              const SizedBox(width: 7),
              Text(
                l.dayEditorAddExercise,
                style: WorkoutType.mono(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: tokens.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    const r = AppRadius.radius * 0.6;

    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(r),
    );

    final path = Path()..addRRect(rRect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// ── Delete button ─────────────────────────────────────────────────────────────

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.tokens, required this.onTap});

  final WorkoutTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(WIcons.trash, size: 15, color: tokens.faint),
            const SizedBox(width: 6),
            Text(
              l.dayEditorDeleteButton,
              style: WorkoutType.mono(
                size: 12.5,
                weight: FontWeight.w600,
                color: tokens.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
