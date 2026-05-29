package auth

import (
	"crypto/rand"
	"encoding/hex"
)

func randomSuffix() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
