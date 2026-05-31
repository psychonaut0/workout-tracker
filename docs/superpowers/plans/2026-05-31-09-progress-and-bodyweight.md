# Progress (Lift) + Bodyweight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the Progress tab — a per-exercise **Lift view** (target selector → exercise sheet, metric tabs Top set / Est. 1RM / Volume / Reps, line chart with PR dots, Current/Best/12wk-Δ cards, by-session log) and a **Bodyweight view** (trend chart, Current/30-day/Lowest, a log-today sheet, dated history) — replacing the Progress placeholder and the Today bodyweight/Recent-PR stubs.

**Architecture:** `ProgressScreen` renders the Lift view, or delegates to `BodyweightView` when its target is the `__bodyweight__` sentinel. A new `ProgressRepository.watchSeriesFor(exerciseId)` yields per-session points (top weight/reps/is_pr + volume) via one grouped `db.watch`; a new `BodyweightRepository.logBodyweight` does a **client-side same-day upsert** (the server has no unique(user_id,date)). A shared `LineChart` (CustomPaint) + `ExerciseSheet` picker + `ProgressSelectorRow`/`MetricTabs`/`BigStat` widgets. **No backend/migration change** — `applyBodyweight` + `bodyweight_logs` already exist (Plan 5a). Tapping a Today Recent-PR row / bodyweight tile switches to the Progress tab with that target (sibling-tab, hoisted in `AppShell`).

**Tech Stack:** Flutter 3.44 (fvm; `make -C app`), PowerSync 2.2.0, `provider`. Dev Postgres :5433; login `me@example.com`/`devpassword`.

**Scope:** Progress (Lift) + Bodyweight only. History / Plan / Profile tabs stay placeholders. The design `.jsx` (`screen-progress.jsx`, `screen-bodyweight.jsx`, `ui.jsx` LineChart) are the authoritative visual spec; UI tasks port from them, this plan supplies architecture + data contracts + load-bearing logic.

**Conventions:** Conventional Commits, subject only. Branch off `main` first. `make -C app`. Reuse `context.tokens`/`WorkoutType`/`WIcons`/`AppRadius`, `UnitService` (`context.watch`, `fmtWt`/`fromKg`/`toKg`/`uLabel`), primitives (`WCard`, `SectionLabel`, `PRBadge`), `Sparkline`, `app/lib/util/dates.dart` (`fmtDate`/`isoDate`).

**Settled decisions (adopted from the synthesis):** routing = sibling-tab (switch to Progress tab, set target); '12wk Δ' = literal label, value = last−first over the full series; Volume & Est.1RM convert by the lb factor when unit=lb (prototype parity; volume = kg·reps then ×factor); default lift = first catalog exercise **with logged history**, else first alphabetically (never hardcode a slug); extract `BigStat` + `ProgressSelectorRow` as shared; History capped at `.take(24)`, read-only; Est.1RM = **Epley** `(w·(1+reps/30)).round()` in kg then convert; server `is_pr` is authoritative (never recompute); `muscles.dart` keys = the **8 real DB `muscle_group` values** (chest/back/shoulders/quads/hamstrings/calves/biceps/triceps — NOT design `hams`/`glutes`).

---

## File Structure
- `app/lib/util/format.dart` (NEW) — `fmtPlain(double)` (int bare else 1dp .0-stripped)
- `app/lib/data/models.dart` (MOD) — `ProgressPoint` + `int est1rm(double,int)`
- `app/lib/data/progress_repository.dart` (NEW) — `watchSeriesFor`
- `app/lib/data/bodyweight_repository.dart` (MOD) — add `logBodyweight`
- `app/lib/data/muscles.dart` (NEW) — canonical ordered muscle labels (8 DB keys)
- `app/lib/widgets/line_chart.dart` (NEW) — `LineChart` CustomPaint
- `app/lib/widgets/progress_widgets.dart` (NEW) — `ProgressSelectorRow`, `MetricTabs`, `BigStat`
- `app/lib/ui/exercise_sheet.dart` (NEW) — `showExerciseSheet → Future<String?>`
- `app/lib/ui/progress_screen.dart` (NEW) — Lift view + delegate
- `app/lib/ui/bodyweight_view.dart` (NEW) — Bodyweight view
- `app/lib/ui/add_weight_sheet.dart` (NEW) — log-today sheet
- `app/lib/shell/app_shell.dart` (MOD) — mount ProgressScreen at index 1, hoist `_progressTarget`

