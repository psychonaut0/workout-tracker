package api

import (
	"context"
	"net/http"
	"time"
)

// Readyz is a readiness probe: 200 if the DB ping succeeds within 2s,
// 503 otherwise. Use this for load-balancer or orchestrator readiness checks.
func Readyz(pinger Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		w.Header().Set("Content-Type", "application/json")
		if err := pinger.Ping(ctx); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"unavailable"}`))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}
}
