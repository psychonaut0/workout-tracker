import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../l10n/app_localizations.dart';
import '../session/session_manager.dart';
import '../sync/db.dart';
import '../theme/app_theme.dart';
import '../theme/icons.dart';
import '../theme/typography.dart';
import '../theme/tokens.dart';
import '../units/unit_service.dart';
import '../util/format.dart';
import '../widgets/plan_form.dart';
import '../widgets/stepper.dart';
import '../widgets/w_dialog.dart';

/// Editor for a single exercise (create or edit).
///
/// [id] null → new exercise; non-null → edit existing.
/// Copy-on-edit: if the loaded exercise has [Exercise.isTemplate] == true,
/// a NEW draft is created (id=null) with a "Editing creates your own copy"
/// banner, and Save calls [ExerciseRepository.createExercise].
/// Owned exercises (isTemplate==false) edit in place via [updateExercise].
///
/// [onBack] is called after save so the parent returns to the list.
class ExerciseEditor extends StatefulWidget {
  const ExerciseEditor({
    super.key,
    required this.id,
    required this.onBack,
  });

  final String? id;
  final VoidCallback onBack;

  @override
  State<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<ExerciseEditor> {
  // ── load state ─────────────────────────────────────────────────────────────

  bool _loaded = false;
  String? _editId; // null = new exercise; non-null = existing exercise

  // ── draft fields ──────────────────────────────────────────────────────────

  late final TextEditingController _nameCtrl;
  late final TextEditingController _equipCtrl;
  late final TextEditingController _rirCtrl;

  String _muscleGroup = 'chest';
  bool _compound = false;

  // Start-weight in DISPLAY units (converted on load and on save).
  double _baseWeightDisplay = 0;
  double _stepDisplay = 2.5; // fromKg(plateStepKg, unit)

  // Store the original plateStepKg to recompute step when unit changes.
  double _plateStepKg = 2.5;

  // Prescription steppers
  int _repLow = 8;
  int _repHigh = 12;
  int _workSets = 3;
  int _warmupSets = 0;

  // Per-exercise rest (seconds); 0 = "Default" = null (use the global default).
  int _restSeconds = 0;

  // PR (kg, 0 = no PR)
  double _prKg = 0;

  // Extra muscle chip: if the loaded exercise's muscleGroup is outside the 8
  // canonical keys, we include it so editing doesn't silently remap it.
  String? _extraMuscle;

  bool _saving = false;

  ExerciseRepository get _repo => ExerciseRepository(db);

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _equipCtrl = TextEditingController();
    _rirCtrl = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _equipCtrl.dispose();
    _rirCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final unit = context.read<UnitService>().unit;

    if (widget.id == null) {
      // New exercise — start with defaults.
      final stepDisplay = UnitService.fromKg(_plateStepKg, unit);
      if (mounted) {
        setState(() {
          _editId = null;
          _muscleGroup = 'chest';
          _compound = false;
          _baseWeightDisplay = 0;
          _stepDisplay = stepDisplay;
          _rirCtrl.text = '1';
          _loaded = true;
        });
      }
      return;
    }

    // Load existing exercise + PR.
    final ex = await _repo.byId(widget.id!);
    if (!mounted) return;

    if (ex == null) {
      // Not found — treat as new.
      setState(() {
        _editId = null;
        _loaded = true;
      });
      return;
    }

    // Fetch PR from the one-shot map.
    final prMap = await _repo.prTopSets();
    if (!mounted) return;

    final prKg = prMap[ex.id] ?? 0;

    // Store plateStepKg for unit-change recomputation.
    final plateStep = ex.plateStepKg;
    final baseKg = ex.baseWeightKg ?? 0;
    final baseDisplay = UnitService.fromKg(baseKg, unit);
    final stepDisplay = UnitService.fromKg(plateStep, unit);

    // Extra muscle chip: include if not in the 8 canonical groups.
    final extra = kMuscleLabels.containsKey(ex.muscleGroup)
        ? null
        : ex.muscleGroup;

    // RIR display string.
    final rirText = (ex.defaultRirLow != null && ex.defaultRirHigh != null)
        ? rirToString(ex.defaultRirLow!, ex.defaultRirHigh!)
        : '1';

    setState(() {
      _editId = ex.id;
      _nameCtrl.text = ex.name;
      _equipCtrl.text = ex.equip ?? '';
      _muscleGroup = ex.muscleGroup;
      _compound = ex.compound;
      _plateStepKg = plateStep;
      _baseWeightDisplay = baseDisplay;
      _stepDisplay = stepDisplay;
      _repLow = ex.defaultRepLow ?? 8;
      _repHigh = ex.defaultRepHigh ?? 12;
      _workSets = ex.defaultWorkingSets ?? 3;
      _warmupSets = ex.defaultWarmupSets ?? 0;
      _restSeconds = ex.defaultRestSeconds ?? 0;
      _rirCtrl.text = rirText;
      _prKg = prKg;
      _extraMuscle = extra;
      _loaded = true;
    });
  }

  // ── unit change ────────────────────────────────────────────────────────────

