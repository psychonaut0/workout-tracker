package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"workout-tracker/server/internal/auth"
)

// --- fakes ---

type fakeUsers struct {
	user      *auth.User
	err       error
	createID  string
	createErr error
}

func (f *fakeUsers) FindByEmail(_ context.Context, _ string) (*auth.User, error) {
	return f.user, f.err
}

func (f *fakeUsers) Create(_ context.Context, _, _ string) (string, error) {
	return f.createID, f.createErr
}

type fakeRefresh struct {
	issue       string
	rotateUser  string
	rotateTok   string
	rotateErr   error
	revokeCalls int
}

func (f *fakeRefresh) Issue(context.Context, string) (string, error) { return f.issue, nil }
func (f *fakeRefresh) Rotate(context.Context, string) (string, string, error) {
	return f.rotateUser, f.rotateTok, f.rotateErr
}
func (f *fakeRefresh) RevokeFamily(context.Context, string) error { f.revokeCalls++; return nil }

func newHandler(t *testing.T, users UserFinder, refresh RefreshManager) *AuthHandler {
	t.Helper()
	priv, _ := rsaKeyForTest()
	kid := auth.ThumbprintKID(&priv.PublicKey)
	signer := auth.NewSigner(priv, kid, "workout-tracker")
	return NewAuthHandler(AuthConfig{
		Users:             users,
		Refresh:           refresh,
		Signer:            signer,
		APIAudience:       "workout-tracker-api",
		PowerSyncAudience: "workout-tracker-powersync",
		PowerSyncURL:      "http://powersync:8080",
		AccessTTL:         15 * time.Minute,
		PowerSyncTTL:      5 * time.Minute,
	})
}

func TestLogin_Succeeds(t *testing.T) {
	hash, _ := auth.HashPassword("devpassword")
	h := newHandler(t, &fakeUsers{user: &auth.User{ID: "u1", PasswordHash: hash}}, &fakeRefresh{issue: "refresh-xyz"})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"me@example.com","password":"devpassword"}`))
	h.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["access_token"] == "" || body["refresh_token"] != "refresh-xyz" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestLogin_RejectsWrongPassword(t *testing.T) {
	hash, _ := auth.HashPassword("devpassword")
	h := newHandler(t, &fakeUsers{user: &auth.User{ID: "u1", PasswordHash: hash}}, &fakeRefresh{})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"me@example.com","password":"WRONG"}`))
	h.Login(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestLogin_RejectsUnknownUser(t *testing.T) {
	h := newHandler(t, &fakeUsers{err: auth.ErrUserNotFound}, &fakeRefresh{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/login",
		strings.NewReader(`{"email":"ghost@example.com","password":"x"}`))
	h.Login(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestRegister(t *testing.T) {
	// success
	h := newHandler(t, &fakeUsers{createID: "new-user-1"}, &fakeRefresh{issue: "refresh-xyz"})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/register",
		strings.NewReader(`{"email":"a@b.com","password":"password123"}`))
	h.Register(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["access_token"] == "" || body["refresh_token"] != "refresh-xyz" {
		t.Errorf("unexpected body: %v", body)
	}

	// short password -> 400
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/auth/register",
		strings.NewReader(`{"email":"a@b.com","password":"short"}`))
	h.Register(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("short password: got %d, want 400", rec.Code)
	}

	// missing fields -> 400
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/auth/register",
		strings.NewReader(`{"email":"a@b.com"}`))
	h.Register(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("missing password: got %d, want 400", rec.Code)
	}

	// duplicate email -> 409
	hDup := newHandler(t, &fakeUsers{createErr: auth.ErrEmailTaken}, &fakeRefresh{})
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/auth/register",
		strings.NewReader(`{"email":"a@b.com","password":"password123"}`))
	hDup.Register(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("duplicate email: got %d, want 409", rec.Code)
	}
}

func TestRefresh_RotatesToken(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{rotateUser: "u1", rotateTok: "refresh-new"})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh",
		strings.NewReader(`{"refresh_token":"refresh-old"}`))
	h.Refresh(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["refresh_token"] != "refresh-new" || body["access_token"] == "" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestRefresh_RejectsReuse(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{rotateErr: auth.ErrRefreshReused})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh",
		strings.NewReader(`{"refresh_token":"reused"}`))
	h.Refresh(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestLogout_RevokesFamily(t *testing.T) {
	fr := &fakeRefresh{}
	h := newHandler(t, &fakeUsers{}, fr)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/logout",
		strings.NewReader(`{"refresh_token":"r"}`))
	h.Logout(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204", rec.Code)
	}
	if fr.revokeCalls != 1 {
		t.Errorf("revoke calls: got %d, want 1", fr.revokeCalls)
	}
}

func TestPowerSyncToken_MintsScopedToken(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/powersync-token", nil)
	// Simulate the auth middleware having authenticated the user.
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, "user-99"))
	h.PowerSyncToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["endpoint"] != "http://powersync:8080" || body["token"] == "" {
		t.Errorf("unexpected body: %v", body)
	}
}

func TestPowerSyncToken_RequiresAuthenticatedUser(t *testing.T) {
	h := newHandler(t, &fakeUsers{}, &fakeRefresh{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/auth/powersync-token", nil)
	h.PowerSyncToken(rec, req) // no user in context
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}
