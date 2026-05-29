package auth

import (
	"crypto/rand"
	"crypto/rsa"
)

// rsaTestKey generates a small RSA key for fast tests.
func rsaTestKey() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, 2048)
}
