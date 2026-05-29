package auth

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
)

// GenerateAndWritePEM creates a new RSA private key and writes it as a PKCS#8
// PEM file with 0600 permissions. Intended to be run once, offline.
func GenerateAndWritePEM(path string, bits int) error {
	priv, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return fmt.Errorf("generate key: %w", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return fmt.Errorf("marshal key: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}
	block := &pem.Block{Type: "PRIVATE KEY", Bytes: der}
	return os.WriteFile(path, pem.EncodeToMemory(block), 0o600)
}

// LoadPrivateKeyPEM loads a PKCS#8 RSA private key from a PEM file.
func LoadPrivateKeyPEM(path string) (*rsa.PrivateKey, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read key file: %w", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, errors.New("auth: no PEM block found in key file")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse key: %w", err)
	}
	priv, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("auth: key is not an RSA private key")
	}
	return priv, nil
}

// ThumbprintKID returns the RFC 7638 SHA-256 JWK thumbprint of an RSA public
// key, used as a stable, deterministic key id. The canonical members for an RSA
// key are exactly e, kty, n in lexicographic order with no whitespace.
func ThumbprintKID(pub *rsa.PublicKey) string {
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	canonical := fmt.Sprintf(`{"e":%q,"kty":"RSA","n":%q}`, e, n)
	sum := sha256.Sum256([]byte(canonical))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
