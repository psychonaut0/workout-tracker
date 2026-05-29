# All targets are meant to be invoked from the repo root via `make -C server <target>`.
# This Makefile sources infra/.env to derive DATABASE_URL when one is not provided.

-include ../infra/.env

DATABASE_URL ?= postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:5433/$(POSTGRES_DB)?sslmode=disable

.PHONY: help build test fmt vet run migrate-up migrate-down migrate-status migrate-reset

help:
	@echo "Targets (run from repo root as 'make -C server <target>'):"
	@echo "  build           Compile the server binary into server/bin/server"
	@echo "  run             Run the server against the local dev DB"
	@echo "  test            Run all Go tests"
	@echo "  fmt             go fmt ./..."
	@echo "  vet             go vet ./..."
	@echo "  migrate-up      Apply all pending migrations"
	@echo "  migrate-down    Roll back the most recent migration"
	@echo "  migrate-status  Show migration status"
	@echo "  migrate-reset   Roll back ALL migrations (destructive)"

build:
	go build -o bin/server ./cmd/server

test:
	TEST_DATABASE_URL=$(DATABASE_URL) go test ./...

fmt:
	go fmt ./...

vet:
	go vet ./...

run:
	DATABASE_URL=$(DATABASE_URL) go run ./cmd/server

MIGRATIONS_DIR := db/migrations

migrate-up:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" up

migrate-down:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" down

migrate-status:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" status

migrate-reset:
	go tool goose -dir $(MIGRATIONS_DIR) postgres "$(DATABASE_URL)" reset
