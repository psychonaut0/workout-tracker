# Handoff: Workout Tracker (mobile)

## Overview
A personal, single-user gym-logging mobile app focused on **progressive overload** — tracking the **top working-set weight per exercise over time**. Built around a real 4-day Upper/Lower/Push/Pull split. Core jobs: run a live workout (log sets fast), review per-exercise progression, track bodyweight, and manage the split template + exercise library.

This app is modeled on the data shape of the `psychonaut0/workout-tracker` repo (local-first PowerSync, six synced tables: exercises, sessions, sets, bodyweight_logs, day_templates, + settings).

## About the Design Files
The files in this bundle are **design references created in HTML/React-via-Babel** — interactive prototypes showing the intended look and behavior. **They are not production code to ship directly.** The task is to **recreate these designs in the target codebase's environment** using its established patterns and libraries. The original repo is **Flutter** (`app/lib/...`, Dart, PowerSync) — so the real implementation should be Flutter widgets backed by the existing PowerSync schema, using these HTML files purely as the visual + interaction spec. If reused on web, port to the codebase's framework instead.

The prototype keeps all state in-memory (resets on reload). Real persistence should use the app's PowerSync/SQLite layer.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, layout, and interactions are all intended as drawn. Recreate pixel-faithfully, then wire to real data. The prototype is a fixed **402 × 874** logical viewport (iPhone), scaled to fit; build responsively for the real device range.

---

## Data Model (most important section)

The biggest design decision: **separate exercise identity from per-day prescription.**

### Exercise (library identity + accumulated stats)
The reusable definition of a movement. Does **not** carry the day-to-day sets/reps.
- `id` (slug), `name` (string)
- `equip` (string, optional) — machine brand / setup, e.g. "Panatta", "Hammer Strength"
- `muscle` (enum: chest, back, shoulders, quads, hams, glutes, calves, biceps, triceps)
- `compound` (bool) — a **trait of the movement** (not the program). Drives default rest duration (180s vs 90s) and whether warm-ups are suggested.
- **Stats:** `pr` — best logged top-set, **derived from history** (not stored; computed as max top-set across sessions). Display read-only.
- `base` — start-weight seed (kg) to bootstrap the *first* session only; after that, history drives suggestions.
- **Default prescription** (`repLow`, `repHigh`, `work`, `warm`, `rir`) — these exist on the exercise **only as defaults that pre-fill a new template slot**. They are NOT the authoritative session values.

### Day template (the split) + Slot (per-day prescription)
A training day holds an **ordered list of slots**. Each slot = one exercise *as scheduled in this day*, carrying the authoritative prescription. The same exercise can appear in different days with different reps.
- Day: `slug`, `name` (e.g. "Upper A"), `focus` (e.g. "Push"), `day` (Mon…Sun), `items: Slot[]`
- Slot: `{ ex: exerciseId, work, repLow, repHigh, rir, warm }`
  - When a slot omits a field, fall back to the exercise's default (see `resolveSlot` in `app/data.jsx`).
  - In the prototype's seed data, `items` are bare exercise-id strings (= "use all defaults"); once edited they become slot objects. Production should store slot rows directly.

### Session + Set (logged history)
- Session: `id`, `date`, `daySlug`, `splitLabel`, `exercises: ExerciseBlock[]`, `prCount`, `durationMin`
- ExerciseBlock: `{ exerciseId, sets: Set[], topWeight, topReps, isPr }`
- Set: `{ weightKg, reps, rir, isWarmup, isTopSet, isPr }`
  - **Top set** = heaviest working set in that exercise that session. **PR** = top set that exceeds all prior top sets for that exercise.

### Bodyweight log
- `{ date (ISO yyyy-mm-dd), weight (kg) }`, one entry per day (logging same day replaces).

### Settings (app-level)
- `unit`: 'kg' | 'lb' (display only — **store everything in kg**, convert at the view layer; lb = kg × 2.2046226)
- `mode`: 'dark' | 'light'
- `accent`: hex
- `profileName`, `syncServer` (string)

---

## Design Tokens

### Color — Dark (default)
| Token | Value | Use |
|---|---|---|
| `--bg` | `#0b0b0c` | app background |
| `--surface` | `#131316` | cards |
| `--surface-2` | `#191920` | sheets / elevated |
| `--surface-3` | `#262630` | inputs, steppers, chips (off) |
| `--line` | `rgba(255,255,255,0.07)` | hairline borders / dividers |
| `--line-strong` | `rgba(255,255,255,0.14)` | stronger borders, track fills |
| `--text` | `#f3f3f1` | primary text |
| `--dim` | `rgba(255,255,255,0.62)` | secondary text |
| `--faint` | `rgba(255,255,255,0.38)` | tertiary/labels |
| `--accent` | `#c2f53a` (lime) | primary accent / CTAs / data |
| `--accent-ink` | `#0b0c08` | text/icons on accent |
| danger | `#ff6b5e` | destructive (sign out, delete text) |