  /// When unit changes we must recompute the display values.
  /// Called from build (didChangeDependencies would fire too late).
  Unit? _lastUnit;

  void _syncUnit(Unit unit) {
    if (_lastUnit == unit) return;
    if (_lastUnit != null) {
      // Convert existing display value to new unit.
      final kg = UnitService.toKg(_baseWeightDisplay, _lastUnit!);
      _baseWeightDisplay = UnitService.fromKg(kg, unit);
      _stepDisplay = UnitService.fromKg(_plateStepKg, unit);
    }
    _lastUnit = unit;
  }

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final unit = context.read<UnitService>().unit;

    // Convert display weight back to kg; 0 → null (write NULL, not 0.00).
    final baseKg = _baseWeightDisplay <= 0
        ? null
        : UnitService.toKg(_baseWeightDisplay, unit);

    // Parse RIR (non-throwing; if fails keep null).
    final rir = rirTryParse(_rirCtrl.text);

    final draft = ExerciseDraft(
      name: _nameCtrl.text.trim(),
      muscleGroup: _muscleGroup,
      equip: _equipCtrl.text.trim().isEmpty ? null : _equipCtrl.text.trim(),
      compound: _compound,
      baseWeightKg: baseKg,
      plateStepKg: _plateStepKg,
      defaultRepLow: _repLow,
      defaultRepHigh: _repHigh,
      defaultWarmupSets: _warmupSets,
      defaultWorkingSets: _workSets,
      defaultRirLow: rir?.low,
      defaultRirHigh: rir?.high,
      defaultRestSeconds: _restSeconds == 0 ? null : _restSeconds,
    );

    if (_editId != null) {
      await _repo.updateExercise(_editId!, draft);
    } else {
      await _repo.createExercise(draft);
    }

