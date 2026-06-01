package db

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestMigrate_IsIdempotentAndCreatesSchema(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Idempotent: running twice must both succeed (second is a no-op).
	if err := Migrate(ctx, dbURL); err != nil {
		t.Fatalf("Migrate (1st): %v", err)
	}
	if err := Migrate(ctx, dbURL); err != nil {
		t.Fatalf("Migrate (2nd, should be no-op): %v", err)
	}

	// Schema is present: the users table exists after migration.
	pool, err := NewPool(ctx, dbURL)
	if err != nil {
		t.Fatalf("NewPool: %v", err)
	}
	defer pool.Close()
	var exists bool
	if err := pool.QueryRow(ctx,
		"SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users')").
		Scan(&exists); err != nil {
		t.Fatalf("check users table: %v", err)
	}
	if !exists {
		t.Fatal("users table missing after Migrate")
	}
}
