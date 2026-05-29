package auth

import (
	"crypto/rsa"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims is the JWT claim set for both the API access token and the PowerSync token.
type Claims struct {
	jwt.RegisteredClaims
}

// Signer mints RS256 JWTs with a stable kid header.
type Signer struct {
	priv   *rsa.PrivateKey
	kid    string
	issuer string
}

func NewSigner(priv *rsa.PrivateKey, kid, issuer string) *Signer {
	return &Signer{priv: priv, kid: kid, issuer: issuer}
}

// Sign mints an RS256 JWT for subject with the given audience and lifetime.
func (s *Signer) Sign(subject, audience string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			Audience:  jwt.ClaimStrings{audience},
			Issuer:    s.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = s.kid
	return token.SignedString(s.priv)
}

// Verifier validates RS256 JWTs against the public key.
type Verifier struct {
	pub    *rsa.PublicKey
	issuer string
}

func NewVerifier(pub *rsa.PublicKey, issuer string) *Verifier {
	return &Verifier{pub: pub, issuer: issuer}
}

// Verify parses and validates a token, requiring RS256, a present exp, the
// expected audience, and the configured issuer.
func (v *Verifier) Verify(tokenStr, audience string) (*Claims, error) {
	claims := &Claims{}
	_, err := jwt.ParseWithClaims(
		tokenStr,
		claims,
		func(t *jwt.Token) (any, error) { return v.pub, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}),
		jwt.WithExpirationRequired(),
		jwt.WithAudience(audience),
		jwt.WithIssuer(v.issuer),
	)
	if err != nil {
		return nil, err
	}
	return claims, nil
}
