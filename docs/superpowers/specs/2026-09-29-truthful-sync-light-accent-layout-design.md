# Truthful sync, readable light accent, layout that holds: design

Date: 2026-09-29
Status: approved (decisions confirmed in session)
Origin: the post-0.16.0 critique (`.impeccable/critique/2026-09-29T11-38-39Z__app-lib.md`), P1 issues #2, #3 and #4. These ship on the same branch as `2026-09-29-live-loop-stability-design.md` (issue #1).

## Goal and success

- **Sync:** the label says what is true. Away from home the phone is offline, not in error. Today speaks up only when data is at risk.
- **Light theme:** accent-coloured text and marks are readable (≥ 4.5:1) with every accent.
- **Layout:** no overflow and no word split across lines on any main screen at 320dp or 412dp, 1.0× or 2.0× text, in en, de or it, including with very long names.

The work is done when the automated sweep for these conditions passes and the device checks at the end hold.

## Decisions

- **Offline is a state, not an error.** Not connected means `Offline`, with the last sync time when known, whether or not PowerSync recorded an error. `Sync error` is only for a failure while connected. A home server that is down therefore also reads as Offline, which is true from the phone's point of view.
- **Today shows a quiet line only when data is at risk:**
  - signed in with sync on;
  - not connected;
  - unsynced local changes exist;
  - the last sync is more than 3 days old, or there has never been one.
- **A new `accentText` token** is used for accent as text or a thin mark on a surface: the accent in dark mode, and a computed darker shade in light mode. The existing `accent` stays for fills. The existing `accentInk` (dark ink *on* accent fills) is unchanged.
- **Tight labels shrink a little, then ellipsize.** A word is never split across lines. One shared `FitLabel` widget does this.
- **The three font families are bundled as assets.** `google_fonts` finds them without a network fetch, so the first offline run and the tests use the real faces.

## Design

### 1. Truthful sync (`sync/sync_status_ui.dart`, `ui/profile_screen.dart`, Today)

**State mapping (pure, in `sync_status_ui.dart`):** `syncDotStateFor` becomes:

```
if (!connected) → offline
if (hasError)   → error
if (syncing)    → syncing
else            → synced
```

The doc comment states the reason: a local-first app can't tell "server down" from "no route to the server", and both mean the phone is offline.

**Profile label:**
- `offline` shows `Offline · synced 3h ago` (new `syncOfflineSince`, which reuses the relative-time buckets) when `lastSyncedAt` is known, else `Offline`.
- The dot stays `faint` for offline and `danger` only for error.
- An expired session still overrides both, as today.

**Data-at-risk rule (pure, in `sync_status_ui.dart`):**

```dart
bool syncAtRisk({
  required bool signedIn,
  required bool syncEnabled,
  required bool connected,
  required int pendingChanges,
  required DateTime? lastSyncedAt,
  required DateTime now,
});
```

True only if all of these hold:
- `signedIn && syncEnabled && !connected`;
- `pendingChanges > 0`;
- `lastSyncedAt` is null, or `now - lastSyncedAt > 3 days`.

The 3 days is a named constant, `syncRiskAfter`.

**`SyncHealth` (new, `sync/sync_health.dart`):**
- An app-scoped `ChangeNotifier` created in `main.dart` next to the auth store, following the `auth.sessionExpired` pattern.
- It listens to `db.statusStream`, and re-reads `pendingUploadCount()` on every status event and every 5 minutes.
- It exposes `bool atRisk` and `DateTime? lastSyncedAt`.
- Signed-in and sync-enabled come from the existing auth store and settings.
- It must follow the app rule for streams: a single subscription it owns and cancels in `dispose`, and never a stream re-listened by a widget.

**Today:**
- A quiet card in the same slot as `SyncPausedBanner`: surface fill, `faint` cloud icon, body text in `dim`, not danger-tinted.
- Copy `todaySyncAtRisk`: "Not synced since {date} · changes are on this phone only". When there has never been a sync: `todaySyncAtRiskNever`, "Not synced yet · changes are on this phone only".
- Tapping it opens Profile.
- The expired banner wins when both apply, so only one card ever shows.

