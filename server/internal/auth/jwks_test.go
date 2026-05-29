package auth

import (
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func testKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	priv, err := rsaTestKey()
	if err != nil {
		t.Fatalf("generate test key: %v", err)
	}
	return priv
}

func TestPublicJWK_HasExpectedFields(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)

	jwk := PublicJWK(&priv.PublicKey, kid)
	if jwk.Kty != "RSA" || jwk.Alg != "RS256" {
		t.Errorf("kty/alg: got %q/%q", jwk.Kty, jwk.Alg)
	}
	if jwk.Kid != kid {
		t.Errorf("kid: got %q, want %q", jwk.Kid, kid)
	}
	if jwk.E != "AQAB" {
		t.Errorf("e: got %q, want AQAB", jwk.E)
	}
	if jwk.N == "" {
		t.Error("n is empty")
	}
}

func TestJWKSHandler_ServesOneKey(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil)
	JWKSHandler(&priv.PublicKey, kid).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("content-type: got %q", ct)
	}
	var doc JWKS
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(doc.Keys) != 1 || doc.Keys[0].Kid != kid {
		t.Errorf("expected one key with kid %q, got %+v", kid, doc.Keys)
	}
}