### Color — Light
`--bg #f3f2ec`, `--surface #ffffff`, `--surface-2 #f6f5ef`, `--surface-3 #e9e8e0`, `--line rgba(0,0,0,0.08)`, `--line-strong rgba(0,0,0,0.15)`, `--text #15150f`, `--dim rgba(0,0,0,0.6)`, `--faint rgba(0,0,0,0.4)`. Accent unchanged.

### Accent options (Profile)
`#c2f53a` lime (default), `#5ce6a4` mint, `#ffc24b` amber, `#5cc8ff` sky.

### Typography
- **Display** (headings, numbers): **Space Grotesk** (400–700). Headings ~25–40px, weight 700, letter-spacing −0.02 to −0.03em.
- **Body/UI**: **Hanken Grotesk** (400–800). 13–16px.
- **Mono** (labels, stats, metadata, units): **JetBrains Mono** (400–700). 9–13px, uppercase labels use letter-spacing 0.06–0.12em.

### Spacing / radius / density
- `--radius`: 15px default (tweakable: sharp 9 / rounded 15 / round 22). Sub-radii use `calc(--radius * 0.4–0.8)`.
- `--pad`: 16px card padding default (compact 14 / comfy 20).
- Screen gutter: 16px. Card gap in lists: 6–10px.
- Pills/chips: border-radius 99px.
- Min tap target 44px (steppers 30–34px tall but with generous hit area; primary buttons 50–52px).

### Misc
- Tab bar uses `backdrop-filter: blur(16px)` over `color-mix(in srgb, var(--bg) 88%, transparent)`.
- Accent CTA shadow: `0 8px 22px color-mix(in srgb, var(--accent) 45%, transparent)`.

---

## Screens / Views

### 1. Today (home / dashboard)
- **Header**: round lime **avatar (initials)** top-left → opens Profile; greeting ("Sat 30 May · Rest day" mono label + "Ready to train" display).
- **Split picker hero** — ONE card whose **content pages** above a fixed Start button. Swipe (scroll-snap) or use arrows/dots to cycle: each training day (first = "NEXT IN ROTATION", others = "SWITCH TO · <day>") then a **Custom workout** slide. On the custom slide the whole card restyles (dashed `--surface` instead of solid accent) and the button reads "Start empty". Day slides show name (40px display), focus, and Exercises / Est. time / Last stats. Dots+arrows sit below the card.
- **This week** strip: 4 day chips, next = accent, completed = check, with weekday labels.
- **Stat tiles** (3): Bodyweight (with sparkline, **tappable → Progress/Bodyweight**), Sets/wk, PRs/wk.
- **Recent PRs** list (tappable rows → Progress for that exercise).
- **Weekly volume**: per-muscle horizontal bars vs target (target = tick mark; under-target = muted bar).

### 2. Active session (full-screen overlay)
The hero gym flow. Opened by any Start action.
- **Sticky header**: back (close), "<Day> · <Focus>", "<done>/<total> sets · N PRs", live **elapsed timer** (accent), and a thin progress bar.
- **Exercise blocks** (accordion): header shows completion badge (n/total or check), name, sub-label "<muscle> · <sets>×<repLow>–<repHigh> @ RIR <rir>" (from the **slot**), and current top weight + PR badge. Expanded:
  - "Last · <ago>" reference row (ghosted) showing last session's top set.
  - Column headers SET / WEIGHT / REPS / RIR.
  - **Set rows**: index (W for warmup), then either editable controls (weight stepper, reps stepper, RIR segmented 0–3) or, once checked, a static summary; right-edge check button. Completing a working set marks top/PR live.
  - **Add set** (dashed) and **Remove exercise** (for added blocks).
- **Add exercise** (dashed) → opens the exercise picker sheet (appends a block).
- **Finish workout** (disabled until ≥1 set done) → Summary.
- **Rest timer**: floating card appears on set completion (180s compound / 90s isolation), circular progress, +30s, Skip.

### 3. Session summary (overlay)
Success check, "<Day> · <Focus>", stat tiles (Duration, Sets, Volume in t/k, PRs), and a Top sets list with PR badges. "Done" → back to Today.

### 4. Progress
Per-target progression. Pick target via a tappable selector row → **bottom sheet** (search + "Tracking → Bodyweight" at top, then exercises grouped by muscle; compound dot; selected highlighted).
- **Lift view**: title "<metric> trend"; **metric tabs** (Top set / Est. 1RM / Volume / Reps); line chart (area fill, PR dots, last-point label); stat cards (Current / Best / 12wk Δ); "<metric> by session" log with per-session delta + PR badges.
- **Bodyweight view** (when target = Bodyweight): "Bodyweight trend" chart; Current / 30-day / Lowest stats; **"Log today's weight"** → add sheet with big ± steppers (0.1kg / 0.2lb) and Save; dated **History** list with deltas.

