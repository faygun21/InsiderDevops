# InsiderDevops

## Project overview

InsiderDevops is a tiny, production-shaped HTTP service written in Go using
**only the standard library** (no web frameworks). It exposes liveness, health
and version endpoints, logs every request as structured JSON to stdout, reads
all configuration from environment variables, and shuts down gracefully on
`SIGINT`/`SIGTERM`. It ships as a multi-stage, distroless, non-root container
image. It is the running artifact for the Insider DevOps internship case study.

## Track

**Track B — Local:** minikube + ngrok. No AWS; everything runs locally.

## Prerequisites

| Tool      | Version  | Purpose                              |
|-----------|----------|--------------------------------------|
| Go        | 1.22+    | Build and test the service           |
| Docker    | 20.10+   | Build/run the container image        |
| minikube  | latest   | Local Kubernetes cluster (Day 3+)    |
| kubectl   | latest   | Talk to the cluster (Day 3+)         |
| ngrok     | latest   | Expose the local service (Day 3+)    |

## Quick start

```bash
git clone https://github.com/faygun21/InsiderDevops.git
cd InsiderDevops
cp .env.example .env          # Windows PowerShell: Copy-Item .env.example .env
docker compose up --build
```

The service is then available at `http://localhost:8080`.

```bash
curl http://localhost:8080/ping      # {"status":"pong"}
curl http://localhost:8080/healthz   # {"status":"healthy"}
curl http://localhost:8080/version   # {"version":"dev"}
```

## Endpoints

| Path       | Method | Success response                 |
|------------|--------|----------------------------------|
| `/ping`    | GET    | `200` `{"status":"pong"}`        |
| `/healthz` | GET    | `200` `{"status":"healthy"}`     |
| `/version` | GET    | `200` `{"version":"<BUILD_SHA>"}`|

All responses are `Content-Type: application/json`.

## Configuration

| Variable    | Default | Description                                            |
|-------------|---------|--------------------------------------------------------|
| `PORT`      | `8080`  | TCP port the HTTP server listens on                    |
| `BUILD_SHA` | `dev`   | Build identifier; injected at build time via `ldflags` |

## Run tests locally

```bash
go mod tidy
go test ./...
```

Run the service directly without Docker:

```bash
go run -ldflags "-X main.buildSHA=$(git rev-parse --short HEAD)" .
```

## Architecture notes

_Placeholder — to be filled on Day 4 (structured JSON logging, observability,
Kubernetes manifests, and the minikube + ngrok exposure path)._

## AI tools used

Claude Code (Claude Sonnet) for code generation; all decisions and reasoning
are my own.