**Strings (en/it/de/es):** `syncOfflineSince` ("Offline · synced {time}"), `todaySyncAtRisk`, `todaySyncAtRiskNever`.

### 2. Readable accent in light mode (`theme/tokens.dart`, call sites)

**Token:**
- `WorkoutTokens.accentText`. Dark: `accent`.
- Light: `accentTextOn(accent, [bg, surface, surface2, surface3])`, a pure function. It lowers the HSL lightness of the accent in 0.01 steps, keeping hue and saturation, until the WCAG contrast ratio is ≥ 4.5 against every given surface.
- It is computed once per theme build and lerped like the other tokens.

**Usage rule (applied to every `tokens.accent` use in `app/lib`):**
- **`accentText`:** accent used as a text colour, an icon colour, or a mark ≤ 8dp thick. That covers:
  - progress bars;
  - chart lines and dots;
  - the ruler's centre marker and centre value;
  - borders of selected chips;
  - active nav labels and icons;
  - set indices;
  - the elapsed timer;
  - the `NEXT` / `ACTIVE NOW` eyebrows;
  - delta text.
- **`accent`:** accent as a fill behind content: buttons, the hero card, the FAB, filled chips and badges (their content stays `accentInk`), and swatches.
- **Material widgets:** those that draw the accent as foreground on a surface get `accentText` through their component theme in `app_theme.dart`. That includes `TextButton` foreground, focus and selection colours, and the progress indicator. `ColorScheme.primary` stays `accent`, so filled components keep the true accent.

**Check:** a test asserts `accentText` ≥ 4.5:1 on all four light surfaces for all five accents, and on all four dark surfaces for all five accents. Dark uses the plain accent, so this proves it already passes.

Out of scope: `danger` in light mode (≈ 2.9:1) is a known gap for a later pass.

### 3. Layout that holds (widgets across Today, Plan, History, Profile, live workout, summary, nav)

**`FitLabel` (new, `widgets/fit_label.dart`):**
- `FitLabel(text, {required style, maxLines = 1, minScale = 0.8, textAlign})`.
- It lays out at the full style. If the text needs more than `maxLines` lines, or any single word is wider than the available width, it retries at smaller scales in 0.05 steps down to `minScale`.
- If it still doesn't fit, it renders at `minScale` with `maxLines: 1` and an ellipsis. So a word is never split: "BODYWEIGHT" becomes smaller, then "BODYWEI…", never "BODYWEI/GHT".
- Scaling multiplies the ambient `TextScaler`, so users' text size is respected, never replaced.
- Semantics carry the full text.

**Fixes** (each names the critique's evidence; the goldens/shots are in the critique run's scratchpad):

| Where | Now | Change |
|---|---|---|
| `widgets/split_card.dart` hint row (~231) | 50px overflow at 320 | the hint `Text` goes in `Flexible`, 2 lines max, ellipsis |
| `widgets/split_card.dart` eyebrow (~65) | long German name wraps and overflows 5px | 1 line, ellipsis |
| `widgets/week_strip.dart` day chip name (~145) | `FittedBox` shrinks to ~4px | `FitLabel`, `maxLines: 2`; `NEXT` stays one line and isn't clipped |
| `widgets/stat_tile.dart` label (~84) and sub-label (~143) | "BODYWEI/GHT", "−15 vs last …" | `FitLabel`: label `maxLines: 2`, sub-label `maxLines: 1` |
| `widgets/sparkline.dart:19` / `today_screen.dart:475` | fixed 92 wide, spills into the next tile | width from the tile's constraints |
| `ui/profile_screen.dart` `_Row` title (~128) | "Compou/nd rest" at 320 | `FitLabel` title; subtitle 1 line, ellipsis |
| `session/session_summary_screen.dart` tiles and exercise names | "Duratio/n", "Kurzhantel-Schräg/bankdrücken" | tile labels `FitLabel`; names 2 lines, ellipsis |
| bottom nav labels | "Progres/s" at 2.0× | `FitLabel` |
| `ui/history_screen.dart` week header | header and count collide at 2.0× | the count goes to its own line when they don't fit side by side; the PR badge no longer covers the date |
| `session/exercise_block.dart` completion badge | clipped to "2/" at 2.0× | badge sizes to its content (min 40dp) |
| `ui/split_tab.dart` day card (~165) | "N exercises" pushed off by a long focus | the count gets its own non-flex slot; focus ellipsizes |
| `ui/plan_screen.dart` sub-tabs | "Exercises" cut to "Exercise" | `FitLabel` |
| Today weekly volume rows | counts wrap digit by digit, names cut to "Shou…" | the count column is sized from the measured widest count at the current scale; names `FitLabel` |

