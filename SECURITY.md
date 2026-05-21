# Security

Security posture for the InsiderDevops service and its supply chain. Track B
(local minikube), so the threat model is "a small public-facing demo service",
not a hardened multi-tenant production system — but the controls below are the
ones that carry over to production.

## Reporting a vulnerability

This is an internship case-study project. Please open a private GitHub issue or
contact the maintainer (`faygun21`) rather than disclosing publicly.

## Controls

### Container runs as non-root (distroless)

The runtime image is `gcr.io/distroless/static:nonroot` — no shell, no package
manager, no libc — and runs as the unprivileged user **UID 65532**. The Helm
chart enforces this at the pod level too: `runAsNonRoot: true`,
`readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, and all
Linux capabilities dropped (`capabilities.drop: [ALL]`). A smaller attack
surface and no writable root FS sharply limit what a compromised process can do.
See [adr/002-why-distroless.md](docs/adr/002-why-distroless.md).

### No secrets in the repo

- `.env` is git-ignored; only `.env.example` (placeholder values) is committed.
- **gitleaks** runs in CI (`.github/workflows/ci.yaml`) over history and fails
  the build on a detected secret.
- The chart's `secret.API_TOKEN` default is a non-functional **placeholder**;
  the real value is supplied at deploy time via `--set` (or a secrets operator),
  never committed.

### Image scanning in CI

**Trivy** scans every image built in CI and **fails the pipeline on
CRITICAL/HIGH** findings (`exit-code: 1`). It runs with `ignore-unfixed: true`,
so the build only blocks on vulnerabilities that have an upstream fix available
— actionable, not noise.

### Network segmentation

A **NetworkPolicy** (`charts/insiderdevops/templates/networkpolicy.yaml`,
enabled by default) restricts **ingress to the nginx ingress-controller pods
only**; every other source is implicitly denied. Egress is allowed (DNS,
upstreams). This means the pod cannot be reached directly inside the cluster,
only through the intended ingress path.

### Secret management — current vs. production

The chart renders a Kubernetes `Secret` from a placeholder value. Kubernetes
Secrets are only base64-encoded at rest by default, so for **production** the
recommendation is **sealed-secrets** or **external-secrets** (e.g. backed by a
cloud secrets manager / Vault), so encrypted material can live in git and be
decrypted only in-cluster. Rotation procedure is in
[RUNBOOK.md](RUNBOOK.md#5-secret-rotation).

### Supply-chain traceability

The GHCR image is **public** (Track B needs minikube to pull it without
credentials), but every build is tagged with its **git short SHA**
(`ghcr.io/faygun21/insiderdevops:<sha>`), so any running image is traceable back
to the exact commit and CI run that produced it. Releases additionally carry a
SemVer tag.

## Summary

| Area            | Control                                                            |
|-----------------|-------------------------------------------------------------------|
| Runtime user    | Non-root UID 65532, distroless, read-only root FS, caps dropped    |
| Secrets in repo | `.env` git-ignored, gitleaks in CI, placeholder-only in chart      |
| Image CVEs      | Trivy in CI, fails on fixable CRITICAL/HIGH                        |
| Network         | NetworkPolicy — ingress from nginx-controller only                 |
| Secrets (prod)  | Recommend sealed-secrets / external-secrets                        |
| Traceability    | SHA-tagged images map a running container to its commit            |
