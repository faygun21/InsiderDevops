// Package middleware contains net/http middleware. For Day 1 this is just a
// structured request logger; Day 4 builds richer JSON logging on top of it.
package middleware

import (
	"encoding/json"
	"net/http"
	"os"
	"time"
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

		line, err := json.Marshal(requestLog{
			Level:     "info",
			Time:      start.UTC().Format(time.RFC3339Nano),
			Method:    r.Method,
			Path:      r.URL.Path,
			Status:    rec.status,
			LatencyMs: float64(time.Since(start).Microseconds()) / 1000.0,
		})
		if err != nil {
			return
		}
		// One os.Stdout.Write per request keeps log lines from interleaving
		// when many requests are served concurrently.
		_, _ = os.Stdout.Write(append(line, '\n'))
	})
}
