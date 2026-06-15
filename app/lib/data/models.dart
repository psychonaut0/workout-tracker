// Domain models for the workout tracker data layer.
//
// PowerSync rows arrive as `Map<String, dynamic>` with:
// - NUMERIC columns → TEXT (parse via `double.parse`)
// - boolean columns → int 0/1 (compare with `!= 0`)
// - dates/timestamps → TEXT (ISO-8601)

// ── RIR adapter ──────────────────────────────────────────────────────────────

/// Parses a RIR display string into a `(low, high)` record.
///
/// `'1'` → `(low: 1, high: 1)`, `'0–1'` or `'1–0'` → `(low: 0, high: 1)`.
/// Normalizes so `low <= high`.
/// Throws on empty / partial / non-numeric input — use [rirTryParse] in editors.
({int low, int high}) rirParse(String s) {
  // Handle both hyphen '-' and en-dash '–'
  final parts = s.split(RegExp(r'[-–]'));
  if (parts.length == 1) {
    final v = int.parse(parts[0].trim());
    return (low: v, high: v);
  }
  final a = int.parse(parts[0].trim());
  final b = int.parse(parts[1].trim());
  return a <= b ? (low: a, high: b) : (low: b, high: a);
}

/// Converts a RIR (low, high) pair to a display string.
///
/// `low == high` → `'$low'`, otherwise `'$low–$high'` (en-dash).
String rirToString(int low, int high) {
  return low == high ? '$low' : '$low–$high';
}

/// Non-throwing variant of [rirParse]: returns null on empty / partial /
/// non-numeric input instead of throwing. Safe to call on every keystroke
/// in a text field.
({int low, int high})? rirTryParse(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return null;
  try {
    return rirParse(trimmed);
  } catch (_) {
    return null;
  }
}

// ── Exercise ─────────────────────────────────────────────────────────────────

class Exercise {
  final String id;
  final String name;
  final String slug;
  final String muscleGroup;
  final String? equip;
  final bool compound;
  final double? baseWeightKg;
  final double plateStepKg;
  final int? defaultRepLow;
  final int? defaultRepHigh;
  final int? defaultWarmupSets;
  final int? defaultWorkingSets;
  final int? defaultRirLow;
  final int? defaultRirHigh;
  final int? defaultRestSeconds;
  final bool isTemplate;

  const Exercise({
    required this.id,
    required this.name,
    required this.slug,
    required this.muscleGroup,
    this.equip,
    required this.compound,
    this.baseWeightKg,
    required this.plateStepKg,
    this.defaultRepLow,
    this.defaultRepHigh,
    this.defaultWarmupSets,
    this.defaultWorkingSets,
    this.defaultRirLow,
    this.defaultRirHigh,
    this.defaultRestSeconds,
    required this.isTemplate,
  });

  factory Exercise.fromRow(Map<String, dynamic> row) {
    final baseWt = row['base_weight_kg'];
    final plateStep = row['plate_step_kg'];
    return Exercise(
      id: row['id'] as String,
      name: row['name'] as String,
      slug: row['slug'] as String? ?? '',
      muscleGroup: row['muscle_group'] as String? ?? '',
      equip: row['equip'] as String?,
      compound: (row['compound'] as int? ?? 0) != 0,
      // tryParse (not parse): a locally-created exercise with no base weight is
      // stored as '' (the null sentinel the server NULLIFs). double.parse('')
      // throws, and one bad row would break the whole catalog stream's map().
      baseWeightKg: double.tryParse(baseWt?.toString() ?? ''),
      plateStepKg: double.tryParse(plateStep?.toString() ?? '') ?? 2.5,
      defaultRepLow: row['default_rep_low'] as int?,
      defaultRepHigh: row['default_rep_high'] as int?,
      defaultWarmupSets: row['default_warmup_sets'] as int?,
      defaultWorkingSets: row['default_working_sets'] as int?,
      defaultRirLow: row['default_rir_low'] as int?,
      defaultRirHigh: row['default_rir_high'] as int?,
      defaultRestSeconds: row['default_rest_seconds'] as int?,
      isTemplate: (row['is_template'] as int? ?? 0) != 0,
    );
  }
}

// ── Slot (from day_template_items) ───────────────────────────────────────────

class Slot {
  /// The row id from `day_template_items`; null for slots not loaded from DB.
  final String? id;
  final String exerciseId;
  final int position;
  final int? workSets;
  final int? warmupSets;
  final int? repLow;
  final int? repHigh;
  final int? rirLow;
  final int? rirHigh;

