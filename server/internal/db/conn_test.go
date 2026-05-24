package db

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestNewPool_ConnectsAndPingsSuccessfully(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping integration test (run via `make -C server test`)")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := NewPool(ctx, dbURL)
	if err != nil {
		t.Fatalf("NewPool: %v", err)
	}
	defer pool.Close()

	var got int
	if err := pool.QueryRow(ctx, "SELECT 1").Scan(&got); err != nil {
		t.Fatalf("SELECT 1: %v", err)
	}
	if got != 1 {
		t.Errorf("SELECT 1: got %d, want 1", got)
	}
}

func TestNewPool_FailsForUnreachableHost(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if _, err := NewPool(ctx, "postgres://nobody@127.0.0.1:1/none?sslmode=disable&connect_timeout=1"); err == nil {
		t.Fatal("expected error for unreachable host, got nil")
	}
}
