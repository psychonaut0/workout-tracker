package auth

import (
	"testing"
	"time"
)

func TestSignAndVerify_RoundTrips(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, err := signer.Sign("user-123", "workout-tracker-api", 5*time.Minute)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	claims, err := verifier.Verify(tok, "workout-tracker-api")
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.Subject != "user-123" {
		t.Errorf("sub: got %q", claims.Subject)
	}
}

func TestVerify_RejectsWrongAudience(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-powersync", time.Minute)
	if _, err := verifier.Verify(tok, "workout-tracker-api"); err == nil {
		t.Fatal("expected audience mismatch to fail")
	}
}

func TestVerify_RejectsExpiredToken(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")
	verifier := NewVerifier(&priv.PublicKey, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-api", -1*time.Minute)
	if _, err := verifier.Verify(tok, "workout-tracker-api"); err == nil {
		t.Fatal("expected expired token to fail")
	}
}

func TestSign_SetsKidHeader(t *testing.T) {
	priv := testKey(t)
	kid := ThumbprintKID(&priv.PublicKey)
	signer := NewSigner(priv, kid, "workout-tracker")

	tok, _ := signer.Sign("u", "workout-tracker-api", time.Minute)
	parsed, _, err := newParserHeader(tok)
	if err != nil {
		t.Fatalf("parse header: %v", err)
	}
	if parsed != kid {
		t.Errorf("kid header: got %q, want %q", parsed, kid)
	}
}