---

### Task 1: ProgressPoint model + est1rm + fmtPlain util

**Files:** Modify `app/lib/data/models.dart`; Create `app/lib/util/format.dart`, `app/test/util/format_test.dart`

- [ ] **Step 1: `format.dart`** — (a) `String fmtPlain(double v)`: if `v == v.roundToDouble()` → `v.toInt().toString()`; else `v.toStringAsFixed(1)` with a trailing `.0` stripped (mirrors `ui.jsx` `fmtKg`). (b) `String fmtThousands(double v)`: round to int and group with commas (manual grouping — no `intl` dep), matching `toLocaleString('en-US')`, e.g. `12500 → '12,500'` (used by the **Volume** metric only). Tests: `fmtPlain(80)=='80'`, `fmtPlain(72.5)=='72.5'`, `fmtPlain(80.0)=='80'`, `fmtThousands(12500)=='12,500'`, `fmtThousands(900)=='900'`.
- [ ] **Step 2: In `models.dart`** add:
```dart
class ProgressPoint {
  final String date;
  final double topWeightKg;
  final int topReps;
  final bool isPr;
  final double volumeKg;
  ProgressPoint({required this.date, required this.topWeightKg, required this.topReps, required this.isPr, required this.volumeKg});
  factory ProgressPoint.fromRow(Map<String, dynamic> r) => ProgressPoint(
        date: r['date'] as String,
        topWeightKg: (r['top_weight'] as num?)?.toDouble() ?? 0,
        topReps: (r['top_reps'] as num?)?.toInt() ?? 0,
        isPr: ((r['is_pr'] as num?) ?? 0) != 0,
        volumeKg: (r['volume'] as num?)?.toDouble() ?? 0,
      );
}
int est1rm(double weightKg, int reps) => (weightKg * (1 + reps / 30)).round(); // Epley
```
- [ ] **Step 3:** Test `est1rm(100, 5) == 117` (`100*(1+5/30)=116.67→117`). Run `make -C app test`. **Commit** — "feat(app): ProgressPoint model, est1rm, fmtPlain"

### Task 2: ProgressRepository.watchSeriesFor

**Files:** Create `app/lib/data/progress_repository.dart`

- [ ] **Step 1: Implement** `const ProgressRepository(this.db);`
```dart
Stream<List<ProgressPoint>> watchSeriesFor(String exerciseId) => db.watch(
  '''SELECT se.date AS date,
            MAX(CASE WHEN s.is_top_set=1 THEN CAST(s.weight_kg AS REAL) END) AS top_weight,
            MAX(CASE WHEN s.is_top_set=1 THEN s.reps END) AS top_reps,
            MAX(CASE WHEN s.is_top_set=1 THEN s.is_pr ELSE 0 END) AS is_pr,
            SUM(CAST(s.weight_kg AS REAL) * s.reps) AS volume
       FROM sets s JOIN sessions se ON se.id=s.session_id
      WHERE s.exercise_id = ? AND s.is_warmup = 0
      GROUP BY se.id, se.date ORDER BY se.date ASC, se.created_at ASC''',
  parameters: [exerciseId],
).map((rs) => rs.map(ProgressPoint.fromRow).toList());
```
(`top_*`/`is_pr` scoped to the top set; `volume` = all working sets. Kept in kg; convert at the view. `db.watch` uses **named** `parameters:`.)
- [ ] **Step 2:** `make -C app analyze` clean. **Commit** — "feat(app): progress repository (per-exercise series)"

### Task 3: BodyweightRepository.logBodyweight (client same-day upsert)

**Files:** Modify `app/lib/data/bodyweight_repository.dart`

