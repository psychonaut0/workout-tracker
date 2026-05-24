// Package api defines the HTTP router and handlers for the server.
package api

import "github.com/go-chi/chi/v5"

func NewRouter() *chi.Mux {
	r := chi.NewRouter()
	r.Get("/healthz", Healthz)
	return r
}
