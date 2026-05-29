package api

import (
	"encoding/json"
	"net/http"
)

// writeJSONError writes a structured error body: {"error":{"message":"..."}}.
func writeJSONError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]string{"message": message},
	})
}
