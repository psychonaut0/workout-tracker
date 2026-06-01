# Sync Attach + Registration (Spec B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a standalone install connect a server later without losing data, and let users register accounts — fixing the upload batch-poisoning and seed↔template slug-collision bugs along the way.

**Architecture:** Option X (keep Spec A's synced-table storage). Server: per-op `SAVEPOINT` so one bad op no longer poisons the upload batch; auto-suffix a colliding exercise slug so seeded exercises upload under the client's own id; a new `/auth/register` endpoint. Client: a "Create account" path; a first-sign-in keep-my-data vs use-account's-data prompt; a catalog filter that hides a template when the user owns a same-named exercise. A manual spike validates PowerSync's connect/upload behavior before the client attach UI is built.

**Tech Stack:** Go (chi + pgx + bcrypt, goose), Flutter 3.44 (fvm), PowerSync. Server tests via `go test ./...` (run from repo root: `cd server && go test ./...` — but per project convention invoke as `make` or explicit paths; here use `go test` inside `server/`). App via `make -C app`.

**Spec:** `docs/superpowers/specs/2026-06-01-sync-attach-registration-design.md`. Bug context: memory `project_sync_attach_bugs_for_spec_b`.

**Branch:** `sync-attach-registration` (off `main`).

**Grounding facts (verified — do not re-derive):**
- Upload handler `server/internal/api/sync_upload.go`: one `tx` for the batch — `tx, _ := h.pool.Begin(ctx)` (~:64), `for _, op := range req.Batch { applyOp(...) }` (~:75), `recompute...` passes, `tx.Commit` (~:107). `applyOp(ctx, tx, userID, op, topGroups, prExercises) error` (:127). `isTransient(err)` helper exists. Skipped ops are `slog.Warn`'d.
- `applyExercise` PUT (:249) does `INSERT INTO exercises (... is_template, created_by) VALUES (... false, $15::uuid) ON CONFLICT (id) DO UPDATE ... WHERE created_by=$15`. The global `UNIQUE(slug)` is `exercises_slug_key` — a DIFFERENT constraint from the `ON CONFLICT (id)`, so a slug dup still errors.
- Auth: `auth.UserStore{pool}` has `FindByEmail` only (`internal/auth/users.go`); `auth.HashPassword(plain)` + `VerifyPassword` exist (`internal/auth/password.go`); `User{ID, PasswordHash}`. `AuthHandler.issueTokens(w, r, userID)` writes the standard `tokenResponse`. `AuthHandler.Login` validates `email`+`password`, looks up, verifies, `issueTokens`.
- Routes in `internal/api/router.go`: `r.Post("/auth/login", d.Auth.Login)` etc. at :39-41 (public group). `AuthConfig` wires `Users`, `Refresh`, `Signer`, etc.
- Existing Go tests: `internal/api/auth_handlers_test.go`, `internal/api/sync_upload_test.go` (follow their existing harness for a test pool / building `crudOp` batches).
- Client: `AuthStore` (`app/lib/auth/auth_store.dart`) has `login(email,password)` POSTing `$apiBaseUrl/auth/login`; `LoginScreen({auth, onLoggedIn})`; Profile's signed-out path calls `setServerUrl`+`setSyncEnabled(true)`+`connectSync`. `ExerciseRepository.watchCatalog` = `SELECT * FROM exercises ORDER BY name`.

---

## Task 1: Server — per-op SAVEPOINT (fix batch-poisoning)

**Files:**
- Modify: `server/internal/api/sync_upload.go` (the batch loop ~:75-86)
- Test: `server/internal/api/sync_upload_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/api/sync_upload_test.go`, following the file's existing harness (test pool, how it builds a `uploadRequest`/`crudOp` batch and calls the handler). The test uploads a batch where the FIRST op violates a constraint (e.g. an exercise with a slug that already exists in the DB, or any op that errors non-transiently) and a SECOND op is valid; assert the valid op PERSISTED (currently it would be lost to the 25P02 cascade + failed commit):
```go
func TestUpload_OneBadOpDoesNotDropTheBatch(t *testing.T) {
    // ... set up test pool + handler per existing harness; seed a template
    // exercise with slug "dup-slug" so a user PUT of the same slug collides ...
    batch := []crudOp{
        // op A: exercise PUT with slug "dup-slug" -> violates exercises_slug_key
        {Op: "PUT", Type: "exercises", ID: newUUID(), Data: map[string]any{"name": "Dup", "slug": "dup-slug", "muscle_group": "back"}},
        // op B: a valid bodyweight log
        {Op: "PUT", Type: "bodyweight_logs", ID: newUUID(), Data: map[string]any{"date": "2026-06-01", "weight_kg": "80.0"}},
    }
    // ... call Upload with this batch as the authenticated user ...
    // Assert: response is 2xx, and op B's bodyweight row EXISTS in the DB.
    // (Before the fix: the slug violation poisons the tx, commit fails 503, nothing persists.)
}
```
(Match the exact request/response types + auth setup used by the other tests in this file. If Task 3's slug-suffix is not yet in place, op A genuinely violates the unique constraint, which is what this test needs.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd server && go test ./internal/api/ -run TestUpload_OneBadOpDoesNotDropTheBatch -v`
Expected: FAIL — op B's row missing (batch was rolled back).

- [ ] **Step 3: Wrap each op in a SAVEPOINT**

In `server/internal/api/sync_upload.go`, replace the batch loop body (~:75-86) so each op runs inside a savepoint and a failure rolls back only that op:
```go
	for _, op := range req.Batch {
		if _, err := tx.Exec(ctx, "SAVEPOINT op_sp"); err != nil {
			writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
			return
		}
		err := applyOp(ctx, tx, userID, op, topGroups, prExercises)
		if err == nil {
			if _, rerr := tx.Exec(ctx, "RELEASE SAVEPOINT op_sp"); rerr != nil {
				writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
				return
			}
			applied++
			continue
		}
		// Roll the failed op back to the savepoint so the outer tx stays usable.
		if _, rerr := tx.Exec(ctx, "ROLLBACK TO SAVEPOINT op_sp"); rerr != nil {
			writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
			return
		}
		if isTransient(err) {
			writeJSONError(w, http.StatusServiceUnavailable, "transient db error")
			return
		}
		slog.Warn("upload: skipping op", "table", op.tableName(), "op", op.Op, "id", op.ID, "err", err)
	}
```
(The recompute passes + `tx.Commit` after the loop are unchanged. Skipped ops may have added to `topGroups`/`prExercises`; recompute on those groups is a harmless idempotent re-read.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd server && go test ./internal/api/ -run TestUpload_OneBadOpDoesNotDropTheBatch -v`
Expected: PASS — op B persisted; response 2xx.

- [ ] **Step 5: Full server tests + commit**

Run: `cd server && go test ./...` → all pass.
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add server/internal/api/sync_upload.go server/internal/api/sync_upload_test.go
git commit -m "fix(server): per-op savepoint so one bad upload op no longer drops the batch"
```

---

## Task 2: Server — auto-suffix colliding exercise slug

**Files:**
- Modify: `server/internal/api/sync_upload.go` (`applyExercise` PUT, ~:249-289)
- Test: `server/internal/api/sync_upload_test.go`

- [ ] **Step 1: Write the failing test**

Add to `sync_upload_test.go`: seed a TEMPLATE exercise with slug `back-squat`; upload a user exercise PUT with the same slug `back-squat` and a fresh id; assert it INSERTS under the client's id with a SUFFIXED slug (e.g. `back-squat-<first8ofid>`), is owned by the user (`created_by`, `is_template=false`), and the template row is untouched:
```go
func TestApplyExercise_SuffixesCollidingSlug(t *testing.T) {
    // seed template: INSERT INTO exercises (... slug 'back-squat', is_template true ...)
    id := newUUID()
    batch := []crudOp{{Op: "PUT", Type: "exercises", ID: id,
        Data: map[string]any{"name": "Back Squat", "slug": "back-squat", "muscle_group": "quads"}}}
    // ... call Upload as the user ...
    // Assert: a row with id==id exists, created_by==user, is_template==false,
    // and its slug == "back-squat-" + id[:8]; the template row still has slug "back-squat".
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd server && go test ./internal/api/ -run TestApplyExercise_SuffixesCollidingSlug -v`
Expected: FAIL — the insert errors on `exercises_slug_key` (op skipped, no user row).

- [ ] **Step 3: Pre-check + suffix the slug**

In `applyExercise` PUT (`sync_upload.go`), after `slug, _ := str(op.Data, "slug")` and before the INSERT, add:
```go
		if slug != "" {
			var taken bool
			if err := tx.QueryRow(ctx,
				`SELECT EXISTS(SELECT 1 FROM exercises WHERE slug = $1 AND id <> $2::uuid)`,
				slug, op.ID).Scan(&taken); err != nil {
				return err
			}
			if taken && len(op.ID) >= 8 {
				slug = slug + "-" + op.ID[:8]
			}
		}
```
The existing INSERT then uses the (possibly suffixed) `slug` unchanged. (This avoids the collision proactively rather than catching the constraint error — cleaner, and it composes with Task 1's savepoint.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd server && go test ./internal/api/ -run TestApplyExercise_SuffixesCollidingSlug -v`
Expected: PASS.

- [ ] **Step 5: Full server tests + commit**

Run: `cd server && go test ./...` → all pass.
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add server/internal/api/sync_upload.go server/internal/api/sync_upload_test.go
git commit -m "feat(server): auto-suffix a colliding exercise slug on upload"
```

---

## Task 3: Spike — validate PowerSync attach on the live backend (INLINE)

> Controller runs this; not shipped code. It validates the assumed model (offline queue flushes on connect; additive merge; server-skip→local reconcile) AND verifies Tasks 1+2 unwedge the test phone's stuck upload queue. If reality diverges, REVISE Tasks 5-6 before building them.

- [ ] **Step 1: Rebuild + redeploy the dev server** with Tasks 1-2:
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
docker compose -f infra/compose.yml up -d --build server
docker logs workout-tracker-server-1 --since 1m 2>&1 | tail -5
```
Expected: server container rebuilds and is healthy.

- [ ] **Step 2: Observe a real attach.** On the test phone (already configured with the Tailscale server URL + sync), trigger a sync (reopen the app / toggle sync). Watch the server logs:
```bash
docker logs workout-tracker-server-1 --since 2m 2>&1 | grep -iE 'exercises|upload|skip|savepoint|25P02|23505' | tail -20
```
Expected: the previously-wedged exercise uploads now SUCCEED (seeded ones with suffixed slugs); no 25P02 cascade. Then check Postgres:
```bash
docker exec -e PGPASSWORD=change-me-locally workout-tracker-postgres-1 psql -U postgres -d workout_tracker -At -c "SELECT count(*) FROM exercises WHERE NOT is_template;"
```
Expected: the user's seeded exercises (≈24 + any custom) are now present (vs 1 before).

- [ ] **Step 3: Record findings** in this plan file under a "Spike findings" note: did the queue flush on connect? did rows round-trip? If the model held, proceed. If not (e.g. local rows got wiped instead of uploaded), document the actual behavior and adjust Tasks 5-6's reconciliation approach before implementing them. No commit (or commit only the plan-file findings note).

---

## Task 4: Server — `/auth/register` endpoint

**Files:**
- Modify: `server/internal/auth/users.go` (add `Create`)
- Modify: `server/internal/api/auth_handlers.go` (add `Register`)
- Modify: `server/internal/api/router.go` (mount route)
- Test: `server/internal/auth/users_test.go`, `server/internal/api/auth_handlers_test.go`

- [ ] **Step 1: Write the failing test for `UserStore.Create`**

Add to `server/internal/auth/users_test.go` (follow its test-pool setup):
```go
func TestUserStore_Create(t *testing.T) {
    // ... test pool ...
    s := NewUserStore(pool)
    id, err := s.Create(ctx, "new@example.com", "hash-abc")
    require.NoError(t, err)
    require.NotEmpty(t, id)
    // duplicate email -> ErrEmailTaken
    _, err = s.Create(ctx, "new@example.com", "hash-def")
    require.ErrorIs(t, err, ErrEmailTaken)
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd server && go test ./internal/auth/ -run TestUserStore_Create -v`
Expected: FAIL — `Create`/`ErrEmailTaken` undefined.

- [ ] **Step 3: Implement `Create`**

In `server/internal/auth/users.go`:
```go
// ErrEmailTaken is returned when creating a user whose email already exists.
var ErrEmailTaken = errors.New("auth: email already registered")

// Create inserts a new user and returns its id. Returns ErrEmailTaken on a
// duplicate email.
func (s *UserStore) Create(ctx context.Context, email, passwordHash string) (string, error) {
	var id string
	err := s.pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id::text`,
		email, passwordHash,
	).Scan(&id)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return "", ErrEmailTaken
		}
		return "", err
	}
	return id, nil
}
```
Add the import `"github.com/jackc/pgx/v5/pgconn"`.

- [ ] **Step 4: Write the failing test for the `Register` handler**

Add to `server/internal/api/auth_handlers_test.go` (follow its harness for building an `AuthHandler` + recorder):
```go
func TestRegister_CreatesUserAndIssuesTokens(t *testing.T) {
    // ... build handler with a real/fake UserStore + signer + refresh ...
    body := `{"email":"a@b.com","password":"password123"}`
    // POST /auth/register -> 200 with access_token + refresh_token
    // duplicate email -> 409; short password -> 400; missing fields -> 400
}
```

- [ ] **Step 5: Run it to verify it fails**

Run: `cd server && go test ./internal/api/ -run TestRegister -v`
Expected: FAIL — `Register` undefined.

- [ ] **Step 6: Implement `Register` + mount the route**

In `server/internal/api/auth_handlers.go` (mirror `Login`'s shape):
```go
type registerRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// Register creates a new user and issues tokens (same response as Login).
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" || req.Password == "" {
		writeJSONError(w, http.StatusBadRequest, "email and password are required")
		return
	}
	if len(req.Password) < 8 {
		writeJSONError(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not hash password")
		return
	}
	id, err := h.cfg.Users.Create(r.Context(), req.Email, hash)
	if err != nil {
		if errors.Is(err, auth.ErrEmailTaken) {
			writeJSONError(w, http.StatusConflict, "email already registered")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "could not create user")
		return
	}
	h.issueTokens(w, r, id)
}
```
Add imports `"errors"` and the `auth` package if not present. The `Users` field in `AuthConfig` is currently typed for `FindByEmail`; widen its interface (or concrete type) to also include `Create(ctx, email, hash) (string, error)` — match how `Users` is declared in `AuthConfig` and ensure `*auth.UserStore` satisfies it.

In `server/internal/api/router.go`, add under the public group (after `/auth/login`, :39):
```go
		r.Post("/auth/register", d.Auth.Register)
