package api

import (
	"crypto/rand"
	"crypto/rsa"
)

func rsaKeyForTest() (*rsa.PrivateKey, error) {
	return rsa.GenerateKey(rand.Reader, 2048)
}
