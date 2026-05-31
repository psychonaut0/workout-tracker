// Canonical muscle group labels keyed on the 8 real DB `muscle_group` values.
// Insertion order defines display order.

const Map<String, String> kMuscleLabels = {
  'chest': 'Chest',
  'back': 'Back',
  'shoulders': 'Shoulders',
  'quads': 'Quads',
  'hamstrings': 'Hamstrings',
  'calves': 'Calves',
  'biceps': 'Biceps',
  'triceps': 'Triceps',
};

/// Returns the display label for a muscle [key].
///
/// Known keys resolve via [kMuscleLabels]; unknown non-empty keys are
/// title-cased; empty string is returned as-is. The parentheses around the
/// `?:` are required because `??` binds tighter than `?:`.
String muscleLabel(String key) =>
    kMuscleLabels[key] ??
    (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));

/// Orders [present] muscles in canonical display order (known muscles first,
/// in [kMuscleLabels] insertion order), then unknown muscles sorted
/// alphabetically.
List<String> orderedMuscles(Iterable<String> present) {
  final known =
      kMuscleLabels.keys.where(present.contains).toList(); // canonical order
  final extra = present.where((m) => !kMuscleLabels.containsKey(m)).toList()
    ..sort(); // unknowns last
  return [...known, ...extra];
}
