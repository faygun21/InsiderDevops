# Day 4 — Build Log (Observability & Public Exposure)

What was created for each Day 4 task, and the key engineering decisions behind
it. Track B: local minikube, Prometheus/Grafana via Helm, public URL via ngrok.

---

## What was built

| File                                                | Purpose                                                                                |
|-----------------------------------------------------|----------------------------------------------------------------------------------------|
| `metrics/metrics.go`                                | Prometheus instruments (`http_requests_total`, `http_request_duration_seconds`) + `Observe` helper |
| `main.go`                                            | Mounts `GET /metrics` (`promhttp.Handler()`) **outside** the logging middleware        |
| `middleware/logger.go`                              | Now records each request into the Prometheus instruments (skips `/metrics`)            |
| `handlers/handler_test.go`                          | Added `TestMetricsHandler` — scrapes `/metrics`, asserts `http_requests_total`         |
| `go.mod` / `go.sum`                                 | Added `github.com/prometheus/client_golang`                                            |
| `scripts/setup-monitoring.ps1`                      | Installs kube-prometheus-stack into `monitoring`, waits for Grafana, prints access     |
| `charts/insiderdevops/templates/servicemonitor.yaml`| ServiceMonitor so Prometheus auto-discovers and scrapes the app's `/metrics`           |
| `charts/insiderdevops/templates/prometheusrule.yaml`| PrometheusRule (`HighErrorRate` alert), toggled by `prometheusRule.enabled`            |
| `charts/insiderdevops/values.yaml`                  | Added `serviceMonitor.*` and `prometheusRule.*` value blocks                           |
| `monitoring/grafana-dashboard.json`                 | Importable dashboard: RPS, p99 latency, error rate, pod restarts                       |
| `monitoring/alert-rules.yaml`                       | Standalone PrometheusRule manifest (the un-templated form of the chart's rule)         |
| `Makefile`                                           | Track B shortcuts: `up/down/load/deploy/monitoring/tunnel/status/all`                  |
| `scripts/expose-service.ps1`                        | port-forward (background) + ngrok to publish the Service on a public URL               |
| `docs/architecture.excalidraw`                      | Architecture diagram (openable at excalidraw.com)                                       |
| `RUNBOOK.md`                                         | Operational runbook (restart, logs, rollback, metrics, secret rotation, Grafana)       |
| `SECURITY.md`                                        | Security posture summary                                                                |
| `docs/adr/001-why-helm.md`                          | ADR: packaging with Helm                                                                |
| `docs/adr/002-why-distroless.md`                    | ADR: distroless non-root base image                                                     |
| `docs/adr/003-why-ngrok.md`                         | ADR: ngrok for the public URL                                                           |
| `README.md`                                          | Added Observability + Public URL sections, links to RUNBOOK/SECURITY                   |

---

## The /metrics wiring at a glance

```
                                   ┌────────────────────────────────┐
 GET /metrics ────────────────────►  promhttp.Handler() (default    │  no logging,
   (Prometheus scrape)              │  registry: http_* + go_* +     │  no self-metrics
                                    │  process_*)                    │
                                    └────────────────────────────────┘
 GET /ping /healthz /version ─────► middleware.Logger ─► app mux
                                         │  - one JSON log line
                                         │  - metrics.Observe(method, path, status, latency)
                                         ▼
                              http_requests_total{method,path,status}
                              http_request_duration_seconds{method,path}
```

`/metrics` is deliberately mounted on a root mux **above** `middleware.Logger`,
so scrapes are neither logged nor counted as request traffic.

---

## Discovery flow (no Prometheus restarts)

```
Helm release (dev ns)                 kube-prometheus-stack (monitoring ns)
 ├─ Service  (port "http" 80)          ├─ Prometheus Operator
 ├─ ServiceMonitor ───────────────────►  watches ServiceMonitors with
 │    label release=kube-prometheus..  │  the matching label, builds scrape
 │    endpoint port=http path=/metrics │  config dynamically
 └─ PrometheusRule ────────────────────►  loads the HighErrorRate alert
      label release=kube-prometheus..  └─ Grafana (reads Prometheus)
```

---

## Key decisions

### Why kube-prometheus-stack (vs installing Prometheus/Grafana separately)

kube-prometheus-stack is the community umbrella chart that bundles the
Prometheus Operator, Prometheus, Alertmanager, Grafana and the standard
exporters (kube-state-metrics, node-exporter) behind a single
`helm upgrade --install`. It is the de-facto production standard, ships sane
defaults and pre-built Kubernetes dashboards, and — crucially — gives us the
ServiceMonitor/PrometheusRule CRDs that make the app's monitoring declarative.
Wiring Prometheus and Grafana up by hand would mean three releases to keep in
sync and hand-written scrape config, for no benefit on a local cluster.

### Why ServiceMonitor over a static scrape config

A static `scrape_configs` entry has to be edited into Prometheus's config and
requires a Prometheus reload/restart whenever a target changes. A ServiceMonitor
is a CRD: the Operator watches for it and rebuilds the scrape configuration
**dynamically**, so deploying or re-deploying the app is picked up automatically
with no Prometheus restart. It also keeps the "what scrapes me" definition in the
app's own Helm chart next to the Service it targets, instead of in a separate,
centrally-owned Prometheus config. The setup script sets
`serviceMonitorSelectorNilUsesHelmValues=false` so the monitor is discovered even
though it lives in the `dev` namespace.

### Why ngrok over `minikube tunnel` for the public URL

`minikube tunnel` needs Administrator elevation on Windows and an entry in
`C:\Windows\System32\drivers\etc\hosts` to resolve the ingress host — and it
still only yields a LAN-local address, not an internet-reachable one. ngrok
needs neither: it opens an outbound tunnel and hands back a real public HTTPS
URL that works from any network, which is exactly what the case study asks to
demonstrate. The trade-off (an external dependency and a rotating free-tier
hostname) is acceptable for a demo. See [adr/003-why-ngrok.md](adr/003-why-ngrok.md).

### Why a PrometheusRule CRD over ConfigMap-based alerts

Before the Operator, alert rules lived in a ConfigMap that Prometheus mounted
and reloaded. A PrometheusRule CRD is GitOps-friendly: it is a first-class,
version-controlled object that the Operator validates and loads automatically,
with no ConfigMap mount, sidecar reloader, or manual reload step. Shipping it in
the chart means the alert is deployed and rolled back together with the code it
watches.

---

## Verification

See the **Definition of Done** checklist in the project brief; the exact
commands are reproduced in [README.md](../README.md) (Observability / Public URL
sections) and [RUNBOOK.md](../RUNBOOK.md).

```powershell
go test ./...                                   # incl. TestMetricsHandler
docker build -t insiderdevops:dev .
minikube image load insiderdevops:dev
helm upgrade --install insiderdevops .\charts\insiderdevops -f values-dev.yaml -n dev --create-namespace
kubectl port-forward svc/insiderdevops 8080:80 -n dev
curl http://localhost:8080/metrics              # shows http_requests_total
.\scripts\setup-monitoring.ps1                  # Grafana at :3000 after port-forward
.\scripts\expose-service.ps1                    # public ngrok URL for /ping
```
