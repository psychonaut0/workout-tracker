package config

import (
	"log/slog"
	"testing"
	"time"
)

func setRequired(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "/run/secrets/jwt.pem")
}

func TestLoad_AppliesDefaults(t *testing.T) {
	setRequired(t)
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("LOG_LEVEL", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":8080" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.JWTIssuer != "workout-tracker" {
		t.Errorf("JWTIssuer: got %q", cfg.JWTIssuer)
	}
	if cfg.APIAudience != "workout-tracker-api" {
		t.Errorf("APIAudience: got %q", cfg.APIAudience)
	}
	if cfg.PowerSyncAudience != "workout-tracker-powersync" {
		t.Errorf("PowerSyncAudience: got %q", cfg.PowerSyncAudience)
	}
	if cfg.AccessTokenTTL != 15*time.Minute {
		t.Errorf("AccessTokenTTL: got %v", cfg.AccessTokenTTL)
	}
	if cfg.RefreshTokenTTL != 720*time.Hour {
		t.Errorf("RefreshTokenTTL: got %v", cfg.RefreshTokenTTL)
	}
	if cfg.PowerSyncTokenTTL != 5*time.Minute {
		t.Errorf("PowerSyncTokenTTL: got %v", cfg.PowerSyncTokenTTL)
	}
}

func TestLoad_RespectsExplicitValues(t *testing.T) {
	setRequired(t)
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("ACCESS_TOKEN_TTL", "30m")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.SlogLevel() != slog.LevelDebug {
		t.Errorf("SlogLevel: got %v, want debug", cfg.SlogLevel())
	}
	if cfg.AccessTokenTTL != 30*time.Minute {
		t.Errorf("AccessTokenTTL: got %v", cfg.AccessTokenTTL)
	}
}

func TestLoad_FailsWhenDatabaseURLMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "/run/secrets/jwt.pem")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when DATABASE_URL is empty")
	}
}

func TestLoad_FailsWhenKeyPathMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("JWT_PRIVATE_KEY_PATH", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when JWT_PRIVATE_KEY_PATH is empty")
	}
}

func TestLoad_FailsOnBadDuration(t *testing.T) {
	setRequired(t)
	t.Setenv("ACCESS_TOKEN_TTL", "not-a-duration")
	if _, err := Load(); err == nil {
		t.Fatal("expected error for malformed ACCESS_TOKEN_TTL")
	}
}
