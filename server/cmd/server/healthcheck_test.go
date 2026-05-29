package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthcheck_OKOn200(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	if err := healthcheck(srv.URL); err != nil {
		t.Fatalf("expected nil for 200, got %v", err)
	}
}

func TestHealthcheck_ErrorsOnNon200(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	if err := healthcheck(srv.URL); err == nil {
		t.Fatal("expected an error for 503, got nil")
	}
}

func TestHealthcheck_ErrorsOnUnreachable(t *testing.T) {
	if err := healthcheck("http://127.0.0.1:1"); err == nil {
		t.Fatal("expected an error for an unreachable host, got nil")
	}
}
