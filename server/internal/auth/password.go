// Package auth provides password hashing, RSA key handling, JWT signing and
// verification, and the refresh-token store for the workout-tracker server.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// OWASP Argon2id baseline (19 MiB, t=2, p=1). Parameters are embedded in every
// hash, so they can be raised later without breaking stored hashes.
const (
	argonMemoryKiB uint32 = 19456 // 19 MiB
	argonTime      uint32 = 2
	argonThreads   uint8  = 1
	saltLen        int    = 16
	keyLen         uint32 = 32
)

var (
	ErrInvalidHash         = errors.New("password: invalid PHC hash format")
	ErrIncompatibleVersion = errors.New("password: incompatible argon2 version")
)

// HashPassword derives an Argon2id hash and returns a self-describing PHC string:
// $argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>.
func HashPassword(plain string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("password: generate salt: %w", err)
	}
	key := argon2.IDKey([]byte(plain), salt, argonTime, argonMemoryKiB, argonThreads, keyLen)
	return fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemoryKiB, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

// VerifyPassword re-derives using the parameters parsed from the stored PHC
// string and compares in constant time. Returns (true,nil) on match,
// (false,nil) on a valid hash that does not match, (false,err) on a malformed hash.
func VerifyPassword(plain, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, ErrInvalidHash
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, ErrInvalidHash
	}
	if version != argon2.Version {
		return false, ErrIncompatibleVersion
	}

	var memory, time uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
		return false, ErrInvalidHash
	}
	if time == 0 || threads == 0 {
		return false, ErrInvalidHash // argon2.IDKey panics on zero time/threads
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, ErrInvalidHash
	}
	storedKey, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, ErrInvalidHash
	}

	computed := argon2.IDKey([]byte(plain), salt, time, memory, threads, uint32(len(storedKey)))
	return subtle.ConstantTimeCompare(storedKey, computed) == 1, nil
}
