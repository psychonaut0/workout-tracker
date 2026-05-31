# Profile & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The final screen — Profile & Settings: editable name + avatar + quick stats; **Units** (kg/lb), **Appearance** (theme dark/light + 4 accents), **Sync & Backend** (the **configurable server URL** — the user's standing request — + connection status), **Account** (signed-in identity + sign out). Settings are client-local; theme/accent/unit apply live; changing the server URL re-auths against the new backend.

**Architecture:** A `SettingsService` (ChangeNotifier, `shared_preferences`-backed) holds `mode`/`accent`/`profileName`/`serverUrl`; `UnitService` gains the same persistence for `unit`. `main()` loads settings at startup, sets the now-mutable top-level `apiBaseUrl` from `serverUrl` BEFORE `openDatabase`/`connectSync`, provides both services, and the `MaterialApp` theme is `buildTheme(settings.brightness, settings.accentColor)` watched (live theme/accent). **Server-URL change = re-auth:** the local PowerSync DB + session are tied to one backend, so applying a new URL confirms → persists → `disconnectAndClear()` + `auth.logout()` → back to Login (which now hits the new `apiBaseUrl`). Profile opens as a root overlay from the Today avatar (replaces the `PlaceholderTab('Profile')`).

**Tech Stack:** Flutter 3.44 (`make -C app`), `shared_preferences` (NEW), `provider`. Reuse `context.tokens`/`WorkoutType`/`WIcons`/`AppRadius`, `UnitService` (`fmtWt`/`uLabel`), `WCard`, `plan_form.dart` (`ChipSelect`/`TextInput`/`PrimaryBtn`), `SessionRepository`/`BodyweightRepository` (quick stats). Design: `docs/design_handoff_workout_tracker/design/app/screen-profile.jsx`. `buildTheme(Brightness, Color)` + `accents` already exist in `app/lib/theme/app_theme.dart`/`tokens.dart`.

**Settled decisions (sensible defaults — adopted):**
- Settings **client-local** via `shared_preferences` (no synced settings table; `serverUrl` is the backend address itself and must bootstrap independently).
- Keep **`UnitService`** as the unit provider (widely watched) and ADD persistence to it; new **`SettingsService`** owns mode/accent/profileName/serverUrl. Two providers.
- `apiBaseUrl` becomes a **mutable top-level var** (default `http://localhost:8080`), set from settings at startup; `AuthStore`/connector read it live (string-interpolated per request).
- **Server-URL change re-auths**: confirm dialog ("Switching server signs you out and clears local data") → persist + set `apiBaseUrl` + `disconnectAndClear()` + `auth.logout()` → Login. (Can't hot-swap a backend; the local DB holds the old server's synced rows.)
- **Signed-in identity** = the email the user logged in with — persist it in `AuthStore` at login (secure storage) + expose `auth.email`. `profileName` is separate (SettingsService, default `'Athlete'`), drives the avatar initials.
- Theme/accent/unit apply **live** (watched); no restart.

---

## File Structure
- `app/pubspec.yaml` (MOD) — add `shared_preferences`
- `app/lib/settings/settings_service.dart` (NEW) — `SettingsService` (mode/accent/profileName/serverUrl)
- `app/lib/units/unit_service.dart` (MOD) — load/save `unit` via shared_preferences
- `app/lib/auth/auth_store.dart` (MOD) — `apiBaseUrl` mutable (drop `const`); persist + expose `email`
- `app/lib/main.dart` (MOD) — load settings → set apiBaseUrl → bootstrap; provide SettingsService; watch theme
- `app/lib/ui/profile_screen.dart` (NEW) — the screen
- `app/lib/shell/app_shell.dart` (MOD) — open real `ProfileScreen` overlay from the avatar; pass `onLogout`

---

### Task 1: Settings infra (SettingsService + UnitService persistence + mutable apiBaseUrl)

**Files:** Modify `app/pubspec.yaml`, `app/lib/units/unit_service.dart`, `app/lib/auth/auth_store.dart`; Create `app/lib/settings/settings_service.dart`; Test `app/test/settings/settings_test.dart`