    if (mounted) widget.onBack();
  }

  // ── delete ───────────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    final id = _editId;
    if (id == null) return;
    final l = AppLocalizations.of(context);

    // Deleting an exercise used by the live workout draft would lose data at
    // finish (its sets PUT would hit a server FK on the now-deleted exercise
    // and be skipped). Require finishing/discarding the active workout first.
    if (context.read<SessionManager>().hasActive) {
      await showWDialog<bool>(
        context,
        title: l.exerciseEditorCantDeleteTitle,
        message: l.exerciseEditorActiveWorkoutMessage,
        actions: [WDialogAction(label: l.commonOk, value: true)],
      );
      return;
    }

    final refs = await _repo.exerciseReferences(id);
    if (!mounted) return;

    final action =
        decideExerciseDelete(setCount: refs.setCount, dayCount: refs.dayCount);
    switch (action) {
      case ExerciseDeleteAction.blockedByHistory:
        await showWDialog<bool>(
          context,
          title: l.exerciseEditorCantDeleteTitle,
          message: l.exerciseEditorBlockedByHistory(refs.setCount),
          actions: [WDialogAction(label: l.commonOk, value: true)],
        );
        return;
      case ExerciseDeleteAction.confirmWithDays:
        final ok = await showWConfirm(
          context,
          title: l.exerciseEditorDeleteTitle,
          message: l.exerciseEditorDeleteWithDays(refs.dayCount),
          confirmLabel: l.commonDelete,
          destructive: true,
        );
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: true);
      case ExerciseDeleteAction.confirmPlain:
        final ok = await showWConfirm(
          context,
          title: l.exerciseEditorDeleteTitle,
          message: l.exerciseEditorDeletePlain,
          confirmLabel: l.commonDelete,
          destructive: true,
        );
        if (ok != true) return;
        await _repo.deleteExercise(id, removeFromDays: false);
    }
    if (mounted) widget.onBack();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final units = context.watch<UnitService>();
    _syncUnit(units.unit);

    final tokens = context.tokens;

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final canSave = _nameCtrl.text.trim().isNotEmpty;
    final isNew = _editId == null;
    final btnLabel = isNew ? l.exerciseEditorCreate : l.exerciseEditorSave;

    // Build muscle chip list: 8 canonical groups + optional extra.
    final muscleItems = [
      ...kMuscleLabels.keys,
      if (_extraMuscle != null && !kMuscleLabels.containsKey(_extraMuscle))
        _extraMuscle!,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, kBottomNavInset),
      children: [
        // ── Identity ──────────────────────────────────────────────────────

        Field(
          label: l.exerciseEditorName,
          child: TextInput(
            controller: _nameCtrl,
            placeholder: l.exerciseEditorNamePlaceholder,
            onChanged: (_) => setState(() {}),
          ),
        ),

        Field(
          label: l.exerciseEditorMuscleGroup,
          child: ChipSelect<String>(
            items: muscleItems,
            selected: _muscleGroup,
            onSelect: (v) => setState(() => _muscleGroup = v),
            labelOf: (m) => localizedMuscle(context, m),
          ),
        ),

        Field(
          label: l.exerciseEditorEquipment,
          child: TextInput(
            controller: _equipCtrl,
            placeholder: l.exerciseEditorEquipmentPlaceholder,
          ),
        ),

        // Compound toggle row
        Padding(
          padding: const EdgeInsets.only(bottom: 16, top: 4, left: 2, right: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.exerciseEditorCompound,
                      style: WorkoutType.body(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.exerciseEditorCompoundHint,
                      style: WorkoutType.mono(
                        size: 10.5,
                        color: tokens.faint,
                      ),
                    ),
                  ],
                ),
              ),
              Toggle(
                value: _compound,
                onChanged: (v) {
                  setState(() {
                    _compound = v;
                    // Turning ON seeds defaultWarmupSets = 2 if null/0.
                    if (v && _warmupSets == 0) _warmupSets = 2;
                    // Leave untouched when toggling off.
                  });
                },
              ),
            ],
          ),
        ),

        // ── Stats (read-only) ──────────────────────────────────────────────

        PlanSection(
          l.exerciseEditorStats,
          hint: l.exerciseEditorStatsHint,
        ),

        // PR card
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(15 * 0.6),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.surface3,
                  borderRadius: BorderRadius.circular(15 * 0.5),
                ),
                alignment: Alignment.center,
                child: Icon(WIcons.bolt, size: 18, color: tokens.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.exerciseEditorPr,
                      style: WorkoutType.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l.exerciseEditorPrHint,
                      style: WorkoutType.mono(
                        size: 10.5,
                        color: tokens.faint,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _prKg > 0
                    ? '${units.fmtWt(_prKg)}${units.uLabel}'
                    : '–',
                style: WorkoutType.mono(
                  size: 15,
                  weight: FontWeight.w700,
                  color: _prKg > 0 ? tokens.text : tokens.faint,
                ),
              ),
            ],
          ),
        ),

        // Start-weight stepper in DISPLAY units.
        // step = fromKg(plateStepKg, unit) — NOT raw plateStepKg.
        Field(
          label: l.exerciseEditorStartWeight,
          hint: l.exerciseEditorStartWeightHint,
          child: WStepper(
            value: _baseWeightDisplay,
            step: _stepDisplay,
            format: (v) => '${fmtPlain(v)}${units.uLabel}',
            onChanged: (v) {
              setState(() => _baseWeightDisplay = v < 0 ? 0 : v);
            },
          ),
        ),

        // ── Default prescription ───────────────────────────────────────────

        PlanSection(
          l.exerciseEditorDefaultPrescription,
          hint: l.exerciseEditorDefaultPrescriptionHint,
        ),

        // Rep low + Rep high
        Row(
          children: [
            Expanded(
              child: Field(
                label: l.dayEditorRepLow,
                child: WStepper(
                  value: _repLow.toDouble(),
                  step: 1,
                  format: (v) => v.round().toString(),
                  onChanged: (v) {
                    final low = v.round().clamp(1, 99);
                    setState(() {
                      _repLow = low;
                      if (_repHigh < low) _repHigh = low;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Field(
                label: l.dayEditorRepHigh,
                child: WStepper(
                  value: _repHigh.toDouble(),
                  step: 1,
                  format: (v) => v.round().toString(),
                  onChanged: (v) {
                    final high = v.round().clamp(_repLow, 99);
                    setState(() => _repHigh = high);
                  },
                ),
              ),
            ),
          ],
        ),

        // Working sets + Warmups
        Row(
          children: [
            Expanded(
              child: Field(
                label: l.dayEditorWorkingSets,
                child: WStepper(
                  value: _workSets.toDouble(),
                  step: 1,
                  format: (v) => v.round().toString(),
                  onChanged: (v) {
                    setState(() => _workSets = v.round().clamp(1, 99));
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Field(
                label: l.dayEditorWarmups,
                child: WStepper(
                  value: _warmupSets.toDouble(),
                  step: 1,
                  format: (v) => v.round().toString(),
                  onChanged: (v) {
                    setState(() => _warmupSets = v.round().clamp(0, 99));
                  },
                ),
              ),
            ),
          ],
        ),

        // Per-exercise rest — 0 = "Default" = inherit the global rest default.
        Field(
          label: l.exerciseEditorRest,
          hint: l.exerciseEditorRestHint,
          child: WStepper(
            value: _restSeconds.toDouble(),
            step: 15,
            format: (v) => v == 0
                ? l.exerciseEditorRestDefault
                : l.exerciseEditorRestSeconds(v.round()),
            onChanged: (v) =>
                setState(() => _restSeconds = v.round() < 0 ? 0 : v.round()),
          ),
        ),

        // RIR target — raw text, parsed via rirTryParse on save only.
        Field(
          label: l.dayEditorRirTarget,
          child: TextInput(
            controller: _rirCtrl,
            placeholder: '1',
            // Do NOT parse on change — rirParse throws on partial input.
          ),
        ),

        // ── Primary action ─────────────────────────────────────────────────

        PrimaryBtn(
          btnLabel,
          enabled: canSave && !_saving,
          onTap: _save,
        ),

        if (_editId != null) ...[
          const SizedBox(height: 10),
          _DeleteButton(tokens: tokens, onTap: _delete),
        ],
      ],
    );
  }
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
              l.exerciseEditorDeleteButton,
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

