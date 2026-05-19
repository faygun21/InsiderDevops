package handlers

import "net/http"

// Healthz is the health endpoint consumed by the Docker HEALTHCHECK and,
// later, Kubernetes liveness/readiness probes.
// GET /healthz -> 200 {"status":"healthy"}.
func Healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "healthy"})
}
