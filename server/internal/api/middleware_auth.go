package api

import (
	"context"
	"net/http"
	"strings"

	"workout-tracker/server/internal/auth"
)

type ctxKey int

const userIDKey ctxKey = iota

// RequireAuth verifies the Bearer access token and stores the user id (the token
// subject) in the request context. It rejects with 401 on any failure.
func RequireAuth(v *auth.Verifier, audience string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			token, ok := strings.CutPrefix(header, "Bearer ")
			if !ok || token == "" {
				writeJSONError(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			claims, err := v.Verify(token, audience)
			if err != nil {
				writeJSONError(w, http.StatusUnauthorized, "invalid token")
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, claims.Subject)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserIDFromContext returns the authenticated user id set by RequireAuth.
func UserIDFromContext(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(userIDKey).(string)
	return id, ok
}
