# Day 2 — Build Log (Kubernetes / Helm)

What was created for each Day 2 task, and the key engineering decisions
behind it. Track B: local minikube + nginx ingress, Windows host.

---

## What was built

| File                                              | Purpose                                                                 |
|---------------------------------------------------|-------------------------------------------------------------------------|
| `charts/insiderdevops/Chart.yaml`                 | Chart metadata; `appVersion: v0.1.0` is the default image version       |
| `charts/insiderdevops/values.yaml`                | Chart defaults (image, probes, resources, ingress, networkPolicy)       |
| `charts/insiderdevops/templates/_helpers.tpl`     | Name/label helpers; every resource is prefixed via `…fullname`          |
| `charts/insiderdevops/templates/deployment.yaml`  | Deployment: probes, resources, `envFrom` ConfigMap + Secret             |
| `charts/insiderdevops/templates/service.yaml`     | ClusterIP Service (port 80 → container `http`/8080)                      |
| `charts/insiderdevops/templates/ingress.yaml`     | nginx Ingress via `kubernetes.io/ingress.class: nginx` annotation       |
| `charts/insiderdevops/templates/configmap.yaml`   | Non-secret config (`PORT`, `LOG_LEVEL`) → env vars                       |
| `charts/insiderdevops/templates/secret.yaml`      | Placeholder Secret, base64 via `b64enc`; overridden in prod             |
| `charts/insiderdevops/templates/networkpolicy.yaml`| Bonus: ingress only from ingress-nginx, allow all egress (toggleable)   |
| `charts/insiderdevops/templates/NOTES.txt`        | Prints the service URL + Track B host/tunnel hint after deploy          |
| `values-dev.yaml`                                 | Dev overrides: 1 replica, tag `dev`, low resources, host `app.local`    |
| `values-prod.yaml`                                | Prod overrides: 2 replicas, tag `v0.1.0`, 2× resources, host `app.prod` |
| `scripts/load-image.ps1`                          | `minikube image load insiderdevops:dev` (+ pre/post checks)             |
| `scripts/rollout-test.ps1`                        | Deploy → bad upgrade → rollback drill with evidence                     |
| `docs/DAY2.md`                                    | This build log                                                          |
| `README.md`                                       | Added the "Kubernetes / Helm" section                                   |

Starter templates removed after `helm create` (unused for a single service):
`hpa.yaml`, `httproute.yaml`, `serviceaccount.yaml`, `templates/tests/`.

---

## Key decisions

### Why Helm over raw manifests

- **One artifact, many environments.** Dev and prod differ only by a small
  `-f values-<env>.yaml` overlay (replicas, image tag, resources, host).
  Raw manifests would mean duplicated YAML kept in sync by hand.
- **Release lifecycle is built in.** `helm upgrade --install`,
  `helm history`, and `helm rollback` give first-class, atomic-ish
  rollout/rollback (Task 2.4) that plain `kubectl apply` does not.
- **Safe naming.** Every resource is prefixed with the release name via
  `{{ include "insiderdevops.fullname" . }}`, so multiple releases (e.g. the
  `dev` and `prod` namespaces) never collide.
- **Config rolls pods automatically.** The Deployment carries
  `checksum/config` and `checksum/secret` pod annotations, so editing the
  ConfigMap/Secret triggers a rollout — something raw manifests don't do.

### How the resource values were chosen

The service is a single static Go binary on a distroless base. Observing it
under `go run .` and in the container (idle and under light `curl` load)
shows RSS well under ~20 MiB and negligible CPU. So:

| Env  | requests      | limits        | Reasoning                                              |
|------|---------------|---------------|--------------------------------------------------------|
| dev  | 50m / 64Mi    | 100m / 128Mi  | Low footprint; stays schedulable on a small minikube VM|
| prod | 100m / 128Mi  | 200m / 256Mi  | 2× headroom for real traffic across the extra replica  |

Requests are set to the realistic idle footprint (so the scheduler packs
honestly); limits are a comfortable multiple to absorb spikes without OOM.

### Why a NetworkPolicy was added (bonus)

Default Kubernetes networking is allow-all: any pod can talk to the service
directly, bypassing the ingress. The policy applies a **default-deny for
ingress** and permits inbound **only** from pods labelled
`app.kubernetes.io/name: ingress-nginx` (combined with `namespaceSelector: {}`
because minikube runs the controller in its own `ingress-nginx` namespace).
Egress is left open to keep DNS/outbound simple. It is gated behind
`networkPolicy.enabled` (default `true`) so it can be turned off for
debugging without editing templates.

> Note: a NetworkPolicy only has effect if the cluster CNI enforces it. On
> minikube this means a policy-capable CNI (e.g. Calico); with the default
> CNI the policy is accepted but not enforced. It is still correct to ship.

---

## Rollout / rollback evidence

`scripts/rollout-test.ps1` deploys the good release, forces a bad one
(`image.tag=v0.2.0-test`, a tag never loaded into minikube → ImagePullBackOff),
watches the rollout fail within a timeout, then `helm rollback`s to the
previous revision and re-verifies health.

_Screenshots to be added after verification_ — `helm history insiderdevops -n dev`
and the `kubectl rollout status` output before/after rollback.

---

## Status

All Day 2 files are written and the chart passes `helm lint` and
`helm template` rendering for default, `values-dev.yaml`, and
`values-prod.yaml`. Live cluster verification (image load → deploy →
rollout drill) is **pending a running minikube** — see the commands in
[../README.md](../README.md#kubernetes--helm) and the Definition of Done.
