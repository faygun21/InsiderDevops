# Day 1 — Build Log

What was created for each Day 1 task, and the key engineering decisions behind it.

---

## TASK 1.1 — Tiny HTTP service (Go, stdlib only)

**Files:** `go.mod`, `main.go`, `handlers/ping.go`, `handlers/health.go`,
`handlers/version.go`, `handlers/respond.go`, `middleware/logger.go`,
`.env.example`

| Endpoint   | Method | Response                          |
|------------|--------|-----------------------------------|
| `/ping`    | GET    | `200 {"status":"pong"}`           |
| `/healthz` | GET    | `200 {"status":"healthy"}`        |
| `/version` | GET    | `200 {"version":"<BUILD_SHA>"}`   |

**Key points:**

- **Zero dependencies.** Only the Go standard library — `go.mod` has no
  `require` block. Module path: `github.com/faygun21/insiderdevops`.
- **Config via env.** `PORT` is read from the environment, defaulting to
  `8080` (`getenv` helper in `main.go`).
- **`BUILD_SHA` injected at build time** via linker flags
  (`-ldflags "-X main.buildSHA=<sha>"`). The package var `buildSHA` defaults
  to `"dev"` so `go run .` works without flags.
- **Consistent JSON responses.** A single `writeJSON` helper
  (`handlers/respond.go`) sets `Content-Type: application/json` and marshals
  the body, so no handler can forget the header or format.
- **`Version` is a closure**, not a global — `main` passes the injected SHA
  in, keeping the `handlers` package free of package-level state.
- **Structured request logging** (`middleware/logger.go`): one JSON line per
  request with `level`, `time`, `method`, `path`, `status`, `latency_ms`.
  A `statusRecorder` wraps `http.ResponseWriter` to capture the status code
  (the stdlib doesn't expose it after the write). Logs are written with a
  single `os.Stdout.Write` per request so concurrent requests don't produce
  interleaved/garbled JSON — this matters for Day 4 log parsing.
- **Graceful shutdown.** `SIGINT`/`SIGTERM` are caught; the server is given a
  10s `context` timeout to drain in-flight requests before exiting. Server
  runs in a goroutine with a buffered error channel so startup failures are
  surfaced instead of silently lost.
- **`-healthcheck` flag.** The binary can probe itself: it performs an
  in-process `GET /healthz` over loopback and exits `0` (healthy) or `1`.
  This is what makes a healthcheck possible on a shell-less distroless image
  (see Task 1.2).

---

## TASK 1.2 — Dockerfile (multi-stage) + Compose

**Files:** `Dockerfile`, `docker-compose.yaml`, `.env.example`,
`.dockerignore`

**Key points:**

- **Stage 1 (builder):** `golang:1.22-alpine`. `CGO_ENABLED=0`,
  `GOOS=linux`, `GOARCH=amd64`, explicit `GOPROXY` → a fully static,
  reproducible `linux/amd64` binary. `go.mod` is copied before the source so
  the dependency layer caches independently. `BUILD_SHA` arrives as an `ARG`
  and is stamped via `ldflags`. `-s -w -trimpath` strip symbols/paths for a
  smaller, reproducible binary.
- **Stage 2 (final):** `gcr.io/distroless/static:nonroot` — no shell, no
  package manager, no libc, runs as **UID 65532** out of the box. Only the
  compiled binary is copied in; nothing else.
- **HEALTHCHECK limitation documented in the Dockerfile.** distroless has no
  `wget`/`curl`/shell, so a shell-form healthcheck is impossible. The
  exec-form `CMD ["/app/server", "-healthcheck"]` uses the binary's own probe
  instead (`--interval=30s --timeout=5s --retries=3`).
- **`docker-compose.yaml`** — service `app`, build context `.`, build arg
  `BUILD_SHA` (default `dev`), `8080:8080`, `env_file: .env`,
  `restart: unless-stopped`. No obsolete `version:` key.
- **`.dockerignore`** keeps the build context small and guarantees local
  secrets (`.env`) and `.git` never enter an image layer — reinforces the
  "no secrets" constraint.
- **`.env.example`** contains `PORT=8080` and `BUILD_SHA=dev`. The real
  `.env` is git-ignored (already in `.gitignore`).

---

## TASK 1.3 — Repo hygiene

**Files:** `.github/pull_request_template.md`, `.github/CODEOWNERS`,
`README.md` (rewritten)

**Key points:**

- **PR template** with Description, Type of change (bug fix / feature /
  refactor / docs checkboxes), and a Checklist (tests pass, no secrets,
  README updated).
- **CODEOWNERS:** `* @faygun21` — owner derived from the git remote
  (`github.com/faygun21/InsiderDevops`).
- **README** rewritten with: project overview, Track B, prerequisites table,
  quick start, endpoints table, config table, how to run tests, an
  Architecture-notes placeholder for Day 4, and the AI-tools-used note.

---

## TASK 1.4 — Unit tests

**File:** `handlers/handler_test.go` (internal `handlers` package test,
stdlib `testing` + `net/http/httptest` only)

- `TestPingHandler` — GET `/ping`: asserts `200`, body contains `pong`, and
  `Content-Type: application/json`.
- `TestHealthzHandler` — GET `/healthz`: asserts `200`, body contains
  `healthy`.
- `TestVersionHandler` — (bonus) passes a known SHA through the `Version`
  closure and asserts it is echoed back, covering the ldflags path.

---

## Status

All Day 1 files are written. Verification (build/test/run) is **pending Go
and Docker installation** — see [TESTING.md](TESTING.md).
