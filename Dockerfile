# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: builder — compile a static, CGO-free linux/amd64 binary.
# ---------------------------------------------------------------------------
FROM golang:1.24-alpine AS builder

# GOPROXY keeps module resolution reproducible; CGO_ENABLED=0 + explicit
# GOOS/GOARCH produce a fully static binary that runs on a scratch/distroless
# base with no libc.
ENV GOPROXY=https://proxy.golang.org,direct \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

WORKDIR /src

# Copy the module file first so this layer is cached until deps change.
# This service has zero external dependencies, so there is no go.sum yet.
COPY go.mod ./
RUN go mod download

COPY . .

# BUILD_SHA is supplied at build time and stamped into the binary via ldflags.
#   -s -w     strip symbol/debug tables (smaller binary)
#   -trimpath remove local filesystem paths (reproducible builds)
ARG BUILD_SHA=dev
RUN go build \
      -trimpath \
      -ldflags="-s -w -X main.buildSHA=${BUILD_SHA}" \
      -o /app/server .

# ---------------------------------------------------------------------------
# Stage 2: final — minimal, non-root runtime.
# ---------------------------------------------------------------------------
# distroless/static:nonroot ships no shell, package manager or libc and runs
# as the unprivileged user nonroot (UID 65532). It is the smallest secure base
# for a static Go binary.
FROM gcr.io/distroless/static:nonroot

WORKDIR /app

# Copy ONLY the compiled binary from the builder stage — nothing else.
COPY --from=builder /app/server /app/server

EXPOSE 8080

# distroless has no shell, wget or curl, so a shell-form HEALTHCHECK is
# impossible. Instead the binary probes itself: `-healthcheck` performs an
# in-process GET against /healthz and exits 0 (healthy) or 1 (unhealthy).
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD ["/app/server", "-healthcheck"]

# UID 65532 (nonroot) is provided by the base image — no adduser needed.
ENTRYPOINT ["/app/server"]
