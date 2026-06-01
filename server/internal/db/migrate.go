package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "github.com/jackc/pgx/v5/stdlib" // registers the "pgx" database/sql driver
	"github.com/pressly/goose/v3"

	"workout-tracker/server/db/migrations"
)

// Migrate applies all pending goose migrations embedded in the binary against
// databaseURL. It is idempotent — goose only runs migrations newer than the
// recorded version — so it is safe to call on every startup. This is what makes
// a fresh deploy (or DR-restored CT) self-provision its schema, the powersync
// publication, and the powersync_role, with no external migrate step.
func Migrate(ctx context.Context, databaseURL string) error {
	sqlDB, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return fmt.Errorf("migrate: open: %w", err)
	}
	defer sqlDB.Close()

	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return fmt.Errorf("migrate: dialect: %w", err)
	}
	// The embed roots the FS at the migrations directory, so the dir is ".".
	if err := goose.UpContext(ctx, sqlDB, "."); err != nil {
		return fmt.Errorf("migrate: up: %w", err)
	}
	return nil
}
