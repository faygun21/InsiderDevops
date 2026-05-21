// Package middleware contains net/http middleware. The request logger emits
// one structured JSON line per request (Day 1) and, since Day 4, also records
// each request into the Prometheus instruments declared in package metrics.
package middleware

import (
	"encoding/json"
	"net/http"
	"os"
	"time"

	"github.com/faygun21/insiderdevops/metrics"
)

// statusRecorder wraps http.ResponseWriter to capture the status code, which
// the standard ResponseWriter does not expose once the response is written.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// requestLog is the JSON shape emitted for every request.
type requestLog struct {
	Level     string  `json:"level"`
	Time      string  `json:"time"`
	Method    string  `json:"method"`
	Path      string  `json:"path"`
	Status    int     `json:"status"`
	LatencyMs float64 `json:"latency_ms"`
}

// Logger emits exactly one structured JSON log line per request to stdout,
// recording method, path, status code and latency.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Default to 200: net/http sends 200 on the first Write when the
		// handler never calls WriteHeader explicitly.
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rec, r)

		latency := time.Since(start)

		// Record the request for Prometheus. /metrics is served outside this
		// middleware (see main.go), so it never reaches here — the explicit
		// skip is belt-and-suspenders against future re-wiring and keeps the
		// scrape endpoint from inflating its own series.
		if r.URL.Path != "/metrics" {
			metrics.Observe(r.Method, r.URL.Path, rec.status, latency)
		}

		line, err := json.Marshal(requestLog{
			Level:     "info",
			Time:      start.UTC().Format(time.RFC3339Nano),
			Method:    r.Method,
			Path:      r.URL.Path,
			Status:    rec.status,
			LatencyMs: float64(latency.Microseconds()) / 1000.0,
		})
		if err != nil {
			return
		}
		// One os.Stdout.Write per request keeps log lines from interleaving
		// when many requests are served concurrently.
		_, _ = os.Stdout.Write(append(line, '\n'))
	})
}
