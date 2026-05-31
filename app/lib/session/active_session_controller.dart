import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart' show uuid;

import '../data/active_session_draft.dart';
import '../data/day_template_repository.dart';
import '../data/exercise_repository.dart';
import '../data/models.dart';
import '../data/session_repository.dart';
import '../data/session_writer.dart';

// ── Pure helpers ─────────────────────────────────────────────────────────────

/// Rounds [v] to the nearest [step].
///
/// Example: `roundTo(38.75, 2.5) == 40.0`.
double roundTo(double v, double step) => (v / step).round() * step;

/// Builds a [BlockState] from a fully-resolved slot, seeding weights from
/// [lastTopKg] (or the exercise's base weight, or 20 as a last-resort floor
/// for custom exercises that have no base weight yet).
///
/// The warm-up ramp formula:
///   weight_i = roundTo(suggested * (0.5 + 0.18 * i), step)
///   reps_i   = max(1, 8 − 2*i)
///
/// Working sets use [suggested] weight, [repLow] reps, RIR 1.
BlockState buildBlock({
  required ResolvedSlot resolved,
  double? lastTopKg,
}) {
  final exercise = resolved.exercise;
  final step = exercise.plateStepKg;

  // Seed: last known top weight beats base; 20 is the custom-only floor —
  // the seeded catalog always has base_weight_kg after the trait migration.
  final seed = lastTopKg ?? exercise.baseWeightKg ?? 20.0;

  // Compound exercises bump one plate on top of the seed to encourage
  // progressive overload; isolation exercises stay at the seed.
  final suggested = roundTo(
    seed + (exercise.compound ? step : 0),
    step,
  );

  // Warm-up ramp
  final warmups = <SetState>[];
  for (var i = 0; i < resolved.warmupSets; i++) {
    warmups.add(SetState(
      id: uuid.v4(),
      weightKg: roundTo(suggested * (0.5 + 0.18 * i), step),
      reps: max(1, 8 - 2 * i),
      rir: null,
      isWarmup: true,
      done: false,
    ));
  }

  // Working sets
  final working = <SetState>[];
  for (var i = 0; i < resolved.workSets; i++) {
    working.add(SetState(
      id: uuid.v4(),
      weightKg: suggested,
      reps: resolved.repLow,
      rir: 1,
      isWarmup: false,
      done: false,
    ));
  }

  return BlockState(
    exercise: exercise,
    resolved: resolved,
    warmupSets: warmups,
    workingSets: working,
    expanded: true,
  );
}

// ── Data classes ─────────────────────────────────────────────────────────────

/// Mutable state for a single set during an active session.
class SetState {
  final String id;
  double weightKg;
  int reps;
  int? rir;
  final bool isWarmup;
  bool done;

  SetState({
    required this.id,
    required this.weightKg,
    required this.reps,
    required this.rir,
    required this.isWarmup,
    required this.done,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'weightKg': weightKg,
        'reps': reps,
        'rir': rir,
        'isWarmup': isWarmup,
        'done': done,
      };

  factory SetState.fromJson(Map<String, dynamic> json) => SetState(
        id: json['id'] as String,
        weightKg: (json['weightKg'] as num).toDouble(),
        reps: json['reps'] as int,
        rir: json['rir'] as int?,
        isWarmup: json['isWarmup'] as bool,
        done: json['done'] as bool,
      );
}

/// State for one exercise block (accordion) in the active session.
class BlockState {
  final Exercise exercise;
  final ResolvedSlot resolved;
  List<SetState> warmupSets;
  List<SetState> workingSets;
  bool expanded;

  /// The all-time best top-set weight for this exercise (loaded from the DB
  /// at session build time). Used for live PR detection.
  double? bestKg;

  BlockState({
    required this.exercise,
    required this.resolved,
    required this.warmupSets,
    required this.workingSets,
    required this.expanded,
    this.bestKg,
  });

