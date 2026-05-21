# RUNBOOK — InsiderDevops (Track B)

Operational procedures for the `insiderdevops` service running on local
minikube in the `dev` namespace. All commands are PowerShell-friendly. Assumes
`kubectl`, `helm` and `minikube` are on `PATH` and minikube is running.

> Quick context: the Helm release is `insiderdevops`, namespace `dev`. Pods are
> selected by `app.kubernetes.io/instance=insiderdevops`. Monitoring lives in
> the `monitoring` namespace (kube-prometheus-stack).

---

## 1. Restart the service

Triggers a rolling restart (new pods, zero-downtime with the readiness probe):

```powershell
kubectl rollout restart deployment/insiderdevops -n dev
kubectl rollout status  deployment/insiderdevops -n dev --timeout=120s
```

---

## 2. View logs

The service logs one structured JSON line per request to stdout:

```powershell
kubectl logs -n dev -l app.kubernetes.io/instance=insiderdevops --tail=50
```

Add `-f` to follow, or `--previous` to read the last crashed container's logs.

---

## 3. Roll back

Roll back to the previous Helm revision (e.g. after a bad deploy):

```powershell
helm history  insiderdevops -n dev          # find the last good REVISION
helm rollback insiderdevops -n dev          # back one revision (omit N = previous)
kubectl rollout status deployment/insiderdevops -n dev --timeout=120s
```

`helm rollback insiderdevops <REVISION> -n dev` targets a specific revision.

---

## 4. Check metrics

```powershell
kubectl port-forward svc/insiderdevops 8080:80 -n dev
# in another terminal:
curl http://localhost:8080/metrics          # Prometheus text format
curl http://localhost:8080/metrics | Select-String http_requests_total
```

Expect `http_requests_total`, `http_request_duration_seconds_*`, plus the
standard `go_*` and `process_*` runtime metrics.

---

## 5. Secret rotation

Rotate the API token without committing it to git (apply-from-stdin so the new
value never lands in shell history as a manifest file):

```powershell
kubectl create secret generic insiderdevops `
  --from-literal=API_TOKEN=<new-token> `
  --dry-run=client -o yaml | kubectl apply -f - -n dev

# roll the pods so they pick up the new value:
kubectl rollout restart deployment/insiderdevops -n dev
```

> Note: this secret is normally managed by the Helm chart. If you rotate it
> out-of-band like this, set the same value via `--set secret.API_TOKEN=...` on
> the next `helm upgrade` so Helm does not revert it. For production, prefer
> sealed-secrets or external-secrets (see [SECURITY.md](SECURITY.md)).

---

## 6. Grafana access

```powershell
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# open http://localhost:3000   (user: admin, password: set via --set at install)
```

Prometheus UI (targets / alerts):

```powershell
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# open http://localhost:9090  ->  Status > Targets  (confirm insiderdevops is UP)
#                                  Alerts            (confirm HighErrorRate loaded)
```

Import the dashboard once Grafana is open: **Dashboards → New → Import →
Upload** `monitoring/grafana-dashboard.json`, then select the Prometheus
datasource when prompted.

---

## Quick triage

| Symptom                              | First checks                                                              |
|--------------------------------------|--------------------------------------------------------------------------|
| Pods not Ready                       | `kubectl get pods -n dev`, `kubectl describe pod <pod> -n dev`            |
| `ImagePullBackOff`                   | Image not side-loaded: `minikube image load insiderdevops:dev`           |
| Target missing in Prometheus        | ServiceMonitor `release` label must equal the stack release name         |
| `HighErrorRate` firing              | `kubectl logs ... --tail=100` for 5xx; check upstream / recent rollout   |
| Public URL down                     | Re-run `scripts/expose-service.ps1`; confirm the port-forward job is up   |