- [ ] **Step 1:** add `shared_preferences: ^2.3.2` to `dependencies`; `make -C app get`.
- [ ] **Step 2: `apiBaseUrl` mutable.** In `auth_store.dart` change `const String apiBaseUrl = 'http://localhost:8080';` → `String apiBaseUrl = 'http://localhost:8080';` (drop `const`; it stays a top-level var read live by `AuthStore` + connector). Also: persist the login email — add `String? _email`, set it in `login(email,…)`, write `_kEmail` to secure storage in `_persistTokens`/login and read it in `load()`, clear it in `logout()`; expose `String? get email => _email`.
- [ ] **Step 3: `UnitService` persistence.** Add `Future<void> load()` (read `'unit'` from `SharedPreferences`, default kg) and persist in `setUnit` (`await prefs.setString('unit', u.name)`). Keep the `Unit`/`fromKg`/`toKg`/`fmtWt`/`uLabel` API unchanged.
- [ ] **Step 4: `SettingsService extends ChangeNotifier`** (`settings_service.dart`): fields `ThemeMode-ish mode` (store `'dark'|'light'`), `Color accent` (default `accents[0]`), `String profileName` (default `'Athlete'`), `String serverUrl` (default `'http://localhost:8080'`). `Future<void> load()` reads all from `SharedPreferences`; setters (`setMode`/`setAccent`/`setProfileName`/`setServerUrl`) persist + `notifyListeners()`. Getters `Brightness get brightness => mode=='light'?Brightness.light:Brightness.dark` and `Color get accentColor => accent`. **Persist accent as `accent.toARGB32()` (int) and reconstruct via `Color.fromARGB((v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF)`** — do NOT use `Color(int)` / `.value` (deprecated in Flutter 3.44 → `analyze` warning). On load, if the stored int doesn't match one of the 4 `accents`, fall back to `accents[0]`.
- [ ] **Step 5: Test** `settings_test.dart` (use `SharedPreferences.setMockInitialValues({})`): SettingsService defaults (dark, accents[0], 'Athlete', localhost); setMode('light') → `brightness==Brightness.light` + persisted; UnitService.load defaults kg, setUnit(lb) persists + reload reads lb.
- [ ] **Step 6:** `make -C app analyze` clean; `make -C app test` green (existing 91 + new). **Commit** — "feat(app): SettingsService + unit persistence + configurable apiBaseUrl"

### Task 2: main.dart bootstrap rewiring

**Files:** Modify `app/lib/main.dart`

- [ ] **Step 1:** In `main()` BEFORE `openDatabase()`: create + `await` `SettingsService().load()` and `UnitService().load()`; set `apiBaseUrl = settings.serverUrl;` (so `openDatabase`/`connectSync` use the configured backend). Pass both services into `App` (so the same instances are provided).
- [ ] **Step 2:** `MultiProvider` providers = `ChangeNotifierProvider.value(value: unitService)` + `ChangeNotifierProvider.value(value: settingsService)`. **DELETE the existing `ChangeNotifierProvider<UnitService>(create: (_) => UnitService())` line** — replace it with the `.value` provider for the loaded instance (else a second, unloaded UnitService is created in-tree). **The theme watcher must live INSIDE the MultiProvider subtree, NOT in `_AppState.build()`** (which is the provider's parent → `context.watch<SettingsService>()` there throws `ProviderNotFoundException`). Wrap the `MaterialApp` in a `Builder`:
```dart
MultiProvider(
  providers: [ ChangeNotifierProvider.value(value: unitService), ChangeNotifierProvider.value(value: settingsService) ],
  child: Builder(builder: (ctx) {
    final s = ctx.watch<SettingsService>();
    return MaterialApp(theme: buildTheme(s.brightness, s.accentColor), home: _loggedIn ? AppShell(onLogout: _onLogout) : LoginScreen(...));
  }),
)
```
Keep the login gate + `connectSync`/`disconnectAndClear`.
- [ ] **Step 2b:** Keep `apiBaseUrl` in sync with `SettingsService.serverUrl` — set it whenever the server changes (the Profile apply path sets it before `disconnectAndClear`; also re-affirm `apiBaseUrl = s.serverUrl` at startup). (The var is the single source the connector/auth read.)
- [ ] **Step 3:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): bootstrap settings + live theme + configured server URL"

### Task 3: ProfileScreen + AppShell wiring

**Files:** Create `app/lib/ui/profile_screen.dart`; Modify `app/lib/shell/app_shell.dart`. Port `screen-profile.jsx`.

