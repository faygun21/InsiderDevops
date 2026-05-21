# ADR 003 — Expose the public URL with ngrok

## Status

Accepted.

## Context

The case study (Track B) requires a publicly reachable URL for the service, but
the cluster is a local minikube running inside Docker Desktop on Windows, behind
a home NAT. The Service is `ClusterIP`, so it is not reachable from outside the
cluster at all. The built-in option, `minikube tunnel`, requires Administrator
elevation on Windows, needs an entry in `C:\Windows\System32\drivers\etc\hosts`
to resolve the ingress host, and still only produces a LAN-local address — not
something reachable from the public internet.

## Decision

We expose the service with **ngrok**. `scripts/expose-service.ps1` starts a
background `kubectl port-forward` from `localhost:8080` to the Service, waits for
it to bind, then runs `ngrok http 8080`, which opens an outbound tunnel and
returns a public HTTPS URL. ngrok is already installed and authenticated in the
environment.

## Consequences

We get a real, internet-reachable HTTPS endpoint with no admin rights, no hosts
-file edits and no inbound firewall/NAT changes — `curl <url>/ping` works from
any network, which is exactly the demo the brief asks for. The trade-offs: ngrok
is an external dependency and a man-in-the-middle for tunneled traffic, and the
free-tier hostname is ephemeral (it changes each run and shows an interstitial),
so it is unsuitable for stable production use. For a local demo these are
acceptable; a production deployment would front the service with a real
ingress/load balancer and DNS instead.
