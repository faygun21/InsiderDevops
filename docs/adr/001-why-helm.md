# ADR 001 — Package the service as a Helm chart

## Status

Accepted.

## Context

The service needs to be deployed to Kubernetes across at least two environments
(`dev` and `prod`) that differ in replica count, image tag, resource limits and
ingress host. Plain `kubectl apply` of static YAML would mean either duplicating
near-identical manifests per environment or hand-editing them at deploy time,
both of which drift and are error-prone. We also want first-class release
history and one-command rollback.

## Decision

We package the Deployment, Service, Ingress, ConfigMap, Secret, NetworkPolicy
and (Day 4) the ServiceMonitor/PrometheusRule as a single Helm chart under
`charts/insiderdevops/`. Environment differences live in `values-dev.yaml` and
`values-prod.yaml`, applied with `helm upgrade --install -f values-<env>.yaml`.
Helm is already the standard packaging format and is installed in the toolchain.

## Consequences

We get templated, DRY manifests, atomic releases with `helm history` and
`helm rollback`, and deploy-time overrides via `--set` (used to keep the Grafana
password and API token out of source). The cost is a templating layer to learn
and a dependency on Helm being present. Chart-level toggles
(`serviceMonitor.enabled`, `prometheusRule.enabled`, `networkPolicy.enabled`)
let the same chart install cleanly on clusters that lack the relevant CRDs.