- [ ] **Step 1: `ProfileScreen({required VoidCallback onClose, required Future<void> Function() onLogout})`** — full-bleed (root overlay). Watches `SettingsService` + `UnitService`. Header (back chevron → `onClose`, 'Profile' title). Body (`ListView`, pad `18/16/104`):
  - **Profile header**: 66px accent avatar with initials from `settings.profileName` (split words, ≤2, uppercase, fallback 'A'); tap name → inline `TextInput` editing → `settings.setProfileName` on submit; sub 'Training since … · 4-day split' (static label OK).
  - **Quick stats** (3 cards): Sessions (count via `SessionRepository.watchSessionStats().first`/length or a count query), PRs (sum prCount), Bodyweight (`fmtWt(latest)+uLabel` from `BodyweightRepository.watchSeriesAsc()`; '–' if none). Use FutureBuilder/StreamBuilder; graceful empty.
  - **Units** group: a `Row` ('Weight unit', sub 'Applies everywhere') + `ChipSelect(['kg','lb'])` → `UnitService.setUnit`.
  - **Appearance** group: Theme `ChipSelect(['Dark','Light'])` → `settings.setMode`; Accent = 4 swatch buttons (`accents`) → `settings.setAccent` (selected = 2px text-color ring).
  - **Sync & Backend** group: a status `Row` ('Sync server', sub = current `serverUrl`, right = accent dot + 'Connected'); below it a `TextInput` (local controller seeded from `serverUrl`) + an **'Apply / Switch server'** `PrimaryBtn` (enabled when the field differs from `serverUrl` and is non-empty) → see Step 2; footer 'Local-first · …'.
  - **Account** group: 'Signed in' `Row` (sub = `auth.email ?? '—'`); 'Sign out' `Row` (danger) → confirm → `onLogout()`.
  - version footer 'workout-tracker · v1.0.0'.
- [ ] **Step 2: Server-switch (the load-bearing bit).** The 'Apply' button shows a confirm dialog ("Switch server? This signs you out and clears local data on this device."). On confirm: `await settings.setServerUrl(newUrl); apiBaseUrl = newUrl;` then **`await onLogout()` FIRST, THEN `onClose()`** (order matters: `onLogout` flips `_loggedIn=false` in `_AppState` → swaps AppShell for LoginScreen while AppShell/_AppState are still in the tree; doing `onClose()` first pops the overlay and runs `disconnectAndClear()` on a torn-down branch. After `onLogout`, the `onClose()` pop is a harmless no-op.) `onLogout` = `disconnectAndClear()` + `auth.logout()` → Login authenticates against the new `apiBaseUrl`. Do NOT reconnect in place. (Trim the URL; basic validation: non-empty, starts with `http`.)
- [ ] **Step 3: AppShell wiring.** First, **change `AppShell.onLogout` from `VoidCallback` to `Future<void> Function()`** (it's `await`ed in ProfileScreen; `main._onLogout` is already `async`, and `main` already passes it via `AppShell(onLogout: _onLogout)` — only the field type changes; update/remove the stale "stored for future use" doc comment). Then `_openProfile`: replace the `PlaceholderTab('Profile')` push with pushing `ProfileScreen(onClose: () => Navigator.pop(context), onLogout: widget.onLogout)` on the **root navigator** (full-bleed overlay, matching the active-session/summary pattern). **All four IndexedStack tabs (Today/Progress/History/Plan) are now real screens and Profile is no longer a placeholder, so `PlaceholderTab` is fully unused — DELETE the `import '…/placeholder_screen.dart'`** (and the file is now dead; leave it on disk but unimported is fine, or delete it) to keep `analyze` clean (`unused_import`).
- [ ] **Step 4:** `make -C app analyze` clean; `make -C app test` green. **Commit** — "feat(app): Profile & Settings screen (units, theme, accent, server URL, sign out)"

### Task 4: Verify (INLINE)
- [ ] **Step 1:** `make -C app analyze` (0 issues); `make -C app test` (all green); `make -C app build` (Linux bundle links).
- [ ] **Step 2: Headless smoke** — boot the release binary ~25s; confirm no crash/exceptions and that the persisted-settings bootstrap (SettingsService.load + apiBaseUrl set + theme from settings) doesn't break startup/auto-login/sync. (Profile opens from the avatar — a tap — so its render is covered by the build + analyze; the live theme-switch / server-switch flows need a manual tap, noted for the user.)

---

## Done after this
This is the **last screen** — with it, the whole `design_handoff_workout_tracker` app (Today, active session + summary, Progress, Bodyweight, History, Plan editors, Profile/Settings) is built. Remaining odds-and-ends stay deferred: `muscle_targets` editing UI, delete-exercise (FK guard), clear-to-NULL on PATCH (forced-PUT), Android hardware-back for in-tab editors, and any visual polish from your eyeball pass.
