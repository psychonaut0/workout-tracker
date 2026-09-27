# Polish from the on-device walkthrough: design

Date: 2026-09-27
Status: approved (decisions confirmed in session)
Origin: the adb walkthrough of 0.15.0 on the phone (2026-09-26). The bugs it found shipped as 0.15.1. This covers what remains: things that work but look inconsistent, mislead slightly, or hide state.

## Goal and success

Progress should show real progress. Today's tiles should read cleanly. The screens should look like one app. An expired session must never again be visible only inside Profile.

Nothing here changes data, storage or sync behaviour.

The work is done when every item below is right on the phone, with no overflow at 320dp width and 1.3× text in en/it/de/es.

## Decisions

- **Progress opens on the last trained exercise.** It falls back to the current alphabetical pick when there is no history.
- **Top set shows rep changes.** When the weight equals the previous session's, the change column and the 12-week tile report the reps instead of "=" / "0 kg".
- **Square ± is the only stepper style outside the live workout.** The ruler stays only in the live workout and History's set editor.
- **An expired session shows a banner on Today**, as well as the Profile row.

## Design

### Progress (`ui/progress_screen.dart` and its helpers)

- **Default exercise.**
  - A pure helper, `defaultProgressExercise(lastTrainedId, catalog)`: the exercise of the most recent working set if it is in the catalog, otherwise the current fallback.
  - The last-trained id comes from one query: `sets JOIN sessions ORDER BY sessions.date DESC, sets.set_number DESC LIMIT 1`, non-warmup, through a repository method.
  - A pick the user makes still wins while the screen is alive, as today. An `initialTarget` passed in (from Today's PR rows) still wins.
- **Empty chart.** With fewer than 2 points, the chart card shows a centred message, "Log one more session to see a trend" (`progressTrendNeedsMore`), instead of an empty frame. With 0 points it shows the existing no-data text.
- **Rep change on Top set.**
  - A pure helper, `topSetChange(prev, cur)`, returns either a weight change or, when the weights are equal, a rep change.
  - The session list's change column shows "+2.5 kg" / "−2.5 kg", "+1 rep" / "−1 rep" (`progressRepDelta` with plural forms), or "same" (`progressSame`).
  - The 12-week tile works the same way. The weight change is shown when non-zero; otherwise the rep change between the first and last top sets of the window, with the same unit.
- **Change labels everywhere on Progress** (all four metrics and the bodyweight history):
  - A real minus "−" (U+2212) and "same" instead of "=".
  - One shared formatter replaces `_signedDelta`.
  - The column is right-aligned at a fixed position (a fixed-width trailing slot) in every metric's list, so it doesn't move when switching metric.
  - Delta colours are unchanged, including the goal-aware bodyweight colours.

### Today (`ui/today_screen.dart`, `widgets/week_strip.dart`)

- **Session-expired banner.**
  - Shown when `auth.sessionExpired` is true, as the first card under the header.
  - A slim `danger`-tinted card: "Sync paused · Sign in again" (`todaySyncPaused`), with a chevron.
  - Tapping opens the same sign-in-again flow as Profile, which is lifted out of `ProfileScreen` into a shared function (`signInAgain(context, auth, settings)`), so both screens use one flow.
  - It disappears when the flag clears. It is at least 48dp tall and labelled for screen readers.
  - `TodayScreen` needs the `AuthStore`: `AppShell` already holds `auth` and passes it down.
- **Stat tiles.**
  - Each tile label reserves two lines of height (maxLines 2 plus a fixed min height), so values line up across the three tiles whether or not a label wraps.
  - The PR tile's subtitle becomes "last 12 Sep" (`todayLastPrDate(date)`), the date of the latest PR, instead of the truncated exercise name.
- **Week strip.** A chip that is both `isNext` and `done` shows the NEXT label with a small ✓ beside it. Today it shows only NEXT.

### Consistency

- **Plan header** (`ui/plan_screen.dart`). It matches Progress and History: a mono eyebrow ("4 training days", replacing the "N training days in rotation" line under the segments) and the large title "Plan". The icon chip goes. The Split / Exercises / Targets segments stay below it.
- **Plan day cards** (`ui/split_tab.dart`).
  - The left block shows only the weekday (or "—" for unscheduled), in the same style History uses for its date block.
  - The exercise count moves into the meta line: "Push · 7 exercises" (`splitDayMeta(focus, n)`, with plural forms).
- **Steppers.**
  - The bodyweight sheet (`ui/add_weight_sheet.dart`) replaces its round ± with the square stepper buttons. The large value display stays.
  - The RIR target text field becomes two `WStepper`s, **RIR low** and **RIR high** (0–5, with low ≤ high enforced by clamping the other), laid out like Rep low / Rep high. This applies to the day editor's slot panel and the exercise editor's default prescription.
  - `rirTryParse`/`rirToString` stay for the summary text and export. The raw `rirText` field in `DaySlotState` goes; `SlotDraft.rirLow/rirHigh` are edited directly.
  - A "Default" / null RIR in the exercise editor maps to the existing default (1–1) on display, and is saved only when changed. This keeps today's parse-on-save meaning: an untouched field saves nothing new.
- **Profile** (`ui/profile_screen.dart`).
  - Language gets its own icon: a new `WIcons.globe`, following the existing icon set.
  - The footer reads "Reps · v{version}".
  - "Apply / Switch server" shows as a normal secondary button when the typed URL differs from the saved one and is valid. It shows as disabled only when there is nothing to apply.
  - The Goal row gets a chevron like the other navigable rows.
- **Exercise picker** (`ui/exercise_sheet.dart`, `showExerciseSheet`, which already receives `current`).
  - The currently shown exercise's row gets an accent border and a trailing ✓.
  - The leading dot, which only duplicated "compound", is removed. Rows keep their 48dp height.

### Strings (en/it/de/es)

- **Add:**
  - `progressTrendNeedsMore`, `progressRepDelta` (plural), `progressSame`;
  - `todaySyncPaused`, `todayLastPrDate`;
  - `splitDayMeta` (plural), `planDaysEyebrow` (plural);
  - `dayEditorRirLow`, `dayEditorRirHigh` (reused in the exercise editor).
- **Remove** keys that become unused (the "in rotation" line, the RIR text-field hint if unused).

## Out of scope

- Any change to the live workout, the rulers, sync or data.
- Progress chart styling beyond the empty state.
- New features: goals, and anything beyond the listed items.

## Acceptance

- **Unit tests:**
  - `defaultProgressExercise`: last trained in the catalog, not in the catalog, no history.
  - `topSetChange`: weight up, down, equal with reps up, down, equal.
  - The shared change formatter: minus sign, "same", units.
  - The plural string helpers, through the l10n harness.
- **Widget tests:**
  - The Today banner shows and hides with `sessionExpired` and opens sign-in on tap, if the host can be mounted; otherwise the banner widget on its own.
  - The stat tiles' values line up when one label wraps (Italian, 320dp, 1.3×).
  - The week strip shows ✓ plus NEXT.
  - Plan day card meta, with no overflow at 320dp and 1.3×.
  - The RIR low/high steppers clamp low ≤ high.
  - The bodyweight sheet uses square buttons of at least 48dp.
  - The picker marks the current row.
- `make -C app analyze` is clean and `make -C app test` is green.
- A phone check of every screen touched.
