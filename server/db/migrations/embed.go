// Package migrations embeds the goose SQL migration files so the server can
// apply them on startup (no external goose CLI or migration files needed in the
// runtime image).
package migrations

import "embed"

// FS holds the embedded *.sql migration files (this directory).
//
//go:embed *.sql
var FS embed.FS
