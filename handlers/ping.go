package handlers

import "net/http"

// Ping is a lightweight liveness endpoint: if it answers, the process is up
// and serving HTTP. GET /ping -> 200 {"status":"pong"}.
func Ping(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "pong"})
}
