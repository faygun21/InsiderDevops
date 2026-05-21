# ADR 002 — Use a distroless, non-root base image

## Status

Accepted.

## Context

The service is a single static, CGO-free Go binary, so the runtime image needs
nothing beyond the binary itself — no shell, package manager or libc. Common
bases like `alpine` or `ubuntu` ship a full userland that enlarges the image and
the attack surface (every extra package is a potential CVE) and, by default, run
as root. We want the smallest, hardest-to-abuse runtime that still runs the
binary.

## Decision

The final stage of the multi-stage Dockerfile is `gcr.io/distroless/static:nonroot`,
which contains only CA certificates and timezone data and runs as the
unprivileged user UID 65532. The Helm chart reinforces this with
`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false` and
dropping all Linux capabilities. Because distroless has no shell, the Docker
`HEALTHCHECK` invokes the binary's own `-healthcheck` flag instead of `curl`.

## Consequences

The image is tiny, has a minimal CVE surface, and a compromised process has no
shell, no writable root FS and no root privileges to pivot from — which is also
what lets Trivy keep a clean bill of health. The trade-offs are real: you cannot
`kubectl exec` into a shell for debugging (use ephemeral debug containers or
logs instead), and any future need for runtime tools (e.g. `curl`) must be
solved without a package manager. For a self-contained Go service these costs
are acceptable.
