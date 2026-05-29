package auth

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
)

// newParserHeader extracts the kid from a JWT's header segment (test helper).
func newParserHeader(token string) (string, bool, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", false, errors.New("not a JWT")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", false, err
	}
	var h struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(raw, &h); err != nil {
		return "", false, err
	}
	return h.Kid, h.Alg == "RS256", nil
}
