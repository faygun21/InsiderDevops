# Day 3 — Build Log (CI/CD & Supply Chain)

What was created for each Day 3 task, and the key engineering decisions behind
it. Track B: local minikube, GitHub-hosted runners, images in GHCR.

---

## What was built

| File                                  | Purpose                                                                            |
|---------------------------------------|-----------------------------------------------------------------------------------|
| `.github/workflows/ci.yaml`           | CI on every push / PR: `lint-and-test`, `build-and-scan` (Trivy → GHCR), `gitleaks` |
| `.github/workflows/release.yaml`      | On `v*.*.*` tags: build & push `:<tag>` + `:latest`, publish a GitHub Release       |
| `.github/workflows/deploy.yaml`       | On push to `main`: record the desired image (poor man's GitOps) and commit it back  |
| `scripts/apply-latest.ps1`            | Local half of the deploy: read `current-image.txt`, `helm upgrade --install` to dev |
| `deploy/current-image.txt`            | The image reference CI says should be running (updated by `deploy.yaml`)            |
| `CHANGELOG.md`                        | Keep a Changelog / SemVer release notes                                            |
| `docs/DAY3.md`                        | This build log                                                                     |
| `README.md`                           | Added the "CI/CD" section + Track B CD limitation note                             |

---

## Pipeline at a glance

```
 push (any branch) / PR (main,dev) / manual
        │
        ├── lint-and-test ──┐         gitleaks  (parallel, no needs:)
        │   go vet          │
        │   go test -race   │
        │   upload coverage │
        │                   ▼
        └────────────► build-and-scan
                        docker build (load, no push)
                        Trivy scan  ── CRITICAL/HIGH fixable? ──► FAIL
                        login GHCR (GHCR_TOKEN)
                        docker push :<sha>   (+ :latest on main)

 tag v*.*.*  ──► release.yaml ──► build & push :<tag> + :latest ──► GitHub Release
 push main   ──► deploy.yaml  ──► write deploy/current-image.txt ──► commit back
                                        │
                                developer runs scripts/apply-latest.ps1 locally
                                        ▼
                                helm upgrade --install -> minikube (dev)
```

---

## Key decisions

### Why `kubectl set image` / `helm --set` over ArgoCD / Flux

A full GitOps controller (ArgoCD, Flux) is the right answer when a cluster is
always-on and reachable. On Track B the cluster is a laptop minikube that the
cloud runner cannot reach, and the whole point is to stay light. Driving the
rollout with a single `helm upgrade --install ... --set image.tag=<sha>` keeps
**zero extra cluster tooling** to install, secure and upgrade, and fits the
local dev loop. The trade-off — tight coupling between the pipeline and the
cluster, and an imperative rather than continuously-reconciled deploy — is
accepted deliberately for a local single-service setup. The "desired image in
git, applied by a small script" shape mirrors GitOps closely enough to swap in
ArgoCD later without changing how the image gets built.

### Why Trivy runs with `ignore-unfixed`

Unfixed vulnerabilities are noise we cannot act on: there is no upstream patch
to apply, so failing the build on them would only teach the team to ignore red
pipelines. We fail hard on **fixable** CRITICAL/HIGH findings (the ones a base
image bump or dependency update resolves) and let unfixed ones through, where
they belong in a tracked backlog rather than a merge blocker. The distroless
base keeps the surface tiny, so this stays a sharp signal.

### Why gitleaks runs in parallel (no `needs:`)

Secret scanning answers a different question from "does the code build and
pass tests" — it asks "did someone commit a credential". Those are
independent, so chaining gitleaks behind the build would only delay the most
urgent feedback. Running it as its own dependency-free job means a leaked
secret surfaces in seconds, in parallel with `lint-and-test`.

### Why GHCR over Docker Hub

GitHub Container Registry is **free for public repositories**, is **natively
integrated** with the repo and `GITHUB_TOKEN`/PAT auth, and — critically for
CI — imposes **no anonymous pull rate limits** on Actions runners, unlike
Docker Hub, whose limits routinely break CI on shared runner IPs. Keeping the
image next to the code also means one place for permissions and provenance.

---

## Secrets & permissions

- **`GHCR_TOKEN`** (a PAT with `write:packages`) is used *only* for
  `docker login ghcr.io`.
- **`GITHUB_TOKEN`** (auto-provisioned) is used for checkout, the GitHub
  Release, and committing `deploy/current-image.txt` back to main.
- No secrets are hardcoded in any workflow; everything comes from
  `${{ secrets.* }}`.
- Every workflow declares a top-level `permissions:` block (least privilege)
  and a `concurrency:` group to cancel redundant runs.

---

## Status / Definition of Done

CI triggers on push and PR, fails closed on fixable CRITICAL/HIGH vulns, and
pushes `ghcr.io/faygun21/insiderdevops:<sha>` on success. Tagging `v0.1.0`
publishes `:v0.1.0` + `:latest` and a GitHub Release. The merge-to-main
deploy records the desired image; `scripts/apply-latest.ps1` rolls it onto the
local cluster. See the verification steps in
[../README.md](../README.md#cicd) and the case-study Definition of Done.
