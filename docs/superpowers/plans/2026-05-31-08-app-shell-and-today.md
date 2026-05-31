# App Shell + Today Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the throwaway launcher with the real app: a 5-tab bottom nav + center FAB shell, and a fully-wired **Today dashboard** (split-picker hero pager, this-week strip, stat tiles with bodyweight sparkline, recent PRs, weekly-volume-vs-target bars), backed by new aggregate/rotation/bodyweight/target repositories.

**Architecture:** `AppShell` (IndexedStack over Today + 3 placeholder tabs, with a blurred `WTabBar` + overhanging FAB in a Stack so root-Navigator overlays — active session, summary, Profile — cover it). Today composes PowerSync `db.watch` streams through new repositories. A single shared `nextInRotation` selector drives the FAB, the hero slide-0, and the WeekStrip "NEXT" chip. The 4 seeded day templates get `focus`/`scheduled_weekday` backfilled (migration `00020`); per-user `muscle_targets` is seeded client-side (insert-if-empty) since it can't be seeded server-side without a user_id.

**Tech Stack:** Flutter 3.44 (fvm; run via `make -C app <target>`), PowerSync 2.2.0, `provider`, `google_fonts`. Go + goose for the migration. Dev Postgres :5433; dev login `me@example.com`/`devpassword`; stack via `docker compose -f infra/compose.yml -f infra/compose.dev.yml --env-file infra/.env up -d`.

**Scope:** App shell + Today only. Progress / History / Plan tabs are lightweight `PlaceholderTab`s this increment; the Today avatar + bodyweight tile route to a `PlaceholderTab('Profile'/'Progress')` overlay. The design `.jsx` files under `docs/design_handoff_workout_tracker/design/` are the authoritative visual spec — UI tasks name the exact file to port (`screen-today.jsx`, `ui.jsx`, the nav in `Workout Tracker.html`); this plan supplies architecture, data contracts (code-complete SQL), and load-bearing logic.

**Conventions:** Conventional Commits, subject only. Branch off `main` first. All Flutter via `make -C app`. Reuse existing theme (`context.tokens`, `WorkoutType`, `WIcons`, `AppRadius`/`AppSpacing`), `UnitService` (`context.watch<UnitService>()`, `fmtWt`/`uLabel`), and primitives (`WCard`, `SectionLabel`, `Tag`, `PRBadge`).

**Settled decisions (all adopted from the understanding synthesis):** 8 DB muscle groups (collapse design's delt-split → `shoulders`, drop `glutes`, `hams`→`hamstrings`; DB value authoritative); **Monday-start** calendar week across all aggregates; **position-based wrapping rotation** (successor of most-recent session's `day_template_id`, default first day); `muscle_targets` seeded **client-side insert-if-empty**; day focus/weekday via **migration 00020**; FAB = zero-tap next-in-rotation, hero Start = visible slide; "Done → Today" via `AppShell` `setState(_index=0)` after the start-push future resolves (no SessionSummaryScreen change); avatar initials placeholder `'A'` (or from auth email), tap → `PlaceholderTab('Profile')`; bodyweight tile tap → `PlaceholderTab('Progress')` stub.

---

## File Structure

**Backend:** `server/db/migrations/00020_backfill_day_focus_weekday.sql`

**Flutter — util & widgets:**
- `app/lib/util/dates.dart` — `fmtDate`, `daysAgo`, `weekdayShort`, `weekStart`, `isoDate`
- `app/lib/widgets/sparkline.dart` — `Sparkline` (CustomPaint)
- `app/lib/widgets/stat_tile.dart`, `week_strip.dart`, `volume_bars.dart`, `split_card.dart` (+ `DaySlide`/`CustomSlide`/dashed-border painter inside)

**Flutter — data:**
- `app/lib/data/models.dart` — add `BodyweightEntry` (MODIFY)
- `app/lib/data/stats_repository.dart`, `bodyweight_repository.dart`, `muscle_target_repository.dart` (NEW)
- `app/lib/data/day_template_repository.dart` — add `nextInRotation` + `templateIdsTrainedThisWeek` (MODIFY)

