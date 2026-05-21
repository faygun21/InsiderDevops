// Command insiderdevops is a tiny, dependency-free HTTP service used for the
// Insider DevOps internship case study. It exposes liveness, health and
// version endpoints, logs every request as structured JSON, and shuts down
// gracefully on SIGINT/SIGTERM.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/faygun21/insiderdevops/handlers"
	"github.com/faygun21/insiderdevops/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// buildSHA is the git commit the binary was built from. It is overridden at
// build time via: go build -ldflags "-X main.buildSHA=<sha>".
// The default keeps `go run .` working without ldflags.
var buildSHA = "dev"

// shutdownTimeout bounds how long in-flight requests may take to drain once a
// termination signal is received.
const shutdownTimeout = 10 * time.Second

func main() {
	// `-healthcheck` lets the binary act as its own health probe. The
	// distroless final image has no shell, wget or curl, so the Docker
	// HEALTHCHECK invokes `/app/server -healthcheck`, which simply calls
	// /healthz over the loopback interface and maps the result to an exit code.
	healthcheck := flag.Bool("healthcheck", false, "probe the local /healthz endpoint and exit 0 (healthy) or 1 (unhealthy)")
	flag.Parse()

	port := getenv("PORT", "8080")

	if *healthcheck {
		os.Exit(runHealthcheck(port))
	}

	// Application routes. These flow through the logging + metrics middleware.
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", handlers.Ping)
	mux.HandleFunc("/healthz", handlers.Healthz)
	mux.HandleFunc("/version", handlers.Version(buildSHA))

	// Root mux. /metrics is mounted here, OUTSIDE middleware.Logger, so the
	// Prometheus scrape is never logged as request traffic nor folded back
	// into the http_* request series (which would inflate cardinality and make
	// every scrape look like load). Everything else is delegated to the logged
	// application mux. promhttp.Handler() serves the default registry, which
	// carries the custom http_* metrics (see package metrics) plus the standard
	// Go runtime and process collectors.
	root := http.NewServeMux()
	root.Handle("/metrics", promhttp.Handler())
	root.Handle("/", middleware.Logger(mux))

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           root,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// Serve in a goroutine so main can block on the signal channel and then
	// drive a graceful shutdown.
	serverErr := make(chan error, 1)
	go func() {
		logJSON("info", "server starting", map[string]any{"addr": srv.Addr, "build_sha": buildSHA})
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serverErr:
		log.Fatalf(`{"level":"fatal","msg":"server failed to start","error":%q}`, err.Error())
	case sig := <-stop:
		logJSON("info", "shutdown signal received", map[string]any{"signal": sig.String()})
	}

	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf(`{"level":"fatal","msg":"graceful shutdown failed","error":%q}`, err.Error())
	}
	logJSON("info", "server stopped cleanly", nil)
}

// getenv returns the value of key, or fallback when it is unset or empty.
func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// runHealthcheck performs an in-process HTTP GET against /healthz and returns
// a process exit code: 0 when the service reports healthy, 1 otherwise.
func runHealthcheck(port string) int {
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%s/healthz", port))
	if err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck request failed: %v\n", err)
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "healthcheck got status %d\n", resp.StatusCode)
		return 1
	}
	return 0
}

// logJSON writes a single structured JSON line to stdout. Startup/shutdown
// events use this so operational logs share the request log's shape (Day 4
// will consolidate this into a real logging package).
func logJSON(level, msg string, fields map[string]any) {
	b := []byte(fmt.Sprintf(`{"level":%q,"msg":%q`, level, msg))
	for k, v := range fields {
		b = append(b, []byte(fmt.Sprintf(`,%q:%q`, k, fmt.Sprint(v)))...)
	}
	b = append(b, '}')
	fmt.Fprintln(os.Stdout, string(b))
}
