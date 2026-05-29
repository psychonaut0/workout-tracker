package auth

import (
	"strings"
	"testing"
)

func TestHashPassword_ProducesVerifiablePHCString(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Errorf("unexpected PHC prefix: %q", hash)
	}

	ok, err := VerifyPassword("correct horse battery staple", hash)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if !ok {
		t.Error("expected password to verify, got false")
	}
}

func TestHashPassword_RejectsWrongPassword(t *testing.T) {
	hash, err := HashPassword("right-password")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	ok, err := VerifyPassword("wrong-password", hash)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if ok {
		t.Error("expected wrong password to fail, got true")
	}
}

func TestHashPassword_SaltsAreUnique(t *testing.T) {
	a, _ := HashPassword("same")
	b, _ := HashPassword("same")
	if a == b {
		t.Error("expected unique salts to produce different hashes")
	}
}

func TestVerifyPassword_RejectsMalformedHash(t *testing.T) {
	if _, err := VerifyPassword("x", "not-a-phc-string"); err != ErrInvalidHash {
		t.Errorf("got %v, want ErrInvalidHash", err)
	}
}
