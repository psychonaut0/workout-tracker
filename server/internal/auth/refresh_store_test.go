package auth

import (
	"context"
	"testing"
	"time"
)

func TestRefreshStore_RotateAndReuseDetection(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()

	email := "rt-" + randomSuffix() + "@example.com"
	var userID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1,$2) RETURNING id::text`,
		email, "hash").Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE id=$1::uuid`, userID) })

	store := NewRefreshStore(pool, time.Hour)

	first, err := store.Issue(ctx, userID)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	gotUser, second, err := store.Rotate(ctx, first)
	if err != nil {
		t.Fatalf("Rotate: %v", err)
	}
	if gotUser != userID {
		t.Errorf("rotate user: got %q want %q", gotUser, userID)
	}
	if second == first {
		t.Error("rotated token should differ from the original")
	}

	if _, _, err := store.Rotate(ctx, first); err != ErrRefreshReused {
		t.Errorf("reuse: got %v, want ErrRefreshReused", err)
	}
	if _, _, err := store.Rotate(ctx, second); err == nil {
		t.Error("expected second token to be revoked after reuse of first")
	}
}

func TestRefreshStore_RotateUnknownToken(t *testing.T) {
	pool := testPool(t)
	store := NewRefreshStore(pool, time.Hour)
	if _, _, err := store.Rotate(context.Background(), "not-a-real-token"); err != ErrInvalidRefreshToken {
		t.Errorf("got %v, want ErrInvalidRefreshToken", err)
	}
}
