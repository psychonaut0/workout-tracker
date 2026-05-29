package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"workout-tracker/server/internal/auth"
)

func newAuthPair(t *testing.T) (*auth.Signer, *auth.Verifier) {
	t.Helper()
	priv, err := rsaKeyForTest()
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	kid := auth.ThumbprintKID(&priv.PublicKey)
	return auth.NewSigner(priv, kid, "workout-tracker"), auth.NewVerifier(&priv.PublicKey, "workout-tracker")
}

func TestRequireAuth_AllowsValidToken(t *testing.T) {
	signer, verifier := newAuthPair(t)
	tok, _ := signer.Sign("user-42", "workout-tracker-api", time.Minute)

	var seenUser string
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			seenUser, _ = UserIDFromContext(r.Context())
			w.WriteHeader(http.StatusOK)
		}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if seenUser != "user-42" {
		t.Errorf("user: got %q", seenUser)
	}
}

func TestRequireAuth_RejectsMissingHeader(t *testing.T) {
	_, verifier := newAuthPair(t)
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/protected", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestRequireAuth_RejectsBadToken(t *testing.T) {
	_, verifier := newAuthPair(t)
	h := RequireAuth(verifier, "workout-tracker-api")(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer not.a.jwt")
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}
