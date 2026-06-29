// Command createuser inserts a user with a hashed password, or resets the
// password if the email already exists (idempotent — also serves as the
// password-reset tool for the self-hosted backend).
// Run: make -C server create-user EMAIL=me@example.com PASSWORD=secret
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"workout-tracker/server/internal/auth"
)

func main() {
	email := flag.String("email", "", "user email")
	password := flag.String("password", "", "user password")
	flag.Parse()

	if *email == "" || *password == "" {
		log.Fatal("createuser: -email and -password are required")
	}
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("createuser: DATABASE_URL is required")
	}

	hash, err := auth.HashPassword(*password)
	if err != nil {
		log.Fatalf("createuser: hash: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("createuser: db: %v", err)
	}
	defer pool.Close()

	// Upsert: create the user, or reset the password if the email already
	// exists. (email is UNIQUE.) Lets this double as the password-reset tool.
	if _, err := pool.Exec(ctx,
		`INSERT INTO users (email, password_hash) VALUES ($1, $2)
		 ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash`,
		*email, hash); err != nil {
		log.Fatalf("createuser: upsert: %v", err)
	}
	log.Printf("createuser: set password for %s", *email)
}
