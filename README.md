# October DevOps – K8s + Helm + CI/CD + Observability

A small two-service demo (FastAPI **API** + Celery **worker** with Redis) built:

- Docker & Compose

- Kubernetes (manifests → Helm)

- CI/CD (build, test, scan, deploy, E2E smoke)

- Observability (Prometheus + Grafana, alerts)

## Architecture (ASCII)

```
                 ┌───────────────────────┐
Client ──HTTP──► │  Ingress (NGINX, K8s) │  host: api.<minikube-ip>.nip.io
                 └──────────┬────────────┘
                            │
                       ┌────▼────┐          ┌───────────────────┐
                       │ Service │─────────►│   Deployment API  │
                       │   api   │          │  (FastAPI + /metrics)
                       └────┬────┘          └───────────────────┘
                            │
                            │  Celery (broker/backend)
                            ▼
                     ┌──────────────┐      ┌───────────────────┐
                     │   Service    │─────►│ Deployment Worker │
                     │    redis     │      │  (Celery)         │
                     └──────┬───────┘      └───────────────────┘
                            │
                            ▼
                      ┌───────────┐
                      │ PVC/data  │
                      └───────────┘
```

> Coming up: CI/CD, Prometheus/Grafana.

## Repo Layout (Now)

```
api/                     # FastAPI app (+ tests, lint)
worker/                  # Celery tasks
deploy/
  helm/
    api/                 # <—— SOURCE OF TRUTH (Helm chart)
scripts/                 # tools (load tester etc.)
docs/                    # runbooks, checklists, release artifacts
docker-compose.yml
Makefile
```

> **Note:** `deploy/k8s-examples/` contains raw K8s manifests for educational reference only.

## Quickstart

### Local (Docker)

```bash
make build-api
make run-api-docker
curl -s localhost:8000/healthz
make stop-api
```

### Stack (Compose)

```bash
make compose-up     # api + redis + worker
make compose-logs
make worker-ping    # enqueue ping()
make worker-add     # enqueue add(1,2)
make compose-down
```

### Kubernetes (Minikube)

```bash
minikube start

# API
make k8s-build-load  # build & load october-api:dev into minikube
make k8s-apply
make k8s-get
make k8s-port-api    # forwards :8080 -> svc/api
curl -s localhost:8080/healthz

# Redis + Worker
make k8s-apply-redis            # PVC + Redis deployment + service
make k8s-build-load-worker      # build & load october-worker:dev
make k8s-apply-worker           # Celery worker deployment
make k8s-logs-worker            # tail worker logs
make k8s-exec-worker-ping       # enqueue ping() task
make k8s-exec-worker-add        # enqueue add(1,2) task
```

### Ingress (NGINX on Minikube)

```bash
make k8s-enable-ingress  # one-time
make k8s-apply-ingress   # applies Ingress with host api.<minikube-ip>.nip.io
make k8s-curl-ingress    # smoke: /healthz
```

### HPA (CPU) on Minikube

```bash
make k8s-enable-metrics
make k8s-apply-hpa
kubectl -n october get hpa api -w

# Generate load (Ingress):
IP=$(minikube ip)
make load-test URL=http://api.$IP.nip.io/healthz CONC=200 DUR=120

# Observe:
make k8s-top
```

### Helm (dev/prod)

```bash
make helm-lint         # Lint chart structure
make helm-template-dev # Render templates (preview)
make helm-up-dev       # Install/upgrade to namespace 'october'
make helm-del          # Uninstall release

# Verify:
IP=$(minikube ip)
curl -s http://api.$IP.nip.io/healthz

helm history app -n october
helm rollback app <REV> -n october

```

### Upgrades & Rollbacks

```bash
# Preview changes
make helm-diff-dev

# Upgrade
make helm-up-dev
kubectl -n october rollout status deploy/api

# Rollback
make helm-history
make helm-rollback REV=<number>

# Notes:
- Use `helm diff` before every upgrade
- Keep image tags immutable.
```

The Helm chart (`deploy/helm/api`) includes API, Redis, Worker, Ingress, and HPA in a single release.

**Environment-specific values:**

- **`values-dev.yaml`**: Local dev (Minikube) — single replicas, local images (`:dev` tag), nip.io ingress
- **`values-prod.yaml`**: Production — 2+ replicas, HPA enabled, versioned images from registry (`:0.1.0`), real domain

