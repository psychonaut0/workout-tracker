package auth

import (
	"path/filepath"
	"testing"
)

func TestGenerateLoadAndThumbprint_RoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "key.pem")
	if err := GenerateAndWritePEM(path, 2048); err != nil { // 2048 keeps the test fast
		t.Fatalf("GenerateAndWritePEM: %v", err)
	}

	priv, err := LoadPrivateKeyPEM(path)
	if err != nil {
		t.Fatalf("LoadPrivateKeyPEM: %v", err)
	}

	kid1 := ThumbprintKID(&priv.PublicKey)
	if kid1 == "" {
		t.Fatal("empty kid")
	}

	priv2, err := LoadPrivateKeyPEM(path)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if kid2 := ThumbprintKID(&priv2.PublicKey); kid2 != kid1 {
		t.Errorf("kid not deterministic: %q != %q", kid1, kid2)
	}
}

func TestLoadPrivateKeyPEM_RejectsMissingFile(t *testing.T) {
	if _, err := LoadPrivateKeyPEM(filepath.Join(t.TempDir(), "nope.pem")); err == nil {
		t.Fatal("expected error for missing key file, got nil")
	}
}