### 5. History
Sessions grouped by week. 4-week summary tiles (Sessions / PRs / Volume). Each session card: date block, "<Day> · <Focus>", ex count · duration · ago, PR badge; expandable to its exercises with top sets + PR markers (compound = accent dot).

### 6. Plan (nav tab)
Manage the split + library. Two sub-tabs:
- **Split**: list of training days (weekday, exercise count, name, focus) → tap to **edit** (name, focus, scheduled day, **ordered slot list**). Each slot row shows its per-day prescription; tap to expand inline editor (Working sets, Warmups, Rep low/high, RIR); reorder ↑↓; remove. "Add exercise" → picker sheet (seeds slot from exercise defaults). Save / Delete day. "New training day".
- **Exercises**: library grouped by muscle (row shows equipment/compound + PR) → tap to **edit**. Editor = **Identity** (name, muscle chips, equipment/machine, Compound toggle) + **Stats** (read-only PR card, Start-weight seed) + **Default prescription** (rep range/sets/warmups/RIR, labeled as pre-fill seeds). "New exercise".

### 7. Profile & Settings (overlay)
Avatar + editable name; quick stats (Sessions / PRs / Bodyweight). Groups:
- **Units**: Weight unit kg/lb (converts the whole app).
- **Appearance**: Theme dark/light; Accent swatches.
- **Sync & Backend**: editable sync-server URL + "Connected" status (PowerSync, local-first).
- **Account**: signed-in identity, Sign out (danger). App version footer.

---

## Navigation
Bottom tab bar, 5 items balanced around a center FAB:
**Today · Progress** | ⚡ (center, starts next workout) | **History · Plan**
Active tab = accent. Profile opens as an overlay from the Today avatar (not a tab). Active session, summary, and Profile are full-bleed overlays above the bar; Plan and Profile keep their own headers.

## Interactions & Behavior
- **Steppers**: weight steps by the exercise's plate increment (`step`, e.g. 2.5kg); reps by 1; bodyweight by 0.1kg/0.2lb. Values stored in kg; display converts.
- **Top-set / PR detection**: on completing working sets, recompute the block's heaviest working set; flag PR if it beats the exercise's prior best.
- **Rest timer** auto-starts on set completion; duration from `compound`.
- **Unit toggle** re-renders all weight displays app-wide (chart axes, stats, steppers, history, summary).
- **Theme/accent** applied via CSS variables on a root wrapper; live.
- **Swipe pager** uses CSS scroll-snap; arrows/dots call `scrollTo`.
- Transitions are subtle (~0.15–0.25s ease) on chevrons, toggles, card restyle, progress bars.

## State Management
- Current tab; active-session model (blocks → sets, elapsed, rest timer); selected Progress target + metric; picker/sheet open flags; profile/unit/theme/accent settings; a "version" bump to re-render after library/template/bodyweight mutations.
- Data fetching (production): read exercises, day_templates, sessions/sets, bodyweight_logs, settings from PowerSync; writes for logging sets, finishing sessions, editing templates/exercises, logging bodyweight, and settings.

## Assets
- **Fonts**: Space Grotesk, Hanken Grotesk, JetBrains Mono (Google Fonts). Swap for the codebase's equivalents if needed.
- **Icons**: simple inline line SVGs defined in `app/ui.jsx` (`Icons` map) — home, dumbbell, chart, history, bolt, timer, trophy, scale, gear/plan, trash, etc. Replace with the app's icon set; keep the same glyph meanings.
- No raster images; the device frame is prototype-only (`frames/ios-frame.jsx`) and should be dropped in production.

## Files (in this bundle, under `design/`)
- `Workout Tracker.html` — entry point: theme tokens, nav, overlays, Today header wiring, Tweaks.
- `app/data.jsx` — **data model, seed data, `resolveSlot`, `prFor`, unit helpers, mutations** (read this first).
- `app/ui.jsx` — primitives: `Icons`, formatters (`fmtWt`/`fromKg`/`toKg`/`uLabel`), `Tag`, `PRBadge`, `LineChart`, `Sparkline`, `Card`.
- `app/screen-today.jsx` — Today + split pager.
- `app/screen-log.jsx` — active session, set rows, steppers, RIR picker, rest timer.
- `app/screen-progress.jsx` — Progress, metric tabs, exercise picker sheet.
- `app/screen-bodyweight.jsx` — bodyweight progress + add sheet.
- `app/screen-history.jsx` — history.
- `app/screen-plan.jsx` — Plan: split/day editor (slots), exercise editor, library.
- `app/screen-profile.jsx` — profile & settings.
- `frames/ios-frame.jsx`, `frames/tweaks-panel.jsx` — prototype scaffolding only (do not port).

## Implementation order (suggested)
1. Tokens + nav shell. 2. Data layer wired to PowerSync (the model above). 3. Active session logging (the core loop) + rest timer + PR detection. 4. Progress chart + metric tabs. 5. Plan (slots + exercise editor). 6. Bodyweight. 7. History. 8. Profile/settings + unit/theme.
