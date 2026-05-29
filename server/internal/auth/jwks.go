package auth

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
)

// JWK is a single JSON Web Key (RSA public key) as served at the JWKS endpoint.
type JWK struct {
	Kty string `json:"kty"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// JWKS is a JSON Web Key Set.
type JWKS struct {
	Keys []JWK `json:"keys"`
}

// PublicJWK builds the JWK for one static RSA public key. n and e are
// Base64urlUInt values (RFC 7518): minimal big-endian bytes, base64url no padding.
func PublicJWK(pub *rsa.PublicKey, kid string) JWK {
	return JWK{
		Kty: "RSA",
		Use: "sig",
		Alg: "RS256",
		Kid: kid,
		N:   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
	}
}

// JWKSHandler serves the immutable JWKS. The body is marshaled once at startup;
// the endpoint must be unauthenticated so PowerSync can poll it.
func JWKSHandler(pub *rsa.PublicKey, kid string) http.HandlerFunc {
	body, _ := json.Marshal(JWKS{Keys: []JWK{PublicJWK(pub, kid)}})
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		_, _ = w.Write(body)
	}
}
