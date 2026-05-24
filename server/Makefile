# All targets are meant to be invoked from the repo root via `make -C server <target>`.
# This Makefile sources infra/.env to derive DATABASE_URL when one is not provided.

-include ../infra/.env

DATABASE_URL ?= postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:5432/$(POSTGRES_DB)?sslmode=disable

.PHONY: help build test fmt vet

help:
	@echo "Targets (run from repo root as 'make -C server <target>'):"
	@echo "  build  Compile the server binary into server/bin/server"
	@echo "  test   Run all Go tests"
	@echo "  fmt    go fmt ./..."
	@echo "  vet    go vet ./..."

build:
	go build -o bin/server ./cmd/server

test:
	TEST_DATABASE_URL=$(DATABASE_URL) go test ./...

fmt:
	go fmt ./...

vet:
	go vet ./...
