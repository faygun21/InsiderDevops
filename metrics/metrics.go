// Package metrics defines the Prometheus instruments exposed by the service
// and the helper used to record one finished HTTP request.
//
// It lives in its own package (rather than in main) so the request-logging
// middleware can record into the same instruments without an import cycle:
// main can't be imported, so the metrics it "owns" must live somewhere both
// main and middleware can reach.
//
// The collectors are registered with the default Prometheus registry via
// promauto, which is the same registry promhttp.Handler() serves. That
// registry already carries the standard Go runtime collectors (go_goroutines,
// go_memstats_*, ...) and the process collectors, so /metrics exposes those
// automatically — only the two custom HTTP series below are added here.
package metrics

import (
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// RequestsTotal counts every HTTP request the service handles, broken
	// down by method, request path and response status code.
	RequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests, by method, path and status code.",
		},
		[]string{"method", "path", "status"},
	)

	// RequestDuration tracks request latency in seconds as a histogram, by
	// method and path. DefBuckets is the client's default latency-oriented
	// bucket set (5ms .. 10s) — plenty for a tiny in-cluster service.
	RequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request latency in seconds, by method and path.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)
)

// Observe records a single completed request against both instruments. The
// status is converted to its decimal string so series stay comparable with
// PromQL filters like status=~"5..".
func Observe(method, path string, status int, d time.Duration) {
	RequestsTotal.WithLabelValues(method, path, strconv.Itoa(status)).Inc()
	RequestDuration.WithLabelValues(method, path).Observe(d.Seconds())
}
