# v0.12.16 — the gray-box crash class: re-listenable watch streams, error surfacing

**Date:** 2026-07-28
**Status:** Approved (design)
**Scope:** Eliminate the "infinite gray box" failure class rather than its current instance. Make every repository watch-stream safe to re-listen, fix a deterministic `Bad state: No element` crash in Progress reachable from Home, handle stream errors that silently freeze Home, and replace Flutter's featureless release `ErrorWidget` with a readable, copyable error card. No user-visible feature changes. Ships as v0.12.16.

The user reports the Home screen intermittently showing an infinite gray box, most often after finishing or minimizing a workout. Every claim below was reproduced or read from current code, not inferred.

---

## 0. Evidence

The Linux release bundle reproduces the crash **5/5 runs**, deterministically, against the real dev database. The exception goes to stdout, which is block-buffered when piped, so it must be redirected to a file to be captured (`timeout 20 ./workout_tracker > out.txt 2>&1`; piping to `tail` loses it to SIGTERM):

```
Bad state: Stream has already been listened to.
#6   _StreamBuilderBaseState._subscribe (package:flutter/src/widgets/async.dart:133)
#7   _StreamBuilderBaseState.initState (package:flutter/src/widgets/async.dart:107)
#8   StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5950)
...
#80  SliverMultiBoxAdaptorElement.createChild (package:flutter/src/widgets/sliver.dart:1061)
#85  RenderSliverMultiBoxAdaptor._createOrObtainChild (sliver_multi_box_adaptor.dart:357)
#86  RenderSliverMultiBoxAdaptor.insertAndLayoutChild (sliver_multi_box_adaptor.dart:517)
#87  RenderSliverList.performLayout.advance (package:flutter/src/rendering/sliver_list.dart:238)
```

It is **16 error reports per run**, not one — one full dump plus 15 in Flutter's abbreviated repeat form (release stringifies the summary as `Instance of 'DiagnosticsProperty<void>'`). The failing layout retries every frame until the offending sliver child leaves the layout range. Resizing the window while the app ran grew the repeat count from 15 to 31, confirming the trigger is **layout**, not startup. The debug bundle does not reproduce it against the same database — JIT startup is slow enough that the streams deliver before the first sliver layout.

**Mechanism.** `today_screen.dart:104-113` declares eight watch-streams as `late final` fields, assigned once in `initState` (`:129-136`) — correctly following the documented rule against creating them in `build()`. But the `StreamBuilder`s that consume them are children of a plain lazy `ListView` (`today_screen.dart:223`) with no `cacheExtent` and no keep-alive client. When a child leaves `viewport + 250px` the sliver garbage-collects it: `_StreamBuilderBaseState.dispose` cancels the subscription. Re-entering layout re-creates the same index, `initState` runs again, and `listen()` is called a second time on the same already-consumed stream.

`PowerSyncDatabase.watch()` is single-subscription end to end — `powersync/lib/src/database/powersync_database.dart:576` delegates to `sqlite_async/lib/src/sqlite_connection.dart:210`, which returns `Stream.fromFuture(...).asyncExpand(...)` over `onChange(...).asyncMap(...)`; every repository `.map()` wrapper preserves that. Cancelling does not reset it. So caching in a field fixed the per-rebuild re-query and simultaneously converted a recycled child into a hard crash.

`app/CLAUDE.md:44` already documents the rule and its caveat — "Safe only when the StreamBuilder is the screen's OUTER wrapper." `today_screen` satisfies the first half of the rule and violates the caveat. `profile_screen.dart:188-190` (`_QuickStats`) has the identical shape inside its own `ListView` and is a latent second instance; it survives only because Profile is a pushed overlay that is not mounted at boot.

**Why it is intermittent, and why "after minimizing a workout".** Whether a section is recycled depends on content height versus viewport height. The resume hero mounting or unmounting changes Home's content height, changing which child sits outside the cache window. Landscape (there is no orientation lock), system font/display scale ≳1.2, a short device, or more PR/volume rows all move the same boundary. On the Linux run the dying section was below the fold, so nothing gray was visible — which is why this looked like "sometimes".

---

## 1. `reListenable` — the primitive

New helper (`app/lib/data/re_listenable.dart`): a re-listenable, latest-replaying view over a single-subscription source that can be recreated on demand.

```dart
Stream<T> reListenable<T>(Stream<T> Function() create) {
  T? last;
  return Stream.multi((controller) {
    if (last != null) controller.add(last as T);
    final sub = create().listen(
      (v) { last = v; controller.add(v); },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });
}
```

