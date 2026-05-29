package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalidRefreshToken = errors.New("auth: invalid or expired refresh token")
	ErrRefreshReused       = errors.New("auth: refresh token reuse detected")
)

// RefreshStore manages opaque refresh tokens: it stores only their SHA-256
// hashes, rotates them on every use, and revokes the whole token family when a
// consumed token is presented again (reuse detection).
type RefreshStore struct {
	pool *pgxpool.Pool
	ttl  time.Duration
}

func NewRefreshStore(pool *pgxpool.Pool, ttl time.Duration) *RefreshStore {
	return &RefreshStore{pool: pool, ttl: ttl}
}

// newToken returns a random opaque token (base64url) and its SHA-256 hash.
func newToken() (plain string, hash []byte, err error) {
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		return "", nil, err
	}
	plain = base64.RawURLEncoding.EncodeToString(raw)
	sum := sha256.Sum256([]byte(plain))
	return plain, sum[:], nil
}

func hashToken(plain string) []byte {
	sum := sha256.Sum256([]byte(plain))
	return sum[:]
}

// Issue creates a brand-new token in a new family for the user.
func (s *RefreshStore) Issue(ctx context.Context, userID string) (string, error) {
	plain, hash, err := newToken()
	if err != nil {
		return "", err
	}
	_, err = s.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
		 VALUES ($1::uuid, gen_random_uuid(), $2, $3)`,
		userID, hash, time.Now().Add(s.ttl))
	if err != nil {
		return "", fmt.Errorf("issue refresh token: %w", err)
	}
	return plain, nil
}

// Rotate atomically consumes the presented token and issues a successor in the
// same family. The consume is a single conditional UPDATE ... RETURNING run
// inside a transaction, so two concurrent rotations of the same token cannot
// both succeed: Postgres takes a row lock, the loser re-evaluates the
// `used_at IS NULL` predicate after the winner commits, matches zero rows, and
// falls into the reuse path. If the presented token exists but was already used
// or revoked, the whole family is revoked and ErrRefreshReused is returned.
func (s *RefreshStore) Rotate(ctx context.Context, presented string) (string, string, error) {
	hash := hashToken(presented)

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Atomic conditional consume: matches at most once, only if the token is live.
	var userID, familyID string
	err = tx.QueryRow(ctx,
		`UPDATE refresh_tokens SET used_at = NOW()
		 WHERE token_hash = $1 AND used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW()
		 RETURNING user_id::text, family_id::text`, hash,
	).Scan(&userID, &familyID)
	if err == nil {
		newPlain, newHash, nerr := newToken()
		if nerr != nil {
			return "", "", nerr
		}
		if _, ierr := tx.Exec(ctx,
			`INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
			 VALUES ($1::uuid, $2::uuid, $3, $4)`,
			userID, familyID, newHash, time.Now().Add(s.ttl)); ierr != nil {
			return "", "", ierr
		}
		if cerr := tx.Commit(ctx); cerr != nil {
			return "", "", cerr
		}
		return userID, newPlain, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", "", err
	}

	// The token is not live. Classify: genuine reuse (used/revoked) -> revoke the
	// whole family; merely expired or entirely unknown -> invalid, no family action.
	var familyID2 string
	var usedAt, revokedAt *time.Time
	derr := tx.QueryRow(ctx,
		`SELECT family_id::text, used_at, revoked_at FROM refresh_tokens WHERE token_hash = $1`, hash,
	).Scan(&familyID2, &usedAt, &revokedAt)
	if errors.Is(derr, pgx.ErrNoRows) {
		return "", "", ErrInvalidRefreshToken
	}
	if derr != nil {
		return "", "", derr
	}
	if usedAt != nil || revokedAt != nil {
		if _, rerr := tx.Exec(ctx,
			`UPDATE refresh_tokens SET revoked_at = NOW()
			 WHERE family_id = $1::uuid AND revoked_at IS NULL`, familyID2); rerr != nil {
			return "", "", rerr
		}
		if cerr := tx.Commit(ctx); cerr != nil {
			return "", "", cerr
		}
		return "", "", ErrRefreshReused
	}
	return "", "", ErrInvalidRefreshToken // exists but expired
}

// RevokeFamily revokes the entire family of the presented token (logout).
// It is idempotent: an unknown token is a no-op.
func (s *RefreshStore) RevokeFamily(ctx context.Context, presented string) error {
	hash := hashToken(presented)
	var familyID string
	err := s.pool.QueryRow(ctx,
		`SELECT family_id::text FROM refresh_tokens WHERE token_hash = $1`, hash,
	).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = NOW()
		 WHERE family_id = $1::uuid AND revoked_at IS NULL`, familyID)
	return err
}