**Fonts:**
- The static TTFs for Space Grotesk (400–700), Hanken Grotesk (400–800) and JetBrains Mono (400–700) go in `app/assets/google_fonts/`, with the OFL licence file, and are declared in `pubspec.yaml`.
- The file names follow the `google_fonts` asset convention (`HankenGrotesk-SemiBold.ttf`, etc.) so the existing `GoogleFonts.*` calls pick them up.
- Runtime fetching stays enabled as a fallback.

**Regression sweep (`app/test/layout/`):**
- A shared harness, `app/test/support/screen_harness.dart`. It is built from the critique's evidence harness:
  - opens a real test database with `dbForTests` inside `tester.runAsync`;
  - seeds long names;
  - pumps real screens with real-async ticks;
  - awaits `GoogleFonts.pendingFonts()`.
- It pumps Today, Plan (split + exercises + targets), History (list + expanded), Progress, Profile, the live workout and the summary.
- Conditions: {320, 412}dp × {1.0, 2.0}× × {en, de, it}.
- Each case fails on any overflow (`tester.takeException()`), and on any word split across lines. `expectNoSplitWords` walks every `RenderParagraph` and flags a line that starts between two letters.
- The seeds use a ~60-character exercise name and a ~40-character day name.
- The exercise editor's RIR steppers get their missing widget test here, now that the harness can mount the editor.
- `AGENTS.md` / `app/CLAUDE.md`: correct the note that screens owning PowerSync watch-streams can't be mounted, and point to the harness.

## Out of scope

The P2 and lower critique items:
- first-run empty states;
- lb volume units;
- locale number formats;
- the unregistered `'HankenGrotesk'` / `'JetBrainsMono'` family names in `hankenTextTheme` and `line_chart`. Bundling makes the faces available, but those names still don't resolve.
- screen-reader semantics;
- Plan dirty guard;
- the two small tap targets;
- `danger` contrast in light mode.

## Acceptance

**Tests:**
- `syncDotStateFor` truth table.
- `syncAtRisk` boundaries: 3 days exactly vs just over, zero pending, never synced, signed out, sync off, connected.
- `SyncHealth` recomputes on a status event and disposes its subscription.
- Profile label for offline with and without `lastSyncedAt`.
- Today card shown and hidden per `atRisk`; expired wins.
- `accentTextOn` contrast for all accents on both palettes; a representative light-theme widget uses `accentText` for its eyebrow.
- `FitLabel`: shrinks before ellipsizing, never splits a word, respects the ambient scale, keeps full-text semantics.
- The layout sweep passes on every screen × condition.
- Exercise-editor RIR low/high steppers stay ordered.

**Device checks:**
1. Away from home, Profile reads `Offline · synced …` with a grey dot.
2. With a pending change and an old last-sync (or airplane mode on a device that last synced over 3 days ago), Today shows the quiet card, and tapping it opens Profile.
3. Light theme with each accent: eyebrows, nav, timer and set numbers are readable.
4. At 2.0× system font: nav, Today tiles, History header, Profile rows and the live badge are whole.
5. Fonts are right on a fresh install with no network.
