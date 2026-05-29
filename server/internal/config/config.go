// Package config loads server configuration from environment variables.
package config

import (
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr    string
	DatabaseURL string
	LogLevel    string

	JWTPrivateKeyPath string
	JWTIssuer         string
	APIAudience       string
	PowerSyncAudience string
	PowerSyncURL      string

	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	PowerSyncTokenTTL time.Duration
}

func Load() (Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	keyPath := os.Getenv("JWT_PRIVATE_KEY_PATH")
	if keyPath == "" {
		return Config{}, fmt.Errorf("JWT_PRIVATE_KEY_PATH is required")
	}

	accessTTL, err := getDuration("ACCESS_TOKEN_TTL", 15*time.Minute)
	if err != nil {
		return Config{}, err
	}
	refreshTTL, err := getDuration("REFRESH_TOKEN_TTL", 720*time.Hour)
	if err != nil {
		return Config{}, err
	}
	psTTL, err := getDuration("POWERSYNC_TOKEN_TTL", 5*time.Minute)
	if err != nil {
		return Config{}, err
	}

	return Config{
		HTTPAddr:          getString("HTTP_ADDR", ":8080"),
		DatabaseURL:       dbURL,
		LogLevel:          getString("LOG_LEVEL", "info"),
		JWTPrivateKeyPath: keyPath,
		JWTIssuer:         getString("JWT_ISSUER", "workout-tracker"),
		APIAudience:       getString("API_AUDIENCE", "workout-tracker-api"),
		PowerSyncAudience: getString("POWERSYNC_AUDIENCE", "workout-tracker-powersync"),
		PowerSyncURL:      getString("POWERSYNC_URL", "http://localhost:8080"),
		AccessTokenTTL:    accessTTL,
		RefreshTokenTTL:   refreshTTL,
		PowerSyncTokenTTL: psTTL,
	}, nil
}

// SlogLevel maps the LOG_LEVEL string to a slog.Level (default info).
func (c Config) SlogLevel() slog.Level {
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func getString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getDuration(key string, def time.Duration) (time.Duration, error) {
	v := os.Getenv(key)
	if v == "" {
		return def, nil
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return d, nil
}