  const Slot({
    this.id,
    required this.exerciseId,
    required this.position,
    this.workSets,
    this.warmupSets,
    this.repLow,
    this.repHigh,
    this.rirLow,
    this.rirHigh,
  });

  factory Slot.fromRow(Map<String, dynamic> row) {
    return Slot(
      id: row['id'] as String?,
      exerciseId: row['exercise_id'] as String,
      position: row['position'] as int? ?? 0,
      workSets: row['target_working_sets'] as int?,
      warmupSets: row['target_warmup_sets'] as int?,
      repLow: row['target_rep_low'] as int?,
      repHigh: row['target_rep_high'] as int?,
      rirLow: row['target_rir_low'] as int?,
      rirHigh: row['target_rir_high'] as int?,
    );
  }
}

// ── ResolvedSlot ─────────────────────────────────────────────────────────────

/// A fully-resolved slot: all fields are non-null (fallback chain applied).
class ResolvedSlot {
  final Exercise exercise;
  final int workSets;
  final int warmupSets;
  final int repLow;
  final int repHigh;
  final int rirLow;
  final int rirHigh;

  const ResolvedSlot({
    required this.exercise,
    required this.workSets,
    required this.warmupSets,
    required this.repLow,
    required this.repHigh,
    required this.rirLow,
    required this.rirHigh,
  });
}

// ── DayTemplate ──────────────────────────────────────────────────────────────

class DayTemplate {
  final String id;
  final String? slug;
  final String name;
  final String? focus;
  final int? scheduledWeekday;
  final int position;
  final List<Slot> slots;
  final bool isTemplate;

  const DayTemplate({
    required this.id,
    this.slug,
    required this.name,
    this.focus,
    this.scheduledWeekday,
    required this.position,
    required this.slots,
    this.isTemplate = false,
  });
}

// ── Draft models (for plan editors) ──────────────────────────────────────────

/// Mutable draft for a single slot in a training day. [itemId] is null for new
/// slots; non-null for slots loaded from the DB (carry their row id for PATCH).
class SlotDraft {
  String? itemId;
  String exerciseId;
  int? workSets;
  int? warmupSets;
  int? repLow;
  int? repHigh;
  int? rirLow;
  int? rirHigh;

  SlotDraft({
    this.itemId,
    required this.exerciseId,
    this.workSets,
    this.warmupSets,
    this.repLow,
    this.repHigh,
    this.rirLow,
    this.rirHigh,
  });
}

/// Mutable draft for a training day (DayTemplate).
class DayDraft {
  String name;
  String? focus;
  int? weekday;
  List<SlotDraft> slots;

  DayDraft({
    required this.name,
    this.focus,
    this.weekday,
    required this.slots,
  });
}

/// Mutable draft for an exercise.
class ExerciseDraft {
  String? id;
  String name;
  String muscleGroup;
  String? equip;
  bool compound;
  double? baseWeightKg;
  double plateStepKg;
  int? defaultRepLow;
  int? defaultRepHigh;
  int? defaultWarmupSets;
  int? defaultWorkingSets;
  int? defaultRirLow;
  int? defaultRirHigh;
  int? defaultRestSeconds;

  ExerciseDraft({
    this.id,
    required this.name,
    required this.muscleGroup,
    this.equip,
    required this.compound,
    this.baseWeightKg,
    required this.plateStepKg,
    this.defaultRepLow,
    this.defaultRepHigh,
    this.defaultWarmupSets,
    this.defaultWorkingSets,
    this.defaultRirLow,
    this.defaultRirHigh,
    this.defaultRestSeconds,
  });
}

// ── LoggedSet ────────────────────────────────────────────────────────────────

class LoggedSet {
  final String id;
  final String exerciseId;
  final int setNumber;
  final double weightKg;
  final int reps;
  final int? rir;
  final bool isWarmup;
  final bool isTopSet;
  final bool isPr;

  const LoggedSet({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    this.rir,
    required this.isWarmup,
    required this.isTopSet,
    required this.isPr,
  });

  factory LoggedSet.fromRow(Map<String, dynamic> row) {
    final wt = row['weight_kg'];
    return LoggedSet(
      id: row['id'] as String,
      exerciseId: row['exercise_id'] as String,
      setNumber: row['set_number'] as int? ?? 0,
      weightKg: double.tryParse(wt?.toString() ?? '') ?? 0.0,
      reps: row['reps'] as int? ?? 0,
      rir: row['rir'] as int?,
      isWarmup: (row['is_warmup'] as int? ?? 0) != 0,
      isTopSet: (row['is_top_set'] as int? ?? 0) != 0,
      isPr: (row['is_pr'] as int? ?? 0) != 0,
    );
  }
}