  /// All sets in display order: warm-ups first, then working.
  List<SetState> get allSets => [...warmupSets, ...workingSets];

  Map<String, dynamic> toJson() => {
        'exerciseId': exercise.id,
        'exerciseName': exercise.name,
        'exerciseSlug': exercise.slug,
        'exerciseMuscleGroup': exercise.muscleGroup,
        'exerciseEquip': exercise.equip,
        'exerciseCompound': exercise.compound,
        'exerciseBaseWeightKg': exercise.baseWeightKg,
        'exercisePlateStepKg': exercise.plateStepKg,
        'exerciseDefaultRepLow': exercise.defaultRepLow,
        'exerciseDefaultRepHigh': exercise.defaultRepHigh,
        'exerciseDefaultWarmupSets': exercise.defaultWarmupSets,
        'exerciseDefaultWorkingSets': exercise.defaultWorkingSets,
        'exerciseDefaultRirLow': exercise.defaultRirLow,
        'exerciseDefaultRirHigh': exercise.defaultRirHigh,
        'resolvedWorkSets': resolved.workSets,
        'resolvedWarmupSets': resolved.warmupSets,
        'resolvedRepLow': resolved.repLow,
        'resolvedRepHigh': resolved.repHigh,
        'resolvedRirLow': resolved.rirLow,
        'resolvedRirHigh': resolved.rirHigh,
        'warmupSets': warmupSets.map((s) => s.toJson()).toList(),
        'workingSets': workingSets.map((s) => s.toJson()).toList(),
        'expanded': expanded,
        'bestKg': bestKg,
      };

  factory BlockState.fromJson(Map<String, dynamic> json) {
    final exercise = Exercise(
      id: json['exerciseId'] as String,
      name: json['exerciseName'] as String,
      slug: json['exerciseSlug'] as String? ?? '',
      muscleGroup: json['exerciseMuscleGroup'] as String? ?? '',
      equip: json['exerciseEquip'] as String?,
      compound: json['exerciseCompound'] as bool? ?? false,
      baseWeightKg: (json['exerciseBaseWeightKg'] as num?)?.toDouble(),
      plateStepKg: (json['exercisePlateStepKg'] as num?)?.toDouble() ?? 2.5,
      defaultRepLow: json['exerciseDefaultRepLow'] as int?,
      defaultRepHigh: json['exerciseDefaultRepHigh'] as int?,
      defaultWarmupSets: json['exerciseDefaultWarmupSets'] as int?,
      defaultWorkingSets: json['exerciseDefaultWorkingSets'] as int?,
      defaultRirLow: json['exerciseDefaultRirLow'] as int?,
      defaultRirHigh: json['exerciseDefaultRirHigh'] as int?,
      isTemplate: false,
    );
    final resolved = ResolvedSlot(
      exercise: exercise,
      workSets: json['resolvedWorkSets'] as int,
      warmupSets: json['resolvedWarmupSets'] as int,
      repLow: json['resolvedRepLow'] as int,
      repHigh: json['resolvedRepHigh'] as int,
      rirLow: json['resolvedRirLow'] as int,
      rirHigh: json['resolvedRirHigh'] as int,
    );
    return BlockState(
      exercise: exercise,
      resolved: resolved,
      warmupSets: (json['warmupSets'] as List)
          .map((e) => SetState.fromJson(e as Map<String, dynamic>))
          .toList(),
      workingSets: (json['workingSets'] as List)
          .map((e) => SetState.fromJson(e as Map<String, dynamic>))
          .toList(),
      expanded: json['expanded'] as bool? ?? true,
      bestKg: (json['bestKg'] as num?)?.toDouble(),
    );
  }
}

/// The in-memory model for an ongoing session, held by [ActiveSessionController].
class SessionDraft {
  final String? templateId;
  final String name;
  final String focus;
  final DateTime startedAt;
  final List<BlockState> blocks;

