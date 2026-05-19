package handlers

import "net/http"

// Version returns a handler that reports the build SHA. It is a closure so
// main can pass the ldflags-injected value in without the handlers package
// needing a package-level variable.
// GET /version -> 200 {"version":"<BUILD_SHA>"}.
func Version(buildSHA string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"version": buildSHA})
	}
}