> **Note:** For **production and development** deployments, always use **Helm** (`make helm-*`).
> The `deploy/k8s-examples/` directory contains raw Kubernetes manifests for **educational purposes only**.
> Raw manifest commands (`make k8s-*`) are useful for learning Kubernetes concepts, but should **not** be used for production deployments.

### Registry & Image Tags

- Registry: GHCR (`ghcr.io/<user>/october-api`, `october-worker`)
- Tags:
  - `:dev` — latest dev build
  - `:sha-<short>` — immutable
  - `:vX.Y.Z` — git tag release

CI pushes on PR/main. To release:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

### CD to Dev (GitHub Actions)

Secrets required:

- `DEV_KUBECONFIG` – kubeconfig for dev cluster
- `DEV_NAMESPACE` – e.g., october
- `DEV_INGRESS_HOST` – e.g., api.<minikube-ip>.nip.io

Deploy runs on push to `main`:

- Lint → Template → Helm upgrade --install (images from GHCR `:dev` by default).

## Health & Probes

- **/healthz** → liveness (process alive)
- **/ready** → readiness (accepts traffic)
- **/metrics** → Prometheus exposition format

K8s probes:

- `startupProbe`: /healthz (gives the app warmup time)
- `readinessProbe`: /ready
- `livenessProbe`: /healthz

## Make targets

Run `make help` for a list. Highlights:

- **Dev:** `install`, `lint`, `fmt`, `test`
- **Docker:** `build-api`, `run-api-docker`, `stop-api`
- **Compose:** `compose-up|logs|down`, `worker-ping`, `worker-add`
- **K8s (API):** `k8s-build-load`, `k8s-apply`, `k8s-get`, `k8s-port-api`, `k8s-logs-api`, `k8s-describe-api`, `k8s-restart-api`, `k8s-set-image-api`
- **K8s (Redis + Worker):** `k8s-apply-redis`, `k8s-build-load-worker`, `k8s-apply-worker`, `k8s-logs-worker`, `k8s-exec-worker-ping`, `k8s-exec-worker-add`
- **Ingress:** `k8s-enable-ingress`, `k8s-apply-ingress`, `k8s-delete-ingress`, `k8s-curl-ingress`, `k8s-open-ingress`
- **HPA:** `k8s-enable-metrics`, `k8s-apply-hpa`, `k8s-hpa-status`, `k8s-top`, `load-test`
- **Helm:** `helm-lint`, `helm-template-dev`, `helm-up-dev`, `helm-del`, `helm-diff-dev`, `helm-history`, `helm-rollback`

## Common Commands

### Helm (dev on Minikube)

```bash
make helm-lint
make helm-template-dev
make k8s-enable-ingress
make helm-up-dev
IP=$(minikube ip); curl -s http://api.$IP.nip.io/healthz
```

### Upgrade preview & rollback

```bash
make helm-diff-dev
make helm-history
make helm-rollback REV=<number>
```

## Roadmap (Milestones)

- **M1 (by Oct 09):** Containerized stack (FastAPI + Celery worker + Redis) deployed to Minikube.
  Includes Dockerfiles, base K8s manifests, probes, Ingress, and HPA. ✅ **DONE**
- **M2 (by Oct 14):** Helm chart (dev/prod) with templates, values, and rollback testing. **IN PROGRESS**
- **M3 (by Oct 19):** CI/CD pipeline – build → test → scan → push → deploy via `helm upgrade --install`  
  with automated E2E smoke test after deployment.
- **M4 (by Oct 23):** Observability – Prometheus + Grafana + Alertmanager with 2 alerts (CrashLoop, CPU >80%)  
  and dashboards for RPS, latency, and error rates.
- **M5 (by Oct 31):** Production readiness & release polish – Redis backup/restore script,
  prod configuration, chaos testing, final README (EN) with cost analysis and diagrams.
  📦 **Release v0.1.0**

## What's Next (M3: CI/CD)

- Build & push images (GHCR/DockerHub) with semver tags
- Trivy scan (fail on HIGH/CRITICAL vulnerabilities)
- Deploy job using `helm upgrade --install --atomic`
- E2E smoke test after deployment (curl `/healthz` through Ingress/port-forward)

## Security Notes (WIP)

- Non-root containers, dropped capabilities, healthchecks
- Secrets kept out of git; example manifests provided

## License

MIT
