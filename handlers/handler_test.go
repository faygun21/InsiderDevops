package handlers

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestPingHandler issues a GET to /ping and asserts a 200 with a "pong" body
// and a JSON content type.
func TestPingHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/ping", nil)
	rec := httptest.NewRecorder()

	Ping(rec, req)

	res := rec.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status: want %d, got %d", http.StatusOK, res.StatusCode)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), "pong") {
		t.Fatalf("body: want it to contain %q, got %q", "pong", string(body))
	}
	if ct := res.Header.Get("Content-Type"); ct != "application/json" {
		t.Fatalf("content-type: want application/json, got %q", ct)
	}
}

// TestHealthzHandler issues a GET to /healthz and asserts a 200 with a
// "healthy" body.
func TestHealthzHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	Healthz(rec, req)

	res := rec.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status: want %d, got %d", http.StatusOK, res.StatusCode)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), "healthy") {
		t.Fatalf("body: want it to contain %q, got %q", "healthy", string(body))
	}
}

// TestVersionHandler verifies the ldflags-injected SHA is echoed back, by
// passing a known value through the Version closure.
func TestVersionHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	rec := httptest.NewRecorder()

	Version("abc123")(rec, req)

	res := rec.Result()
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		t.Fatalf("status: want %d, got %d", http.StatusOK, res.StatusCode)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), "abc123") {
		t.Fatalf("body: want it to contain %q, got %q", "abc123", string(body))
	}
}
