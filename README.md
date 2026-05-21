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

## Kubernetes / Helm

Day 2 ships a Helm chart at [charts/insiderdevops/](charts/insiderdevops/)
with a Deployment, ClusterIP Service, nginx Ingress, ConfigMap, Secret and an
optional NetworkPolicy. Two overlays — [values-dev.yaml](values-dev.yaml) and
[values-prod.yaml](values-prod.yaml) — differ in replicas, image tag,
resources and ingress host. See [docs/DAY2.md](docs/DAY2.md) for the
decisions.

### Prerequisites (already installed)

| Tool     | Version  | Notes                                        |
|----------|----------|----------------------------------------------|
| minikube | v1.38.1  | Started with `--driver=docker`               |
| kubectl  | v1.36.1  | Talks to the minikube cluster                |
| helm     | v3.21.0  | Installs/upgrades the chart                  |

Enable the ingress controller once: `minikube addons enable ingress`.

### 1. Load the local image into minikube (Track B — required)

Track B uses **no registry**. minikube's in-cluster Docker daemon cannot see
the host's images, so the built image must be side-loaded first. With
`imagePullPolicy: IfNotPresent` the kubelet then uses the loaded image
instead of trying to pull it.

```powershell
docker build -t insiderdevops:dev .      # if not already built
.\scripts\load-image.ps1                  # runs: minikube image load insiderdevops:dev
```

### 2. Deploy to dev

```powershell
helm upgrade --install insiderdevops .\charts\insiderdevops `
  -f values-dev.yaml --create-namespace --namespace dev
```

### 3. Deploy to prod

Same command, prod overlay and namespace (2 replicas, tag `v0.1.0`,
host `app.prod`):

```powershell
helm upgrade --install insiderdevops .\charts\insiderdevops `
  -f values-prod.yaml --create-namespace --namespace prod
```

### 4. Rollout / rollback test

Deploys, forces a bad image tag, watches it fail, then rolls back and prints
`helm history` + `kubectl rollout status` as evidence:

```powershell
.\scripts\rollout-test.ps1
```

### 5. Continuous deployment (Track B limitation)

CI builds and pushes the image to GHCR, but the cluster is a **local minikube**
that the cloud GitHub runner cannot reach — so it cannot run `helm upgrade` for
you. Instead, the `deploy.yaml` workflow records the image that should be
running in [deploy/current-image.txt](deploy/current-image.txt) and commits it
back to `main`. You then roll it onto the local cluster yourself:

```powershell
git pull                       # fetch the latest deploy/current-image.txt
.\scripts\apply-latest.ps1     # helm upgrade --install to namespace dev + rollout status
```

> The image now lives in GHCR, so the package must be **public** (or an
> `imagePullSecret` configured) for minikube to pull it. See
> [CI/CD](#cicd) below for the full pipeline.

### Ingress host setup (Windows)

The Ingress matches on `Host`, so the hostname must resolve locally and a
tunnel must be open:

> Add `127.0.0.1 app.local` to `C:\Windows\System32\drivers\etc\hosts`
> (edit as Administrator), then run `minikube tunnel` in a separate
> terminal. For prod, add `127.0.0.1 app.prod` as well.

```powershell
curl http://app.local/ping       # {"status":"pong"}
```

## CI/CD

Three GitHub Actions workflows live in [.github/workflows/](.github/workflows/).
Every workflow has a least-privilege `permissions:` block and a `concurrency:`
group that cancels redundant runs on the same ref. See
[docs/DAY3.md](docs/DAY3.md) for the design decisions.

### CI — [`ci.yaml`](.github/workflows/ci.yaml)

Runs on **push to any branch**, **PRs into `main`/`dev`**, and **manually**
(`workflow_dispatch`):

```
 push / PR / manual
   │
   ├── lint-and-test ─────────┐        gitleaks  (parallel — no needs:)
   │   go vet                 │        secret scan over full history
   │   go test -race + cover  │
   │   upload coverage.out    │
   │                          ▼
   └───────────────► build-and-scan   (needs: lint-and-test)
                       docker build (load locally, no push)
                       Trivy scan ── fixable CRITICAL/HIGH? ──► PIPELINE FAILS
                       login GHCR (GHCR_TOKEN)
                       docker push :<short-sha>   (+ :latest on main)
```

Trivy runs with `ignore-unfixed: true` and `exit-code: 1`, so the build fails
only on CRITICAL/HIGH vulnerabilities that actually have an upstream fix.

### Release — [`release.yaml`](.github/workflows/release.yaml)

Triggered **only** by a SemVer tag. Builds and pushes `:<tag>` + `:latest` to
GHCR and publishes a GitHub Release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

### Deploy — [`deploy.yaml`](.github/workflows/deploy.yaml)

On push to `main`, records the desired image in `deploy/current-image.txt` and
commits it back. The actual rollout to the local minikube is done on your
machine — see [Continuous deployment (Track B limitation)](#5-continuous-deployment-track-b-limitation)
above and [scripts/apply-latest.ps1](scripts/apply-latest.ps1).

### Image location

```
ghcr.io/faygun21/insiderdevops:<short-sha>   # every successful build
ghcr.io/faygun21/insiderdevops:latest        # main + every release
ghcr.io/faygun21/insiderdevops:v0.1.0        # tagged releases
```

### Secrets

- `GHCR_TOKEN` — PAT used **only** for `docker login ghcr.io`.
- `GITHUB_TOKEN` — built in; used for checkout, the GitHub Release, and the
  deploy commit. No secrets are hardcoded in any workflow.

## Architecture notes

_Placeholder — to be filled on Day 4 (structured JSON logging, observability,
Kubernetes manifests, and the minikube + ngrok exposure path)._

## AI tools used

Claude Code (Claude Sonnet) for code generation; all decisions and reasoning
are my own.
