package handlers

import (
	"encoding/json"
	"net/http"
)

// writeJSON serialises v and writes it with the given status code and a
// Content-Type of application/json. Centralised so every endpoint stays
// consistent and the header is never accidentally omitted.
func writeJSON(w http.ResponseWriter, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		http.Error(w, `{"error":"failed to encode response"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
