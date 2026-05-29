// Command genkey writes a new RSA private key PEM for JWT signing.
// Run once: make -C server gen-jwt-key
package main

import (
	"flag"
	"log"

	"workout-tracker/server/internal/auth"
)

func main() {
	out := flag.String("out", ".secrets/jwt_private_key.pem", "output path for the PEM private key")
	bits := flag.Int("bits", 3072, "RSA key size in bits")
	flag.Parse()

	if err := auth.GenerateAndWritePEM(*out, *bits); err != nil {
		log.Fatalf("genkey: %v", err)
	}
	log.Printf("genkey: wrote %d-bit RSA private key to %s", *bits, *out)
}