```

- [ ] **Step 7: Run tests to verify they pass + commit**

Run: `cd server && go test ./...` → all pass.
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add server/internal/auth/users.go server/internal/auth/users_test.go server/internal/api/auth_handlers.go server/internal/api/auth_handlers_test.go server/internal/api/router.go
git commit -m "feat(server): POST /auth/register to create users"
```

---

## Task 5: Client — registration UI

**Files:**
- Modify: `app/lib/auth/auth_store.dart` (add `register`)
- Modify: `app/lib/ui/login_screen.dart` (a "Create account" toggle/path)
- Test: `app/test/auth/auth_store_register_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/auth/auth_store_register_test.dart` (mirror any existing auth_store test; inject a mock `http.Client`):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout_tracker/auth/auth_store.dart';

void main() {
  test('register posts to /auth/register and stores tokens on success', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/register');
      return http.Response('{"access_token":"a","refresh_token":"r"}', 200);
    });
    final store = AuthStore(client: client /*, storage: an in-memory FlutterSecureStorage mock */);
    await store.register('new@example.com', 'password123');
    expect(store.accessToken, 'a');
    expect(store.email, 'new@example.com');
  });
}
```
(Use the same secure-storage test seam the existing `AuthStore` tests use — match the constructor params already supported: `AuthStore({storage, client})`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `register` undefined.

- [ ] **Step 3: Implement `AuthStore.register`**

In `app/lib/auth/auth_store.dart`, mirror `login` (it POSTs `$apiBaseUrl/auth/login`, then `_persistTokens` + stores email):
```dart
  /// POST /auth/register. Throws on failure (e.g. 409 email taken). On success
  /// behaves like login (tokens + email persisted).
  Future<void> register(String email, String password) async {
    final res = await _http.post(
      Uri.parse('$apiBaseUrl/auth/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw Exception('register failed (${res.statusCode}): ${res.body}');
    }
    _email = email;
    await _persistTokens(jsonDecode(res.body) as Map<String, dynamic>);
    await _storage.write(key: _kEmail, value: email);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!".

- [ ] **Step 5: Add a "Create account" path to LoginScreen**

In `app/lib/ui/login_screen.dart`, add a mode toggle: a `bool _registering = false` and a text button at the bottom ("Create account" / "Have an account? Sign in") that flips it. When `_registering`, the submit button reads "Create account" and calls `widget.auth.register(email, password)` instead of `login`; both then call `widget.onLoggedIn()` (the existing success path that enables sync + connects). Surface the thrown error message (e.g. "email already registered") in the existing error display. Keep the existing fields/validation; do not change `onLoggedIn` semantics.

- [ ] **Step 6: Verify + commit**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'` and `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: 0 issues; all tests pass.
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/auth/auth_store.dart app/lib/ui/login_screen.dart app/test/auth/auth_store_register_test.dart
git commit -m "feat(app): account registration (register API + Create account on Login)"
```

---

## Task 6: Client — attach reconciliation prompt + catalog de-dup

**Files:**
- Modify: `app/lib/data/exercise_repository.dart` (catalog de-dup filter)
- Modify: `app/lib/ui/profile_screen.dart` (first-sign-in keep/discard prompt)
- Test: `app/test/data/catalog_dedup_test.dart`

- [ ] **Step 1: Write the failing test for the de-dup filter**

Create `app/test/data/catalog_dedup_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/exercise_repository.dart';

Map<String, Object?> _ex(String id, String name, {int tmpl = 0}) =>
    {'id': id, 'name': name, 'is_template': tmpl};

void main() {
  test('dedupeCatalog hides a template when a same-named owned exercise exists', () {
    final rows = [
      _ex('u1', 'Back Squat', tmpl: 0),   // user-owned
      _ex('t1', 'Back Squat', tmpl: 1),   // template duplicate -> hidden
      _ex('t2', 'Bench Press', tmpl: 1),  // template, no owned dup -> kept
    ];
    final kept = dedupeCatalog(rows).map((r) => r['id']).toList();
    expect(kept, ['u1', 't2']);
  });
  test('case-insensitive name match', () {
    final rows = [_ex('u1', 'back squat', tmpl: 0), _ex('t1', 'Back Squat', tmpl: 1)];
    expect(dedupeCatalog(rows).map((r) => r['id']), ['u1']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make -C app test 2>&1 | tail -20`
Expected: FAIL — `dedupeCatalog` undefined.

- [ ] **Step 3: Implement `dedupeCatalog` + apply it in `watchCatalog`**

In `app/lib/data/exercise_repository.dart` add a top-level pure function and use it to filter the watch stream's rows BEFORE mapping to `Exercise`:
```dart
/// Drops a synced template exercise when the user already owns a non-template
/// exercise with the same (case-insensitive) name — so the catalog isn't
/// doubled after sync attach. Owned rows (is_template==0) always win.
List<Map<String, Object?>> dedupeCatalog(List<Map<String, Object?>> rows) {
  final ownedNames = <String>{};
  for (final r in rows) {
    if ((r['is_template'] as int? ?? 0) == 0) {
      ownedNames.add((r['name'] as String).toLowerCase());
    }
  }
  return rows.where((r) {
    final isTemplate = (r['is_template'] as int? ?? 0) != 0;
    return !(isTemplate && ownedNames.contains((r['name'] as String).toLowerCase()));
  }).toList();
}
```
Then in `watchCatalog` (the `SELECT * FROM exercises ORDER BY name` watch), ensure the query selects `is_template` (it's `SELECT *` so it does), and run the ResultSet rows through `dedupeCatalog` before `.map(Exercise.fromRow)`. (Keep the existing mapping; just insert the filter on the row list.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `make -C app test 2>&1 | grep -E 'All tests passed|failed'`
Expected: "All tests passed!".

- [ ] **Step 5: First-sign-in keep / discard prompt**

In `app/lib/ui/profile_screen.dart`, in the sign-in success path (the `onLoggedIn` callback that currently does `setSyncEnabled(true)` + `connectSync`), add reconciliation: AFTER authenticating but consider whether local data exists. Use the spike findings (Task 3) for the exact mechanics; the intended behavior:
- If the local DB already has user data (e.g. `SessionRepository(db).anyUserId()` non-null OR any local sessions/exercises), and the user is signing into an EXISTING account, show a confirm dialog (match this file's existing dialog style):
  - **"Keep my data"** → proceed with `setSyncEnabled(true)` + `connectSync` (the offline queue uploads + merges; this is the default).
  - **"Use the account's data"** → `await disconnectAndClear()` first (wipe local), THEN `setSyncEnabled(true)` + `connectSync` (download remote only).
- If there is no local data, skip the prompt and just connect.

Because Option X is additive-merge, "Keep my data" is the simple/default path; the prompt mainly exists to offer the destructive "use account's data" alternative. Keep the registration path (new account) prompt-free — a new account is empty, so always keep-local.

> NOTE: the precise "does the account already have remote data" detection may need the spike's findings (you can only see remote rows after an initial connect). If detecting remote-emptiness pre-connect is impractical, implement the simpler contract: always offer keep-vs-discard whenever LOCAL data exists at sign-in (not register), and document that. Decide based on Task 3.

- [ ] **Step 6: Verify + commit**

Run: `make -C app analyze 2>&1 | grep -iE 'no issues|error'`, `make -C app test 2>&1 | grep -E 'All tests passed|failed'`, `make -C app build 2>&1 | tail -2`
Expected: 0 issues; all tests pass; Linux bundle links.
```bash
cd /home/psy/Documents/personal/projects/workout-tracker
git add app/lib/data/exercise_repository.dart app/lib/ui/profile_screen.dart app/test/data/catalog_dedup_test.dart
git commit -m "feat(app): sync-attach keep/discard prompt + catalog de-dup after attach"
```

---

## Task 7: Verify (INLINE)

- [ ] **Step 1: Server + app gates**
```bash
cd /home/psy/Documents/personal/projects/workout-tracker/server && go test ./... 2>&1 | tail -5
cd /home/psy/Documents/personal/projects/workout-tracker && make -C app analyze 2>&1 | grep -iE 'no issues|error'
make -C app test 2>&1 | grep -E 'All tests passed|failed'
make -C app build 2>&1 | tail -2
```
Expected: server tests pass; app analyze 0 issues; app tests pass; Linux bundle links.

- [ ] **Step 2: Rebuild + redeploy the server** (so register + the fixes are live):
```bash
docker compose -f infra/compose.yml up -d --build server && docker logs workout-tracker-server-1 --since 1m 2>&1 | tail -3
```

- [ ] **Step 3: Build + install the APK** for on-device verification of register + the keep/discard prompt:
```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk; export ANDROID_HOME="$HOME/Android/Sdk"; export PATH="$ANDROID_HOME/platform-tools:$PATH"
make -C app build-apk 2>&1 | tail -2
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk 2>&1 | tail -1
```
Report; the user verifies registration + attach on-device.

---

## Verification summary

1. Server: `go test ./...` green — incl. the batch-survives-one-bad-op regression test and the slug-suffix test; `/auth/register` works (success/duplicate/invalid).
2. Spike (Task 3) confirmed the live attach unwedges the phone's queue and uploads seeded exercises (suffixed) — or the plan was revised from findings.
3. App: analyze 0 issues; tests pass (register + de-dup); build links.
4. On-device: a new account can be created; signing into an account with local data offers keep-my-data vs use-account's-data; the catalog isn't doubled after attach.

## Deferred / out of scope
Multi-device live conflict resolution beyond first-attach; local-only-tables migration (Option Y); password reset / email verification / OAuth.
