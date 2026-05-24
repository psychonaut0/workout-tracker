package config

import "testing"

func TestLoad_AppliesDefaultsWhenOnlyDatabaseURLIsSet(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("LOG_LEVEL", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":8080" {
		t.Errorf("HTTPAddr default: got %q, want %q", cfg.HTTPAddr, ":8080")
	}
	if cfg.LogLevel != "info" {
		t.Errorf("LogLevel default: got %q, want %q", cfg.LogLevel, "info")
	}
	if cfg.DatabaseURL != "postgres://x:y@localhost/db" {
		t.Errorf("DatabaseURL: got %q", cfg.DatabaseURL)
	}
}

func TestLoad_RespectsExplicitValues(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost/db")
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("LOG_LEVEL", "debug")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Errorf("HTTPAddr: got %q", cfg.HTTPAddr)
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel: got %q", cfg.LogLevel)
	}
}

func TestLoad_FailsWhenDatabaseURLMissing(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected error when DATABASE_URL is empty, got nil")
	}
}