- `Stream.multi` invokes its callback **per listener**, so a second or later `listen()` opens a fresh upstream query instead of throwing. Sequential re-listens after a cancel are the case that matters here; concurrent listeners also work.
- The captured `last` replays the most recent value to a new listener immediately, so a recycled section repaints with data instead of flashing its loading state. `last` lives as long as the returned stream object, which is exactly the lifetime of the cached field.
- `controller.onCancel = sub.cancel` tears the upstream query down when a listener leaves, so a recycled child does not leak a SQL watch.
- Cost: a recycled child re-runs its query on return. That is the pre-v0.12.13 cost, paid only on recycle rather than on every rebuild.

`T?` as the sentinel is sound for every current consumer (all return non-nullable `List`s, `int`s or records). If a future watch stream has a nullable element type, use a one-element list or a `bool hasLast` flag instead; noted so the next reader does not have to rediscover it.

## 2. Apply it in the repositories

Wrap the returned stream at each `watchX()` definition, so **every** consumer is safe by construction and no screen can reintroduce the crash by holding a stream the wrong way. Cover the watch methods in `stats_repository.dart`, `bodyweight_repository.dart`, `muscle_target_repository.dart`, `exercise_repository.dart`, `session_repository.dart`, `day_template_repository.dart`, and `progress_repository.dart`.

`db.statusStream` is untouched — PowerSync already backs it with a broadcast controller and it is used with `initialData`.

## 3. Stream-caching leftovers

Seven sites still create a fresh single-subscription stream on every `build()`. With §2 these can no longer crash, so this is purely to stop re-issuing queries on every rebuild — the documented rule, applied consistently:

| Site | Note |
|---|---|
| `history_screen.dart:57` | `build` also does `context.watch<UnitService>()`, so a unit toggle re-queries |
| `exercise_library_tab.dart:55` | repo is a cached field, the stream is not |
| `progress_screen.dart:73` | catalog stream |
| `progress_screen.dart:101` | parameterised by selected exercise → memoize keyed on `exId`, not a plain field |
| `bodyweight_view.dart:53` | |
| `split_tab.dart:30,33` | `StatelessWidget` → needs converting to `StatefulWidget` |
| `targets_tab.dart:25,28` | `StatelessWidget` → same |

## 4. The Progress crash reachable from Home

Confirmed by reading current code, not inferred. `app_shell.dart:112-113` sets `_progressTarget = exId` and switches to the Progress tab when a Recent-PR row on Home is tapped; `app_shell.dart:180-182` builds `ProgressScreen(key: ValueKey(_progressTarget), initialTarget: _progressTarget)`. The changed key **remounts** the screen, so its root `StreamBuilder` (`progress_screen.dart:72-73`) starts over and its first build always has `snap.data == null` (the first `db.watch` emission is asynchronous) → `catalog = []`. With `_target` non-null and not the bodyweight id, both early returns at `:86` and `:90` are skipped and `:95-98` runs:

```dart
final ex = catalog.firstWhere((e) => e.id == exId, orElse: () => catalog.first);
```

`catalog.first` on an empty list throws `Bad state: No element` — deterministically, on frame one, every time a PR row is tapped. The bodyweight tile is unaffected because `:86` short-circuits it.

**Fix:** distinguish "the stream has not emitted yet" from "the exercise is genuinely gone". While the catalog is empty, render the existing loading/skeleton path; when the catalog is non-empty but the id is absent, fall back to the empty state rather than to an index. No `orElse` may assume a non-empty list.

## 5. Unhandled errors on the two manual subscriptions

`today_screen.dart:140` and `:147` subscribe to `watchRecentSessions` and `watchDays` with `.listen()` and **no `onError`**. A row-mapper `TypeError` (a NULL `day_template_items.exercise_id`, a NULL `day_template_id`) therefore becomes an uncaught async error that kills the subscription permanently: `_rotationLoaded` stays false and Home renders `SizedBox(height: 290)` (`:264`) forever, with an empty week strip. This is a *different* symptom from the gray box — a large blank area — and is worth fixing in the same pass.

**Fix:** add `onError` to both subscriptions: log, keep the last good data, and leave the section rendering whatever it last had rather than an unrecoverable placeholder.

## 6. Error surfacing

The app currently has **no** error plumbing: no `FlutterError.onError`, no `ErrorWidget.builder`, no `runZonedGuarded`, no `PlatformDispatcher.instance.onError` anywhere in `app/lib`. Every uncaught build exception in release renders Flutter's default gray `ErrorWidget` and its text goes only to logcat. That is why this bug took three releases and a desktop repro to find.

Add, in `main()`:

