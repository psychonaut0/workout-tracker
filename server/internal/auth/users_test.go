package auth

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping DB integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestUserStore_FindByEmail(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	email := "find-" + randomSuffix() + "@example.com"

	_, err := pool.Exec(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)`, email, "hash")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE email=$1`, email) })

	store := NewUserStore(pool)
	u, err := store.FindByEmail(ctx, email)
	if err != nil {
		t.Fatalf("FindByEmail: %v", err)
	}
	if u.PasswordHash != "hash" || u.ID == "" {
		t.Errorf("unexpected user: %+v", u)
	}
}

func TestUserStore_Create(t *testing.T) {
	pool := testPool(t)
	s := NewUserStore(pool)
	ctx := context.Background()
	email := "reg-" + randomSuffix() + "@example.com"

	id, err := s.Create(ctx, email, "hash-abc")
	if err != nil {
		t.Fatal(err)
	}
	if id == "" {
		t.Fatal("empty id")
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM users WHERE id=$1::uuid`, id) })

	// duplicate email -> ErrEmailTaken
	if _, err := s.Create(ctx, email, "hash-def"); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("want ErrEmailTaken, got %v", err)
	}
}

func TestUserStore_FindByEmail_NotFound(t *testing.T) {
	pool := testPool(t)
	store := NewUserStore(pool)
	if _, err := store.FindByEmail(context.Background(), "nobody@example.com"); err != ErrUserNotFound {
		t.Errorf("got %v, want ErrUserNotFound", err)
	}
}
