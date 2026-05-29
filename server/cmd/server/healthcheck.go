package main

import (
	"fmt"
	"net/http"
	"time"
)

// healthcheck probes baseURL + "/healthz" and returns nil only on HTTP 200.
// Used by the `-healthcheck` flag so the distroless container (no shell/curl)
// can health-check itself by re-invoking the binary.
func healthcheck(baseURL string) error {
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(baseURL + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthz returned %d", resp.StatusCode)
	}
	return nil
}
