// Package api defines the HTTP router and handlers for the server.
package api

import (
	"context"

	"github.com/go-chi/chi/v5"
)

// Pinger is the surface area /readyz needs from the DB pool. Defined here so
// the api package does not import the db package.
type Pinger interface {
	Ping(ctx context.Context) error
}

func NewRouter(pinger Pinger) *chi.Mux {
	r := chi.NewRouter()
	r.Get("/healthz", Healthz)
	r.Get("/readyz", Readyz(pinger))
	return r
}
