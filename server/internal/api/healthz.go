package api

import "net/http"

// Healthz is a liveness probe: 200 if the process is up. Does not touch any
// dependencies; for readiness use /readyz.
func Healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
