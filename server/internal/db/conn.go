// Package db owns the Postgres connection pool used by handlers.
package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool aliases pgxpool.Pool so callers can depend on this package without
// importing pgxpool directly.
type Pool = pgxpool.Pool

// NewPool opens a pgxpool connection, verifies it with Ping, and returns the
// ready-to-use pool. The caller owns the pool and must Close it on shutdown.
func NewPool(ctx context.Context, databaseURL string) (*Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return pool, nil
}