**Flutter — shell & screen:**
- `app/lib/shell/app_shell.dart`, `w_tab_bar.dart`, `placeholder_screen.dart`, `session_launcher.dart` (NEW)
- `app/lib/ui/today_screen.dart` (NEW)
- `app/lib/main.dart` (MODIFY — swap launcher → AppShell), delete `app/lib/ui/home_screen.dart` (dead)

---

### Task 1: Backend — backfill day focus + weekday

**Files:** Create `server/db/migrations/00020_backfill_day_focus_weekday.sql`

Migration `00014` seeded the focus text into `notes` and never set `scheduled_weekday`; the `focus`/`scheduled_weekday` columns (added in Plan 7's `00017`) are NULL on the 4 shared days.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
UPDATE day_templates SET focus='Push',            scheduled_weekday=0 WHERE slug='upper-a';
UPDATE day_templates SET focus='Quad + Calf',     scheduled_weekday=1 WHERE slug='lower-a';
UPDATE day_templates SET focus='Pull',            scheduled_weekday=3 WHERE slug='upper-b';
UPDATE day_templates SET focus='Posterior Chain', scheduled_weekday=4 WHERE slug='lower-b';

-- +goose Down
UPDATE day_templates SET focus=NULL, scheduled_weekday=NULL
  WHERE slug IN ('upper-a','lower-a','upper-b','lower-b');
```

- [ ] **Step 2: Apply + verify** — `make -C server migrate-up`; then confirm the 4 days have focus + weekday:
`docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -c "SELECT slug, focus, scheduled_weekday FROM day_templates WHERE slug LIKE 'upper-%' OR slug LIKE 'lower-%' ORDER BY position;"` — expect 4 rows, all non-NULL. (Replication auto-syncs the column values; no PowerSync change.)

- [ ] **Step 3: Commit** — `git commit -am "feat(db): backfill focus + scheduled_weekday on the 4 seeded days"`

### Task 2: Date / relative-time helpers (TDD)

**Files:** Create `app/lib/util/dates.dart`, `app/test/util/dates_test.dart`

Port the semantics of `ui.jsx`'s `fmtDate`/`daysAgo`/`MONTHS`.

- [ ] **Step 1: Write the test** (`dates_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/util/dates.dart';

void main() {
  test('weekStart returns the Monday 00:00 of the given date', () {
    // 2026-05-31 is a Sunday → week started Mon 2026-05-25
    expect(isoDate(weekStart(DateTime(2026, 5, 31))), '2026-05-25');
    // 2026-05-25 is a Monday → itself
    expect(isoDate(weekStart(DateTime(2026, 5, 25, 14))), '2026-05-25');
  });
  test('daysAgo labels', () {
    final now = DateTime(2026, 5, 31);
    expect(daysAgo('2026-05-31', now: now), 'today');
    expect(daysAgo('2026-05-30', now: now), 'yesterday');
    expect(daysAgo('2026-05-28', now: now), '3d ago');
    expect(daysAgo('2026-05-10', now: now), '3w ago');
  });
  test('weekdayShort: 0=Mon .. 6=Sun', () {
    expect(weekdayShort(0), 'Mon');
    expect(weekdayShort(6), 'Sun');
  });
  test('fmtDate', () {
    expect(fmtDate('2026-05-31', weekday: true), 'Sun 31 May');
    expect(fmtDate('2026-05-25', weekday: true), 'Mon 25 May'); // non-Sunday: catches a wrong weekday offset
    expect(fmtDate('2026-05-31'), '31 May');
  });
}
```

- [ ] **Step 2: Run → fail.** `make -C app test`

- [ ] **Step 3: Implement `dates.dart`:**
  - `DateTime weekStart(DateTime d)` → Monday 00:00 (`d.weekday` is 1=Mon..7=Sun; subtract `weekday-1` days, zero the time).
  - `String isoDate(DateTime d)` → `yyyy-mm-dd` (zero-padded).
  - `String daysAgo(String iso, {DateTime? now})` → diff in whole days from `now ?? DateTime.now()` (date-only): **<=0**→'today', 1→'yesterday', <7→'{n}d ago', else '{n~/7}w ago'.
  - `String weekdayShort(int mon0)` → ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][mon0] (mon0 in 0..6).
  - `String fmtDate(String iso, {bool weekday = false})` → '[Ddd ]D Mmm' using a MONTHS list; weekday via `weekdayShort(DateTime.parse(iso).weekday - 1)` — Dart `weekday` is 1=Mon..7=Sun, so the **`-1` is required** or Sunday (7) overflows the 7-element list.

- [ ] **Step 4: Run → pass.** **Commit** — `git add app/lib/util app/test/util && git commit -m "feat(app): date + relative-time helpers"`

### Task 3: Sparkline widget

**Files:** Create `app/lib/widgets/sparkline.dart`, `app/test/widgets/sparkline_test.dart`

Port `ui.jsx`'s `Sparkline` (default 92×22).

- [ ] **Step 1: Implement** `Sparkline({required List<double> values, Color? stroke, double width=92, double height=22})` — a `CustomPaint`. If `values.length < 2` return `const SizedBox.shrink()`. Else `lo=min, hi=max, sp=max(hi-lo, 0.001)`; `x(i)=i/(n-1)*w`, `y(v)=h-2-((v-lo)/sp)*(h-4)`; paint a polyline (strokeWidth 1.8, round cap/join, `stroke ?? context.tokens.dim`) + a filled `r=2` dot at the last point.

- [ ] **Step 2: Widget test** (`sparkline_test.dart`): pumping `Sparkline(values: [1,2,3])` finds a `CustomPaint`; `Sparkline(values: [1])` renders a zero-size `SizedBox`. Run `make -C app test`.

- [ ] **Step 3: Commit** — `git add app/lib/widgets/sparkline.dart app/test/widgets/sparkline_test.dart && git commit -m "feat(app): sparkline widget"`

### Task 4: Data layer — stats / bodyweight / muscle-target repos + rotation helpers

**Files:** Modify `app/lib/data/models.dart`, `app/lib/data/day_template_repository.dart`; Create `app/lib/data/{stats_repository,bodyweight_repository,muscle_target_repository}.dart`. Local SQLite **can** JOIN (only the PowerSync sync-rules can't).

- [ ] **Step 1: Add `BodyweightEntry` to `models.dart`:** `class BodyweightEntry { final String date; final double weightKg; ... BodyweightEntry.fromRow(Map r) : date = r['date'] as String, weightKg = (r['weight'] as num).toDouble(); }` (the query aliases `CAST(weight_kg AS REAL) AS weight`).

- [ ] **Step 2: `BodyweightRepository`** (`bodyweight_repository.dart`): `const BodyweightRepository(this.db);`
  - `Stream<List<BodyweightEntry>> watchSeriesAsc()` → `db.watch('SELECT date, CAST(weight_kg AS REAL) AS weight FROM bodyweight_logs ORDER BY date ASC').map((rs) => rs.map(BodyweightEntry.fromRow).toList())`.

- [ ] **Step 3: `StatsRepository`** (`stats_repository.dart`): `const StatsRepository(this.db);` — all take `{required DateTime weekStart}` and bind the date via the NAMED `parameters:` arg — `db.watch(sql, parameters: [isoDate(weekStart)])` (`watch` uses `parameters:`; only `get`/`getAll`/`getOptional` take a trailing positional list):
  - `Stream<int> watchSetsThisWeek` → `SELECT COUNT(*) AS n FROM sets s JOIN sessions se ON se.id=s.session_id WHERE s.is_warmup=0 AND se.date >= ?` (map first row `n`).
  - `Stream<int> watchDistinctMusclesThisWeek` → `SELECT COUNT(DISTINCT ex.muscle_group) AS n FROM sets s JOIN sessions se ON se.id=s.session_id JOIN exercises ex ON ex.id=s.exercise_id WHERE s.is_warmup=0 AND se.date >= ?`.
  - `Stream<int> watchPrsThisWeek` → `SELECT COUNT(*) AS n FROM sets s JOIN sessions se ON se.id=s.session_id WHERE s.is_pr=1 AND se.date >= ?`.
  - `Stream<List<({String exerciseId, double weight, int reps, String date})>> watchRecentPrs({int limit=6})` → `SELECT s.exercise_id, CAST(s.weight_kg AS REAL) AS weight, s.reps, se.date FROM sets s JOIN sessions se ON se.id=s.session_id WHERE s.is_pr=1 AND s.is_warmup=0 ORDER BY se.date DESC, se.created_at DESC LIMIT ?` (no weekStart).
  - `Stream<List<({String muscle, int sets})>> watchWeeklyVolumeByMuscle` → `SELECT ex.muscle_group AS muscle, COUNT(*) AS sets FROM sets s JOIN sessions se ON se.id=s.session_id JOIN exercises ex ON ex.id=s.exercise_id WHERE s.is_warmup=0 AND se.date >= ? GROUP BY ex.muscle_group ORDER BY sets DESC`.

- [ ] **Step 4: `MuscleTargetRepository`** (`muscle_target_repository.dart`): `const MuscleTargetRepository(this.db);` (`MuscleTarget`/`fromRow` already in models.dart)
  - `Stream<List<MuscleTarget>> watchTargets()` → `db.watch('SELECT id, muscle, target_sets FROM muscle_targets ORDER BY muscle').map((rs) => rs.map(MuscleTarget.fromRow).toList())` (nested map — `watch` emits a `ResultSet` per change, like the other repos; do NOT `.map(MuscleTarget.fromRow)` directly).
  - `Future<void> seedDefaultsIfEmpty(String userId)` → if `(await db.get('SELECT COUNT(*) AS n FROM muscle_targets'))['n'] == 0`, `db.writeTransaction` inserting 8 rows `(uuid.v4(), userId, muscle, target_sets, <nowIso>)` with defaults: `quads 16, back 14, hamstrings 12, chest 12, shoulders 12, biceps 10, calves 9, triceps 9`. (uuid from `package:powersync/powersync.dart`.) The userId comes from the synced data — see Step 6.

- [ ] **Step 5: Rotation helpers on `DayTemplateRepository`:**
  - `Future<DayTemplate?> nextInRotation(SessionRepository sessionRepo)` → `final days = await watchDays().first; if (days.isEmpty) return null; final recent = await sessionRepo.watchRecentSessions(limit:1).first; final lastId = recent.isEmpty ? null : recent.first.dayTemplateId; if (lastId==null) return days.first; final i = days.indexWhere((d)=>d.id==lastId); return i<0 ? days.first : days[(i+1)%days.length];`
  - `Future<Set<String>> templateIdsTrainedThisWeek({required DateTime weekStart})` → `final rows = await db.getAll('SELECT DISTINCT day_template_id FROM sessions WHERE date >= ? AND day_template_id IS NOT NULL', [isoDate(weekStart)]); return rows.map((r)=>r['day_template_id'] as String).toSet();`

- [ ] **Step 6: A userId source for the seed** — add to `SessionRepository`: `Future<String?> anyUserId() async => (await db.getOptional('SELECT user_id FROM sessions LIMIT 1'))?['user_id'] as String?` — used as the seed's owner when no auth identity is threaded (the dev session rows already carry the stamped user_id). If null (no sessions yet), skip seeding until first session exists; the dashboard handles empty targets gracefully.

- [ ] **Step 7: Tests** — `app/test/data/stats_repository_test.dart` (optional, DB-bound; if a fake DB is impractical, assert the SQL strings via small pure helpers or skip with a note) + a `nextInRotation` unit test with a fake `DayTemplateRepository`/`SessionRepository` (wrap-around + default-first). At minimum `make -C app analyze` clean. **Run** `make -C app test`.

- [ ] **Step 8: Commit** — `git add app/lib/data app/test/data && git commit -m "feat(app): stats/bodyweight/muscle-target repos + rotation helpers"`

### Task 5: Today presentational widgets — StatTile, WeekStrip, VolumeBars

**Files:** Create `app/lib/widgets/{stat_tile,week_strip,volume_bars}.dart`. Spec source: `screen-today.jsx`. Pure presentational (fed data via constructor).

- [ ] **Step 1: `StatTile`** — `StatTile({required String label, required String value, String? unit, Widget? spark, String? sub, VoidCallback? onTap})`. `WCard`-style (surface bg, line border, radius, padding 13/14): mono uppercase label (10, ls 0.08, faint, mb 8); baseline Row(value `WorkoutType.display(27,w700)` + optional unit `mono(12,dim)`); then `spark` (mt 8) OR `sub` `mono(10.5,dim)` (mt 6). `onTap` wraps in InkWell.

- [ ] **Step 2: `WeekStrip`** — `WeekStrip({required List<({String name, int? weekday, bool isNext, bool done})> days})`. Row of up to 4 chips (gap 7, each flex 1, radius `AppRadius.radius*0.7`, padding 10v/6h): next = accent bg; weekday label `mono(9.5)` (accentInk@0.7 if next else faint) via `weekdayShort`; name `display(13,w700)` (accentInk if next else text, spaces removed); status slot (14px): next→`mono 'NEXT'`, done→16px surface3 pill with `WIcons.check` accent, else 5px lineStrong dot.

- [ ] **Step 3: `VolumeBars`** — `VolumeBars({required List<({String muscle, int sets, int target})> rows})` in a `WCard(padding 16/16/8)`. **`target` is NON-null** (Task 7 coalesces a goalless muscle to `target = sets`, so it reads on-target / never muted and the math never divides by null). `max = rows.fold(1, (m,r) => [m, r.sets, r.target].reduce(max))`; each row Row(crossAxis center, gap 12, mb 11): label width 74 `body(12.5,dim)`; `Expanded` track height 7 surface3 pill — `Stack`: fill `FractionallySizedBox(widthFactor: sets/max)` (color `lineStrong` if `sets<target` else `accent`), plus a 1.5px vertical tick at `target/max` (`Align(alignment: Alignment((target/max)*2-1, 0))`, text@0.4, overhang ±3); value width 38 right `mono(11.5)` (dim if under target else text) '{sets}/{target}'.

- [ ] **Step 4: Widget tests** (`app/test/widgets/today_widgets_test.dart`): WeekStrip renders a 'NEXT' label for the next chip + a check for a done chip; VolumeBars shows muted fill when `sets<target` (assert the fill color) and the '{sets}/{target}' text. Run `make -C app test`.

- [ ] **Step 5: Commit** — `git add app/lib/widgets/{stat_tile,week_strip,volume_bars}.dart app/test/widgets/today_widgets_test.dart && git commit -m "feat(app): Today stat tile, week strip, volume bars"`

### Task 6: SplitCard hero (pager + dashed Custom slide + dots/arrows)

**Files:** Create `app/lib/widgets/split_card.dart` (contains `SplitCard`, `DaySlide`, `CustomSlide`, a dashed-border painter). Spec source: `screen-today.jsx` (the hero pager). This is the most fidelity-heavy widget — port faithfully.

- [ ] **Step 1: Implement `SplitCard`** (StatefulWidget) — `SplitCard({required List<({DayTemplate day, int exerciseCount, String lastAgo})> days, required int nextIndex, required void Function(DayTemplate?) onStart})`:
  - A `PageView` (controller starts at `nextIndex`) of `DaySlide`s + a final `CustomSlide`. Card body animates accent↔surface theming over ~250ms (`AnimatedContainer`): day slides = accent bg + `accentInk` text; custom slide = surface bg + dashed `lineStrong` border (custom painter) + `WIcons.plus`.
  - `DaySlide`: eyebrow `mono(11,w700,ls 0.1)` = `i == nextIndex` → 'NEXT IN ROTATION', else 'SWITCH TO · {WEEKDAY}' (key off the rotation target passed in as `nextIndex`, NOT literal index 0 — the pager opens at `nextIndex`, which is usually non-zero); name `display(40,w700,accentInk,ls -0.03)` ellipsis; focus `display(19,w600)`; stats Row (gap 18, mt 16): Exercises = `exerciseCount`, Est. time = `~{max(20, (slots*9+10).round())}m`, Last = `lastAgo`|'—' — each `mono(16,w700)` over `mono(9.5,uppercase)`. A faint decorative `WIcons.dumbbell` (~150px @0.08, `Positioned`+`IgnorePointer`, day slides only).
  - `CustomSlide`: eyebrow 'NO TEMPLATE', name 'Custom', sub 'Build it as you go', hint Row (`WIcons.plus` + 'Add exercises live during the session').
  - Fixed full-width **Start button** below the pager (height 52, mt 18, radius `AppRadius.radius*0.8`): on a day slide → `WIcons.bolt` + 'Start workout' (accent bg / accentInk); on custom → `WIcons.plus` + 'Start empty' (surface). Calls `onStart(currentSlideIsDay ? day : null)`.
  - dots + arrows row below on app bg: 28px arrow circles (disabled at ends), pill dots animating width 6↔18 (`AnimatedContainer` ~200ms); arrows/dots call `PageController.animateToPage(.., 250ms, Curves.ease)`.

- [ ] **Step 2: Widget test** — pumping `SplitCard` with 2 days: tapping Start on the visible day slide calls `onStart` with that day; advancing to the Custom slide and tapping Start calls `onStart(null)`. Run `make -C app test`. (Animations: `tester.pumpAndSettle()`.)

- [ ] **Step 3: Commit** — `git add app/lib/widgets/split_card.dart app/test && git commit -m "feat(app): Today split-picker hero pager"`

### Task 7: TodayScreen composer

**Files:** Create `app/lib/ui/today_screen.dart`. Assembles the dashboard per the synthesis `todayUiSpec`. Spec source: `screen-today.jsx`.

- [ ] **Step 1: Implement** `TodayScreen({required void Function(DayTemplate?) onStart, required void Function(String exId) onOpenExercise, required VoidCallback onOpenProfile})` (StatefulWidget). It owns the repos (or receives them — match AppShell's wiring in Task 8) and composes:
  1. **Greeting header**: 46px accent avatar with initials (placeholder 'A' or derived from auth email; tap → `onOpenProfile`); mono line `"{fmtDate(isoDate(now), weekday:true)} · {restOrTrain}"` (`fmtDate` takes an ISO string, so pass `isoDate(now)`; train day name if any `day_template.scheduledWeekday == today Mon0` else 'Rest day'); display 'Ready to train'.
  2. **SplitCard** (Task 6) fed by `watchDays()` + `nextInRotation` (compute `nextIndex`; `exerciseCount` from each day's `slots.length`; `lastAgo` from the most-recent session for that day or '—').
  3. **This week**: `SectionLabel(label: 'This week')` + `WeekStrip` — chips for the 4 days (or all days), `isNext` from `nextInRotation`, `done` from `templateIdsTrainedThisWeek(weekStart(now))`. (NOTE: the existing `SectionLabel` takes a **required named `label:`** and an optional `Widget? action` — never a positional string or a raw count.)
  4. **Stat tiles**: bodyweight (`fmtWt(currentBw)` + `uLabel` + `Sparkline(last 18)`, tap → `onOpenExercise('__bodyweight__')` stub) / Sets/wk (`watchSetsThisWeek`, sub 'across {watchDistinctMusclesThisWeek} muscles') / PRs/wk (`watchPrsThisWeek`, sub 'new top sets').
  5. **Recent PRs**: `SectionLabel(label: 'Recent PRs', action: Text('$count', style: WorkoutType.mono(size: 11, color: context.tokens.dim)))` + up to 4 rows from `watchRecentPrs` (resolve names via `ExerciseRepository`), tap → `onOpenExercise(exId)`.
  6. **Weekly volume**: `SectionLabel(label: 'Weekly volume')` + `VolumeBars` from `watchWeeklyVolumeByMuscle` LEFT-merged with `watchTargets()` by muscle, **coalescing a missing target to that muscle's own `sets`** (`target = matchedTarget ?? sets`) so a just-seeded/goalless muscle renders on-target (never muted) and nothing compares against null.
  - Outer `ListView` padding `EdgeInsets.symmetric(horizontal:16)` + `only(top:8, bottom:96)`. Wrap stream-fed sections in `StreamBuilder`; render gracefully empty (no bodyweight → '—'/no spark; empty PRs/volume collapse). Watch `UnitService` for weight displays.
  - Call `MuscleTargetRepository.seedDefaultsIfEmpty(userId)` once on first load (in `initState` via the repo + `SessionRepository.anyUserId()`); guard against repeat.

- [ ] **Step 2: Gate** — `make -C app analyze` clean. (Visual verified at Task 10.)

- [ ] **Step 3: Commit** — `git add app/lib/ui/today_screen.dart && git commit -m "feat(app): Today dashboard composer"`

### Task 8: App shell — AppShell + WTabBar + PlaceholderTab + session_launcher

**Files:** Create `app/lib/shell/{app_shell,w_tab_bar,placeholder_screen,session_launcher}.dart`. Spec source: synthesis `navShellPlan` + README Navigation.

- [ ] **Step 1: `session_launcher.dart`** — extract from the current `main.dart` launcher: `Future<void> startSession(BuildContext context, {DayTemplate? template})` (build `ActiveSessionController`; `buildFromTemplate(...)` with `ExerciseRepository(db)`/`DayTemplateRepository(db)`/`SessionRepository(db)` if template != null, else `seedEmpty(name:'Custom', focus:'')`; guard `context.mounted`; push on **root navigator** a `ChangeNotifierProvider<ActiveSessionController>.value(value: controller, child: const ActiveSessionScreen())`). Plus `Future<DayTemplate?> nextInRotation(DayTemplateRepository, SessionRepository)` delegating to the repo helper (Task 4).

- [ ] **Step 2: `placeholder_screen.dart`** — `PlaceholderTab({required String title, IconData? icon})`: `ColoredBox(tokens.bg)` + centered Column(faint glyph, `display(22)` title, mono 'Coming soon' faint), bottom inset 96 + safe area.

- [ ] **Step 3: `w_tab_bar.dart`** — `WTabBar({required int currentIndex, required ValueChanged<int> onTab, required VoidCallback onStart})`: `ClipRect`+`BackdropFilter(blur 16)` over `Container(color: tokens.bg.withValues(alpha:0.88))`, top hairline. Row of 5: Today(0)=`WIcons.home`, Progress(1)=`WIcons.chart`, [FAB], History(2)=`WIcons.history`, Plan(3)=`WIcons.plan`. Each tab btn = Column(icon ~23 over mono label 9.5/w600) active=accent else faint, ≥44px hit area → `onTab`. FAB = 52px accent circle, `WIcons.bolt` accentInk, overhanging (`Transform.translate(-22)`), accent@0.45 shadow blur 22 → `onStart`. Bottom padding `9 + viewPadding.bottom`.

- [ ] **Step 4: `app_shell.dart`** — `AppShell({required VoidCallback onLogout})` (StatefulWidget, `_index=0`): `Scaffold(extendBody:true, body: Stack([ IndexedStack(index:_index, children:[TodayScreen(onStart: _start, onOpenExercise: _openExercise, onOpenProfile: _openProfile), PlaceholderTab('Progress'), PlaceholderTab('History'), PlaceholderTab('Plan')]), Align(bottomCenter: WTabBar(currentIndex: _index, onTab: (i) => setState(() => _index = i), onStart: _fabStart)) ]))`. **Index mapping is identity, NOT offset:** `WTabBar` renders 5 visual slots `[tab0, tab1, FAB, tab2, tab3]` but its `onTab` emits IndexedStack indices `0..3` directly (Today=0, Progress=1, History=2, Plan=3); the FAB is a SEPARATE `onStart` callback, not an index. Do NOT add a +1 offset for History/Plan — that would mis-route the tabs. `_fabStart`: `final t = await nextInRotation(dayRepo, sessionRepo); if(!mounted) return; await startSession(context, template:t); if(mounted) setState(()=>_index=0);` (FAB never dead — `t==null` starts empty). `_start(day)` (from Today's hero): `await startSession(context, template:day); if(mounted) setState(()=>_index=0)`. `_openProfile`/`_openExercise`: push a `PlaceholderTab('Profile'/'Progress')` root overlay. Construct repos once in `initState`.

- [ ] **Step 5: Gate** — `make -C app analyze` clean. **Commit** — `git add app/lib/shell && git commit -m "feat(app): 5-tab app shell with center FAB"`

### Task 9: main.dart wiring + cleanup

**Files:** Modify `app/lib/main.dart`; delete `app/lib/ui/home_screen.dart`.

- [ ] **Step 1: Swap** the logged-in branch: `home: _loggedIn ? AppShell(onLogout: _onLogout) : LoginScreen(auth: _auth, onLoggedIn: _onLoggedIn)`. Keep `MultiProvider`/`UnitService`, the login gate, `_onLoggedIn → connectSync`, `_onLogout → disconnectAndClear`. Delete the old `LauncherScreen` + `_DayTile` from `main.dart`.

- [ ] **Step 2: Delete dead file** — `git rm app/lib/ui/home_screen.dart` (the Plan-6 throwaway, no longer referenced; confirm nothing imports it: `grep -rn home_screen app/lib`).

- [ ] **Step 3: Gate** — `make -C app analyze` clean; `make -C app test` all green. **Commit** — `git commit -am "feat(app): mount AppShell as the home; remove throwaway launcher + home_screen"`

### Task 10: Verify — analyze + test + live smoke (INLINE)

- [ ] **Step 1: GATE 1+2** — `make -C app analyze` (zero issues); `make -C app test` (all green incl. new dates/sparkline/today-widget/split-card/rotation tests).
- [ ] **Step 2: GATE 3 build** — `make -C app build` → Linux bundle builds.
- [ ] **Step 3: Live smoke** — ensure the stack is up; `make -C app run`; log in (`me@example.com`/`devpassword`). Confirm: Today renders; the greeting shows the day's focus/Rest; SplitCard shows the 4 days with focus + 'NEXT IN ROTATION' on the rotation target; WeekStrip shows weekday labels + the next/done state; stat tiles populate (PRs/wk + Recent PRs reflect the sessions logged in Plan 7's validation; bodyweight tile shows '—' until bodyweight exists); VolumeBars show per-muscle bars vs the seeded targets; the **center FAB** starts the next-in-rotation session and the **hero Start** starts the visible slide; finishing returns to the Today tab; the 4 tabs switch (Progress/History/Plan = placeholders); the avatar opens the Profile placeholder.
- [ ] **Step 4: Verify the muscle_targets seed landed** — `docker exec workout-tracker-postgres-1 psql -U postgres -d workout_tracker -c "SELECT muscle, target_sets FROM muscle_targets ORDER BY muscle;"` — expect the 8 default rows for the dev user (written client-side on first dashboard load + synced up).

---

## Deferred to later plans
- Progress (Lift metric tabs + LineChart) + Bodyweight logging (write path) — replaces the bodyweight-tile/Recent-PR stubs.
- History (week grouping, summary tiles).
- Plan editors (Split day/slot + Exercise library — writes the trait/focus/weekday columns).
- Profile & Settings + `SettingsService` (client-local unit/theme/accent + **configurable server URL**) — replaces the Profile placeholder + the hardcoded `apiBaseUrl`.
- `LineChart` widget; real per-head delt taxonomy; bodyweight write/upsert-by-day.