- [ ] **Step 1: Add** (inside `db.writeTransaction` for atomicity; uuid from `package:powersync/powersync.dart`):
```dart
/// Pure + testable: the upsert op given the existing same-day row id (or null).
({String sql, List<Object?> args}) bodyweightUpsertOp(
    String? existingId, String dateIso, double kg, String newId) {
  final w = kg.toStringAsFixed(2); // weight_kg is TEXT, never numeric
  return existingId != null
      ? (sql: 'UPDATE bodyweight_logs SET weight_kg = ? WHERE id = ?', args: [w, existingId])
      : (sql: 'INSERT INTO bodyweight_logs (id, date, weight_kg) VALUES (?, ?, ?)', args: [newId, dateIso, w]);
  // OMIT user_id (server stamps from token) + created_at (server defaults), like persistSession.
}

Future<void> logBodyweight({required String dateIso, required double kg}) async {
  await db.writeTransaction((tx) async {
    final existing = await tx.getOptional('SELECT id FROM bodyweight_logs WHERE date = ? LIMIT 1', [dateIso]);
    final op = bodyweightUpsertOp(existing?['id'] as String?, dateIso, kg, uuid.v4());
    await tx.execute(op.sql, op.args);
  });
}
```
**Why client-side upsert:** the server has NO `unique(user_id,date)` and `applyBodyweight` PUT upserts `ON CONFLICT(id)` only — a fresh uuid each save would create duplicate same-day rows. Reusing the existing same-day id makes the upload a PATCH-in-place. `weight_kg` is TEXT (`toStringAsFixed(2)`); OMIT `user_id` (server stamps) + `created_at` (server defaults) — exactly like `persistSession`. Drop the "read-only/write deferred" doc comment.
- [ ] **Step 2: Test** `app/test/data/bodyweight_write_test.dart` — unit-test the pure `bodyweightUpsertOp` directly (the existing `FakeExec` only has `execute`, NOT `getOptional`, so it can't capture the dedup SELECT — test the helper, not a fake tx). Assert: `existingId != null` → an `UPDATE … WHERE id = ?` op reusing **that same id** (the `newId` uuid is NOT used); `existingId == null` → an `INSERT` op using `newId`; in both, `weight_kg` is the `toStringAsFixed(2)` **String**; and neither op's args/SQL include `user_id` or `created_at`. Run `make -C app test`.
- [ ] **Step 3: Commit** — "feat(app): bodyweight logging with client same-day upsert"

### Task 4: Canonical muscle order + labels

**Files:** Create `app/lib/data/muscles.dart`, `app/test/data/muscles_test.dart`

- [ ] **Step 1: Implement** keyed on the **8 real DB `muscle_group` values** (verified seed/Today work), insertion order = display order:
```dart
const Map<String, String> kMuscleLabels = {
  'chest': 'Chest', 'back': 'Back', 'shoulders': 'Shoulders', 'quads': 'Quads',
  'hamstrings': 'Hamstrings', 'calves': 'Calves', 'biceps': 'Biceps', 'triceps': 'Triceps',
};
String muscleLabel(String key) => kMuscleLabels[key] ?? (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));
List<String> orderedMuscles(Iterable<String> present) {
  final known = kMuscleLabels.keys.where(present.contains).toList(); // canonical order
  final extra = present.where((m) => !kMuscleLabels.containsKey(m)).toList()..sort(); // unknowns last
  return [...known, ...extra];
}
```
(`??` binds tighter than `?:`, so the parentheses around the `?:` are required.) **Do NOT use design keys `hams`/`glutes`** — the DB uses `hamstrings` and has no glutes.
- [ ] **Step 2: Test** `muscleLabel('hamstrings')=='Hamstrings'`, `muscleLabel('unknown')=='Unknown'`, `orderedMuscles(['biceps','chest'])==['chest','biceps']`. Run `make -C app test`. **Commit** — "feat(app): canonical muscle labels/order"

### Task 5: LineChart widget

**Files:** Create `app/lib/widgets/line_chart.dart`

Port `ui.jsx` `LineChart` faithfully (the synthesis `newWidgets` LineChart entry has the exact geometry). `LineChart({required List<({double value, int reps, bool isPr})> series, double height=210, required String unit, bool showReps=true})` as a `CustomPaint(size: Size(double.infinity, height))` (use `LayoutBuilder`/the paint size for available width `W`).

- [ ] **Step 1: Implement** the painter per the spec: if `series.length < 2` → `SizedBox(height: height)`. Pads padT 18 / padR 16 / padB 26 / padL 34; y-domain `lo=min, hi=max, span=max(hi-lo,4)`, then `lo -= span*0.18; hi += span*0.22`; `x(i)=padL+(i/(n-1))*iw`, `y(v)=padT+ih-((v-lo)/(hi-lo))*ih`. Layers: 5 gridlines + left y labels (`fmtPlain`/round, mono 9 faint); area-fill path with a vertical accent@0.22→accent@0 gradient; polyline accent stroke w2.4 round; per-point dots (PR → r4.5 accent + bg-color halo stroke w2; last point handled separately; else r2.2 accent@0.55); month x-labels at month boundaries (mono 9 faint); last point → r9 accent@0.16 halo + r4.5 dot + floating value label `fmtPlain(value)+unit+(showReps? ' ×{reps}':'')` (mono 12/700) positioned `translate(min(lastX, W-58), max(lastY-26, 4))`. Use `TextPainter` for labels. Re-key (pass `key: ValueKey('$metricId-$unit')` from callers) so the y-domain recomputes on metric/unit change. **Series values are already in display units** (callers convert).
- [ ] **Step 2:** `make -C app analyze` clean. **Commit** — "feat(app): line chart widget"

### Task 6: Shared widgets — ProgressSelectorRow, MetricTabs, BigStat

**Files:** Create `app/lib/widgets/progress_widgets.dart`

- [ ] **Step 1: `BigStat`** — `BigStat({required String label, required String value, String? unit, bool accent=false})`: Column(mono 9.5 uppercase faint label mb6; baseline Row value `display(22,w700, accent?tokens.accent:tokens.text)` + optional `unit` mono 11 dim).
- [ ] **Step 2: `ProgressSelectorRow`** — `({required IconData icon, required String title, required String subtitle, required VoidCallback onTap})`: surface `WCard`-ish (line border, radius 15, pad 13/12/13/12, InkWell): 38×38 surface3 tile (radius 7.5) centered accent icon; Expanded title `body(16,w600)` ellipsis + subtitle `mono(11,faint)`; trailing 'CHANGE' `mono(10,w700,dim,uppercase)` + `WIcons.chevron` faint.
- [ ] **Step 3: Metric model + `MetricTabs`.** First define the 4 metrics as a const list (in `progress_widgets.dart` or a small `metrics.dart`) carrying **both `label` and `short`** plus the flags — `label` ≠ `short` for reps:
```dart
class Metric { final String id, label, short; final bool wt, reps, pr; const Metric(this.id,this.label,this.short,{this.wt=false,this.reps=false,this.pr=false}); }
const kMetrics = [
  Metric('top','Top set','Top set', wt:true, reps:true, pr:true),
  Metric('e1rm','Est. 1RM','Est. 1RM', wt:true),
  Metric('volume','Volume','Volume', wt:true),
  Metric('reps','Top reps','Reps'),
];
```
`MetricTabs({required String selected, required ValueChanged<String> onSelect})`: Row of 4 Expanded segments gap 6, height 34, radius 9, labeled by **`metric.short`**; selected = surface3 bg + inner 1px lineStrong ring + text color; unselected = transparent + 1px line border + faint; `mono(11.5,w700)`. Tap → `onSelect(metric.id)`. (Titles + section-labels in Task 8 use **`metric.label`** → 'Top reps trend' / 'Top reps by session' for reps.)
- [ ] **Step 4:** `make -C app analyze` clean. **Commit** — "feat(app): progress selector row, metric tabs, big stat"

### Task 7: ExerciseSheet picker

**Files:** Create `app/lib/ui/exercise_sheet.dart`

Port the `screen-progress.jsx` `ExerciseSheet` (the synthesis `newWidgets` ExerciseSheet entry is exact). `Future<String?> showExerciseSheet(BuildContext, {required List<Exercise> exercises, required String? current})` → returns an exId, the `'__bodyweight__'` sentinel, or null (keep current). **New file — do NOT overload `session/exercise_picker_sheet.dart`** (different selection-highlight + Bodyweight entry + return-id semantics).

- [ ] **Step 1: Implement** a `showModalBottomSheet` (isScrollControlled, surface2 bg, top corners radius*1.5, 1px lineStrong top border, maxHeight ~84%): grabber; header 'Choose exercise' + 'Done'(pop null); search field (filter by name or `muscleLabel`); a pinned **TRACKING → Bodyweight** row (shown when query empty or matches 'bodyweight'/'weight'; selected when `current=='__bodyweight__'`; returns the sentinel); then exercises grouped by `muscleGroup` in `orderedMuscles` order, each row with a compound dot (6×6: accent if compound else lineStrong), name + `mono` sub `'{equip}{compound? ' · compound':''}'` (guard null equip), a check when selected; tap returns `ex.id`. Use `kMuscleLabels`/`orderedMuscles`/`muscleLabel`.
- [ ] **Step 2:** `make -C app analyze` clean. **Commit** — "feat(app): exercise/bodyweight picker sheet"

### Task 8: ProgressScreen (Lift view) + BodyweightView

**Files:** Create `app/lib/ui/progress_screen.dart`, `app/lib/ui/bodyweight_view.dart`. Spec sources: `screen-progress.jsx` + synthesis `progressUiSpec`/`bodyweightUiSpec`.

- [ ] **Step 1: `ProgressScreen`** — `ProgressScreen({String? initialTarget})` (Stateful). `const bwId = '__bodyweight__'`. State: `String? _target` (init from `initialTarget`), `String _metricId = 'top'` (preserved across **in-screen picker** switches; a Today-driven target change rebuilds the screen via the `ValueKey` and resets the metric to 'top' — fine for this increment). If `_target == bwId` → return `BodyweightView(onOpenPicker: _openPicker)`. Else Lift view (ListView, padding `fromLTRB(16,8,16,96)`, rebuild on `context.watch<UnitService>()`): (1) title block ('PROGRESSION' eyebrow + '{metric.label} trend'); (2) `ProgressSelectorRow`(WIcons.dumbbell, ex.name, '{muscleLabel} · {equip?}', onTap `_openPicker`); (3) `MetricTabs`; (4) `LineChart` in a WCard (series = `watchSeriesFor(exId)` mapped to display units per the metric — wt metrics via `fromKg`, e1rm via `est1rm` then `fromKg`, volume `*reps` summed in kg then `fromKg` if lb; reps raw; `isPr = metric.pr && point.isPr`; key on `'$_metricId-$unit'`); (5) 3 `BigStat` cards (Current=last, Best=max [accent], '12wk Δ'=last−first signed) — guard `series.length` (0/1 → '—'). **Value formatting (used for BOTH stat cards and session-log row values): the Volume metric uses `fmtThousands` (comma-grouped); top/e1rm/reps use `fmtPlain`.** (The chart's floating last-value label stays `fmtPlain` even for volume — matches the prototype.) The **Current** card's unit appends `' ×{topReps}'` when the active metric carries reps (i.e. `top`), e.g. 'kg ×8'; the other cards take the bare unit; (6) session-log `SectionLabel(label:'{metric.label} by session', action: Text('{n} sessions'...))` + WCard list (newest first, per-row delta vs older, PRBadge on `is_pr` for the `top` metric else signed delta else '='). Default target: first catalog exercise whose `watchSeriesFor` is non-empty, else first alphabetical (compute from the watched catalog; do not hardcode). Empty exercise → muted 'No sessions logged yet' but selector still works. `_openPicker`: `final r = await showExerciseSheet(context, exercises: catalog, current: _target); if (r != null) setState(() => _target = r);`.
- [ ] **Step 2: `BodyweightView`** — `BodyweightView({required VoidCallback onOpenPicker})` (Stateful) reading `BodyweightRepository.watchSeriesAsc()` via StreamBuilder, rebuild on `context.watch<UnitService>()`, series mapped to display weight: header ('Bodyweight trend'); `ProgressSelectorRow`(WIcons.scale, 'Bodyweight', 'Daily log · {N} entries', onTap `onOpenPicker`); `LineChart`(showReps:false, all isPr:false); 3 `BigStat` (Current=last; '30-day'=last−(first entry ≤30d ago) signed, **accent always**; Lowest=min) — `fmtPlain` (already display units), '—' on 0/1; full-width accent 'Log today's weight' button (h50, radius 15) → `showAddWeightSheet`; `SectionLabel(label:'History', action:'{N} entries')` + WCard list of `series.reversed.take(24)` with **inverted-polarity** day-over-day delta (loss → accent, gain → dim, 0 → faint '='; oldest visible → '=').
- [ ] **Step 3:** `make -C app analyze` clean. **Commit** — "feat(app): Progress lift view + bodyweight view"

### Task 9: AddWeightSheet

**Files:** Create `app/lib/ui/add_weight_sheet.dart`. Spec: synthesis `bodyweightUiSpec` AddWeightSheet.

- [ ] **Step 1: Implement** `Future<void> showAddWeightSheet(BuildContext)` (modal bottom sheet, isScrollControlled, surface2, top corners radius*1.5, scrim 0.55): grabber; header 'Log bodyweight' + today `fmtDate(isoDate(now), weekday:true)`; bespoke **56×56 round** ±steppers (surface3, lineStrong border, WIcons.minus/plus ~22 — NOT WStepper); big value `display(52,w700)` `val.toStringAsFixed(1)` + `mono(16,dim)` `uLabel`; **unit-aware step** `unit==lb ? 0.2 : 0.1` in display units, clamp ≥0, round display 1dp; seed initial = `fromKg(lastLoggedKg)` to 1dp (re-seed each open; default 70.0kg-equiv if no entries); Save button (full-width accent, h52, radius 15) → `BodyweightRepository(db).logBodyweight(dateIso: isoDate(DateTime.now()), kg: toKg(val))` (import `sync/db.dart` for the global `db`; `BodyweightRepository` is `const ...(this.db)` — never construct it argument-less) → pop. **Capture `final nav = Navigator.of(context);` BEFORE the `await`, then `nav.pop()`** (flutter_lints flags BuildContext across async gaps — this repo was bitten before, commit 9d44084). The `watchSeriesAsc` stream auto-repaints the view.
- [ ] **Step 2:** `make -C app analyze` clean. **Commit** — "feat(app): log-bodyweight sheet"

### Task 10: AppShell integration

**Files:** Modify `app/lib/shell/app_shell.dart`

- [ ] **Step 1:** Replace `PlaceholderTab(title:'Progress')` (IndexedStack index 1) with `ProgressScreen(initialTarget: _progressTarget)`. Hoist `String? _progressTarget` into `_AppShellState`. Rework `_openExercise(String exId)`: `setState(() { _progressTarget = exId; _index = 1; })` (sibling-tab switch, NOT a root overlay). Give `ProgressScreen` a `key: ValueKey(_progressTarget)` so a Today-driven target change discards the stale State and re-runs `initState` to read the new `initialTarget`. (Use the key — NOT `didUpdateWidget`: the in-screen picker mutates the screen's own `_target` without changing `initialTarget`, which would desync a `didUpdateWidget` guard; the key leaves the picker working since `_progressTarget` is unchanged during in-screen switches.) Today's bodyweight tile already passes `'__bodyweight__'` and Recent-PR rows pass the exId → no Today-side change. Keep the `placeholder_screen.dart` import (still used for History/Plan/Profile). Re-tapping Today for the *same* target only switches the tab (no rebuild) — acceptable.
- [ ] **Step 2:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): mount Progress tab + route Today taps to it"

### Task 11: Verify — analyze + test + Linux build (INLINE)

- [ ] **Step 1: GATE 1+2** — `make -C app analyze` (zero issues); `make -C app test` (all green incl. format/est1rm/bodyweight-upsert/muscles tests).
- [ ] **Step 2: GATE 3 build** — `make -C app build` → Linux bundle links.
- [ ] **Step 3: Headless smoke** (autonomous, like Plan 8): run the release binary ~30s (auto-login + sync), then verify a bodyweight write round-trips: after the smoke, optionally inject a log via the running app is not possible headlessly, so instead assert the app launched without crash/exception and the Progress queries don't throw (no exceptions in the log). For the bodyweight write, a follow-up manual tap is fine — note it. (The unit tests already cover the upsert logic + est1rm + series aggregation.)
- [ ] **Step 4: Commit** any fixes.

---

## Deferred to later plans
- History screen (week grouping, summary tiles).
- Plan editors (Split day/slot + Exercise library).
- Profile & Settings + `SettingsService` (client-local unit/theme/accent + **configurable server URL**).
- Bodyweight history edit/delete from the view (backend supports PATCH/DELETE; UI deferred).