// ── ExerciseBlockData ─────────────────────────────────────────────────────────

/// Aggregated data for one exercise within a session (for the summary/history views).
class ExerciseBlockData {
  final String exerciseId;
  final List<LoggedSet> sets;
  final double topWeight;
  final int topReps;
  final bool isPr;

  const ExerciseBlockData({
    required this.exerciseId,
    required this.sets,
    required this.topWeight,
    required this.topReps,
    required this.isPr,
  });
}

// ── SessionSummaryRow ─────────────────────────────────────────────────────────

class SessionSummaryRow {
  final String id;
  final String date;
  final String? splitLabel;
  final String? dayTemplateId;
  final int? durationMin;

  const SessionSummaryRow({
    required this.id,
    required this.date,
    this.splitLabel,
    this.dayTemplateId,
    this.durationMin,
  });

  factory SessionSummaryRow.fromRow(Map<String, dynamic> row) {
    return SessionSummaryRow(
      id: row['id'] as String,
      date: row['date'] as String? ?? '',
      splitLabel: row['split_label'] as String?,
      dayTemplateId: row['day_template_id'] as String?,
      durationMin: row['duration_min'] as int?,
    );
  }
}

// ── BodyweightEntry ───────────────────────────────────────────────────────────

class BodyweightEntry {
  final String date;
  final double weightKg;

  const BodyweightEntry({required this.date, required this.weightKg});

  factory BodyweightEntry.fromRow(Map<String, dynamic> row) {
    return BodyweightEntry(
      date: row['date'] as String,
      weightKg: (row['weight'] as num).toDouble(),
    );
  }
}

// ── HistorySessionRow ─────────────────────────────────────────────────────────

class HistorySessionRow {
  final String id, date;
  final String? splitLabel;
  final int? durationMin;
  final int exerciseCount;
  final int prCount;
  final double tonnageKg; // sum of non-warmup weight*reps
  HistorySessionRow({required this.id, required this.date, this.splitLabel, this.durationMin, required this.exerciseCount, required this.prCount, required this.tonnageKg});
  factory HistorySessionRow.fromRow(Map<String, dynamic> r) => HistorySessionRow(
        id: r['id'] as String,
        date: r['date'] as String,
        splitLabel: r['split_label'] as String?,
        durationMin: (r['duration_min'] as num?)?.toInt(),
        exerciseCount: (r['ex_count'] as num?)?.toInt() ?? 0,
        prCount: (r['pr_count'] as num?)?.toInt() ?? 0,
        tonnageKg: (r['tonnage'] as num?)?.toDouble() ?? 0,
      );
}

// ── ProgressPoint ─────────────────────────────────────────────────────────────

class ProgressPoint {
  final String date;
  final double topWeightKg;
  final int topReps;
  final bool isPr;
  final double volumeKg;

  const ProgressPoint({
    required this.date,
    required this.topWeightKg,
    required this.topReps,
    required this.isPr,
    required this.volumeKg,
  });

  factory ProgressPoint.fromRow(Map<String, dynamic> r) => ProgressPoint(
        date: r['date'] as String,
        topWeightKg: (r['top_weight'] as num?)?.toDouble() ?? 0,
        topReps: (r['top_reps'] as num?)?.toInt() ?? 0,
        isPr: ((r['is_pr'] as num?) ?? 0) != 0,
        volumeKg: (r['volume'] as num?)?.toDouble() ?? 0,
      );
}

/// Epley formula: estimated 1-rep max in kg (rounded to nearest kg).
int est1rm(double weightKg, int reps) =>
    (weightKg * (1 + reps / 30)).round();

// ── MuscleTarget ──────────────────────────────────────────────────────────────

class MuscleTarget {
  final String id;
  final String muscle;
  final int targetSets;

  const MuscleTarget({
    required this.id,
    required this.muscle,
    required this.targetSets,
  });

  factory MuscleTarget.fromRow(Map<String, dynamic> row) {
    return MuscleTarget(
      id: row['id'] as String,
      muscle: row['muscle'] as String,
      targetSets: row['target_sets'] as int? ?? 0,
    );
  }
}