- **`ErrorWidget.builder`** → a compact error card. It must be **deliberately dependency-free**: an `ErrorWidget` can be inflated outside `MaterialApp`, so it may not have `Theme`, `Directionality`, `MediaQuery`, or localizations above it. Use an explicit `Directionality`, hardcoded colours, and no `context.tokens` / `AppLocalizations` / `Scaffold`. It shows the exception type and message (first few lines, wrapped, never overflowing) and copies the full details to the clipboard on tap. It must also be resilient to being laid out inside a tightly constrained sliver child.
- **`FlutterError.onError`** → forward to `FlutterError.presentError` (preserving current logging) and retain the last error's full details so the card's copy action has the stack trace.

Deliberately out of scope (YAGNI): an in-app error log screen. The copyable card is enough to turn a gray box into a bug report.

## 7. `_ResumeHero` null-safety

`active_session_controller.dart:315-318` is `assert(_draft != null); return _draft!;`. Asserts are stripped in release, leaving a bare `!`, and `_ResumeHero` (`today_screen.dart`) rebuilds it once per second for the whole life of an active workout. It is unreachable today only because `finish()` nulls the draft and `SessionManager` clears before notifying with no `await` in between — a single future `await` inserted between those statements turns it into a per-second release crash. Make the read null-safe so the margin is not one statement's ordering.

---

## 8. Testing

CI renders no pixels and no test in the suite currently renders `TodayScreen` at all, which is why a crash reproducible by resizing a window shipped three times.

- **`reListenable` unit tests:** a second `listen()` after a cancel succeeds; the last value replays to a late listener; errors forward to each listener; `onDone` closes; the upstream subscription is cancelled when the last listener leaves (assert via a factory that counts creations and cancellations).
- **Recycle regression test:** mount a `ListView` in a short viewport over a repo-shaped single-subscription stream, scroll a `StreamBuilder` child out past the 250px cache window and back, and assert `tester.takeException()` is null. This fails against today's code and is the minimal reproduction of the shipped bug.
- **Real-PowerSync `TodayScreen` render:** following `test/data/offline_create_integration_test.dart`'s precedent (real `PowerSyncDatabase` on a temp path), render Home in a ~400px viewport and scroll it end to end. Caveat stated honestly: `today_screen` builds its repositories from the global `db` singleton (`sync/db.dart`), so this needs `openDatabase()` pointed at a temp path or an injection seam. If that seam turns out to be a riskier refactor than the bug being fixed, stop at the recycle test and say so in the implementation notes rather than dropping it silently.
- **Progress crash test:** render `ProgressScreen` with a non-null `initialTarget` against a catalog stream that has not yet emitted; assert no exception and a loading/empty state. This fails today.
- **Error-surface test:** a widget whose `build` throws, mounted with no `MaterialApp` ancestor, renders the card without a secondary exception.

## 9. CI gate and a documentation correction

`app/CLAUDE.md` states "CI runs analyze + tests". It does not: `.github/workflows/` contains only `android-release.yml` and the server image build, neither of which runs `flutter analyze` or `flutter test`. Analyze and tests are local-only gates today.

- Add a workflow running `make -C app analyze` and `make -C app test` on push and pull request, with the same fvm-pinned Flutter version as the release job.
- Correct the claim in `app/CLAUDE.md`.
- Add the caveat that a `late final` cached stream is only safe if it is also re-listenable, so the next reader does not repeat the v0.12.13 fix's mistake.

## 10. Out of scope

Recorded so they are not silently forgotten: the `split_card` `_currentPage` clamp on shrinking day lists (cosmetic, already guarded); `stats_repository.dart:82`'s `(row['weight'] as num)` on a NULL `weight_kg` (blanks the Recent-PRs section via an error snapshot, does not gray-box — same class as the v0.12.10 incident and worth a `tryParse` pass, but not this increment's subject); the `_TabFade` controller shape in `app_shell.dart:236-240`; the absorb tombstone-on-zero-ops corner. Re-enabling Impeller is unrelated housekeeping.

## 11. Release

Branch off main, TDD per section, adversarial review before merge, `--no-ff` merge whose subject carries `(v0.12.16)`, then tag. Bump `app/pubspec.yaml` to `0.12.16+28` in its own `chore(app): bump version to 0.12.16` commit before tagging — the release workflow hard-fails if the pubspec version does not match the tag.

**Device verification before tagging** (nothing here is provable in CI): Home survives finishing and minimizing a workout; Home survives landscape and a system font scale of 1.3; tapping a Recent-PR row opens Progress without a gray screen; a deliberately broken build shows the error card rather than gray.