  const SessionDraft({
    required this.templateId,
    required this.name,
    required this.focus,
    required this.startedAt,
    required this.blocks,
  });

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'name': name,
        'focus': focus,
        'startedAt': startedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory SessionDraft.fromJson(Map<String, dynamic> json) => SessionDraft(
        templateId: json['templateId'] as String?,
        name: json['name'] as String,
        focus: json['focus'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        blocks: (json['blocks'] as List)
            .map((e) => BlockState.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── ActiveSessionController ──────────────────────────────────────────────────

/// Manages the in-memory state of an active workout session.
///
/// Call [buildFromTemplate] to initialise from a [DayTemplate]; or
/// [seedForTest] in unit tests to inject a ready-made draft.
///
/// All state mutations (toggleDone, addSet, etc.) call [notifyListeners] so
/// that Provider-wired widgets rebuild automatically.
class ActiveSessionController extends ChangeNotifier {
  SessionDraft? _draft;

  SessionDraft get draft {
    assert(_draft != null, 'No active session — call buildFromTemplate first.');
    return _draft!;
  }

  bool get hasSession => _draft != null;

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Initialises the controller from a [DayTemplate].
  ///
  /// Resolves each slot, queries the last/best top set for seeding and PR
  /// detection, then builds the block list.
  Future<void> buildFromTemplate(
    DayTemplate template, {
    required ExerciseRepository exerciseRepo,
    required DayTemplateRepository dayTemplateRepo,
    required SessionRepository sessionRepo,
  }) async {
    final blocks = <BlockState>[];

    for (final slot in template.slots) {
      final exercise = await exerciseRepo.byId(slot.exerciseId);
      if (exercise == null) continue;

      final resolved = resolveSlot(slot, exercise);

      final lastTop = await sessionRepo.lastTopSet(slot.exerciseId);
      final bestKg = await sessionRepo.bestTopSet(slot.exerciseId);

      final block = buildBlock(
        resolved: resolved,
        lastTopKg: lastTop?.weight,
      );
      block.bestKg = bestKg;
      blocks.add(block);
    }

    _draft = SessionDraft(
      templateId: template.id,
      name: template.name,
      focus: template.focus ?? '',
      startedAt: DateTime.now(),
      blocks: blocks,
    );
    notifyListeners();
  }

  /// Seeds an empty session with no blocks (custom / ad-hoc workout).
  ///
  /// Used by the launcher's "Start empty" option before pushing
  /// [ActiveSessionScreen].
  void seedEmpty({required String name, required String focus}) {
    _draft = SessionDraft(
      templateId: null,
      name: name,
      focus: focus,
      startedAt: DateTime.now(),
      blocks: [],
    );
    notifyListeners();
  }

  /// Seeds the controller directly — for use in tests only.
  @visibleForTesting
  void seedForTest(SessionDraft draft) {
    _draft = draft;
    notifyListeners();
  }

  // ── Computed getters ──────────────────────────────────────────────────────

  /// Wall-clock elapsed since the session started.
  Duration get elapsed => DateTime.now().difference(draft.startedAt);

  /// Number of working sets that have been ticked done.
  int get doneWork => draft.blocks
      .expand((b) => b.workingSets)
      .where((s) => s.done)
      .length;

  /// Total number of working sets (done + not done).
  int get totalWork =>
      draft.blocks.fold(0, (n, b) => n + b.workingSets.length);

  /// Whether the session can be finished (at least one working set done).
  bool get canFinish => doneWork >= 1;

  /// Number of exercise blocks that have beaten their all-time best in this
  /// session (optimistic — the server's is_pr flags are authoritative after sync).
  int get prCount {
    var count = 0;
    for (final block in draft.blocks) {
      final maxDoneWorking = block.workingSets
          .where((s) => s.done)
          .fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
      final best = block.bestKg;
      if (best == null || (maxDoneWorking > 0 && maxDoneWorking > best)) {
        if (maxDoneWorking > 0) count++;
      }
    }
    return count;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Notifies listeners after a caller mutates a [SetState] directly
  /// (e.g. weight/reps/RIR changed by a stepper — the set is mutated in-place
  /// by the UI and this method propagates the rebuild).
  void markChanged() => notifyListeners();

  /// Toggles [set] within [block] between done and not done.
  void toggleDone(BlockState block, SetState set) {
    set.done = !set.done;
    notifyListeners();
  }

  /// Appends a new working set to [block] (cloning weight/reps from the last
  /// working set in the block, or using the block's default suggested weight).
  void addSet(BlockState block) {
    final last = block.workingSets.isNotEmpty ? block.workingSets.last : null;
    final step = block.exercise.plateStepKg;
    final seed = block.resolved.exercise.baseWeightKg ?? 20.0;
    final suggested = roundTo(
      seed + (block.exercise.compound ? step : 0),
      step,
    );
    block.workingSets.add(SetState(
      id: uuid.v4(),
      weightKg: last?.weightKg ?? suggested,
      reps: last?.reps ?? block.resolved.repLow,
      rir: last?.rir ?? 1,
      isWarmup: false,
      done: false,
    ));
    notifyListeners();
  }

  /// Removes [block] from the session.
  void removeBlock(BlockState block) {
    draft.blocks.remove(block);
    notifyListeners();
  }

  /// Appends a new block for [exercise] using the exercise's own defaults.
  void addBlock(Exercise exercise) {
    // Build a default slot from the exercise's own defaults (no slot overrides).
    final slot = Slot(exerciseId: exercise.id, position: draft.blocks.length);
    final resolved = resolveSlot(slot, exercise);
    final block = buildBlock(resolved: resolved);
    draft.blocks.add(block);
    notifyListeners();
  }

  // ── Finish ────────────────────────────────────────────────────────────────

  /// Persists the session to the local PowerSync DB, clears the draft store,
  /// and clears the in-memory draft.
  ///
  /// Returns the new session id. The caller must wrap this in
  /// `db.writeTransaction((tx) => controller.finish(PowerSyncTxExecutor(tx)))`
  /// to ensure atomicity. Pass [draftStore] to also clear the on-disk draft
  /// (call with the same [DraftStore] used to save the session while it was active).
  Future<String> finish(SqlExecutor executor, {DraftStore? draftStore}) async {
    final d = draft;
    final sessionId = uuid.v4();
    final today = DateTime.now();
    final dateIso =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final splitLabel = '${d.name} · ${d.focus}'; // middot separator

    // Collect all sets: warm-ups (is_warmup=true) then working, per block,
    // with set_number restarting per exercise.
    final sets = <SetWrite>[];
    for (final block in d.blocks) {
      var setNum = 1;
      for (final s in block.warmupSets) {
        sets.add(SetWrite(
          id: s.id,
          exerciseId: block.exercise.id,
          setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2),
          reps: s.reps,
          rir: null, // warm-up RIR is never written
          isWarmup: true,
        ));
      }
      for (final s in block.workingSets) {
        sets.add(SetWrite(
          id: s.id,
          exerciseId: block.exercise.id,
          setNumber: setNum++,
          weightKg: s.weightKg.toStringAsFixed(2),
          reps: s.reps,
          rir: s.rir,
          isWarmup: false,
        ));
      }
    }

    final write = SessionWrite(
      id: sessionId,
      dateIso: dateIso,
      dayTemplateId: d.templateId,
      splitLabel: splitLabel,
      durationMin: (elapsed.inSeconds / 60).round(),
      sets: sets,
    );

    await persistSession(executor, write);

    // Clear the on-disk draft (if a store is provided) then the in-memory state.
    await draftStore?.clear();
    _draft = null;
    notifyListeners();

    return sessionId;
  }

  /// Clears the in-memory draft without persisting. Used when the user
  /// discards the session.
  void discard() {
    _draft = null;
    notifyListeners();
  }
}
