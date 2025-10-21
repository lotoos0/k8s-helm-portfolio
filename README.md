# October DevOps – K8s + Helm + CI/CD + Observability

[![Milestone](https://img.shields.io/badge/Milestone-M3%20Complete-success)](docs/INDEX.md)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](docs/ARCHITECTURE.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-comprehensive-brightgreen)](docs/INDEX.md)
![progress](https://img.shields.io/badge/Project_Progress-65%25-brightgreen)
A production-grade two-service demo (FastAPI **API** + Celery **worker** with Redis) showcasing modern DevOps practices:

- 🐳 **Docker & Compose** – Containerized microservices
- ☸️ **Kubernetes** – Production-ready orchestration (manifests → Helm)
- 🚀 **CI/CD** – Automated build → test → scan → deploy with E2E smoke tests
- 📊 **Observability** – Prometheus + Grafana + ServiceMonitor + PrometheusRule

---

## 📚 Documentation

**[📍 START HERE: Complete Documentation Index](docs/INDEX.md)**

| Document                                              | Description                                                       |
| ----------------------------------------------------- | ----------------------------------------------------------------- |
| **[🏗️ Architecture](docs/ARCHITECTURE.md)**           | System design, components, CI/CD pipeline, data flows             |
| **[🔌 API Reference](docs/API_REFERENCE.md)**         | Complete API docs with code examples (Python, cURL, JS, Go)       |
| **[🚀 Deployment Guide](docs/DEPLOYMENT_GUIDE.md)**   | Step-by-step deployment: Docker → K8s → Helm → CI/CD → Production |
| **[🔧 Troubleshooting](docs/TROUBLESHOOTING.md)**     | Problem-solving guide with quick diagnostics                      |
| **[✅ Release Checklist](docs/release-checklist.md)** | Pre-deployment verification                                       |

**Total Documentation**: 3,359+ lines covering architecture, deployment, operations, and troubleshooting.

---

## ✨ Key Features

### 🐳 Containerization

- Multi-stage Docker builds for optimal image size
- Docker Compose for local development stack
- Image security scanning with Trivy (fail on HIGH/CRITICAL)

### ☸️ Kubernetes & Helm

- Production-ready Helm chart with dev/prod values
- Health probes (startup, liveness, readiness)
- Horizontal Pod Autoscaler (HPA) for automatic scaling
- Ingress with NGINX for HTTP routing
- PersistentVolumeClaims for Redis data

### 🚀 CI/CD Pipeline

- Automated build, test, and deployment
- Multi-registry support (GHCR + DockerHub)
- Security scanning at every stage
- E2E smoke tests post-deployment
- **Automatic rollback on failure**

### 📊 Observability

- **Prometheus** metrics (`http_requests_total`, `http_request_duration_seconds`)
- **Grafana** dashboards (RPS, latency p95, 5xx rate)
- **ServiceMonitor** for automatic metrics scraping
- **PrometheusRule** alerts (CrashLoopBackOff, High CPU)
- Health check endpoints (`/healthz`, `/ready`)

### 🔒 Security (M4)

- Secret management with Kubernetes Secrets
- Planned: NetworkPolicy for pod isolation
- Planned: Non-root containers, read-only filesystem

---

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

**📐 For detailed architecture documentation**: [Architecture Guide](docs/ARCHITECTURE.md)

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

> **💡 Tip**: For detailed deployment instructions, see the [Deployment Guide](docs/DEPLOYMENT_GUIDE.md)

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

---

## 📊 Monitoring (Prometheus + Grafana)

### Setup kube-prometheus-stack

```bash
# Install Prometheus, Grafana, Alertmanager
make mon-install

# Check status
make mon-status
```

### Access Dashboards

```bash
# Grafana (http://localhost:3000)
make mon-pf-grafana

# Get admin password
make mon-grafana-pass

# Prometheus (http://localhost:9090)
make mon-pf-prom
```

**Default credentials**: `admin` / (use `make mon-grafana-pass`)

### Metrics Available

The API exposes Prometheus metrics at `/metrics`:

- **`http_requests_total`** - Counter with labels: `method`, `path`, `status`
- **`http_request_duration_seconds`** - Histogram with buckets for latency

**ServiceMonitor** automatically scrapes metrics (configured in `values.yaml`):

```yaml
serviceMonitor:
  enabled: true
  interval: 15s
  additionalLabels:
    release: mon # Required for Prometheus Operator selector
```

### Grafana Dashboards

Import dashboard with these PromQL queries:

**1. RPS by Status:**

```promql
sum by (status) (rate(http_requests_total{namespace="october"}[$__rate_interval]))
```

**2. Latency p95:**

```promql
1000 * histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{namespace="october"}[$__rate_interval]))
)
```

**3. 5xx Error Rate:**

```promql
sum(rate(http_requests_total{namespace="october", status=~"5.."}[$__rate_interval]))
```

### Alerts (PrometheusRule)

Configured alerts (toggleable via `values.yaml`):

```yaml
alerts:
  enabled: true
  release: "mon"
```

**Active alerts:**

- **CrashLoopBackOffPods** - Pod in CrashLoopBackOff >5m (severity: warning)
- **HighCPUApi** - API CPU >80% of requests for 5m (severity: warning)

View alerts: http://localhost:9090/alerts (after `make mon-pf-prom`)

### Troubleshooting

**No metrics in Grafana?**

1. Check ServiceMonitor has `release: mon` label
2. Verify Prometheus targets show API as UP: http://localhost:9090/targets
3. Generate traffic: `curl http://localhost:8080/healthz`
4. Check `/metrics` endpoint directly

**Dashboard shows "No data"?**

- Ensure namespace variable is set to `october`
- Verify time range includes recent data
- Check Prometheus data source is configured

````

---

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
````

### CD to Dev (GitHub Actions)

Secrets required:

- `DEV_KUBECONFIG` – kubeconfig for dev cluster
- `DEV_NAMESPACE` – e.g., october
- `DEV_INGRESS_HOST` – e.g., api.<minikube-ip>.nip.io

Deploy runs on push to `main`:

- Lint → Template → Helm upgrade --install (images from GHCR `:dev` by default).

**Local CD:**

```bash
make cd-dev DEV_HOST=api.$(minikube ip).nip.io
```

### E2E Smoke (CI Gate)

- After CD (atomic), CI runs `scripts/smoke.sh` against `${DEV_INGRESS_HOST}`.
- On failure: diagnostics (kubectl/helm dumps) are uploaded, then auto-rollback to previous revision.
- Local:
  ```bash
  IP=$(minikube ip)
  make smoke-ci HOST=api.$IP.nip.io
  # or fallback
  make smoke-pf
  ```

## Health & Probes

- **/healthz** → liveness (process alive)
- **/ready** → readiness (accepts traffic)
- **/metrics** → Prometheus exposition format

K8s probes:

- `startupProbe`: /healthz (gives the app warmup time)
- `readinessProbe`: /ready
- `livenessProbe`: /healthz

**📖 For complete API documentation**: [API Reference](docs/API_REFERENCE.md)

## Make targets

Run `make help` for a list. Highlights:

- **Dev:** `install`, `lint`, `fmt`, `test`
- **Docker:** `build-api`, `run-api-docker`, `stop-api`
- **Compose:** `compose-up|logs|down`, `worker-ping`, `worker-add`
- **K8s (API):** `k8s-build-load`, `k8s-apply`, `k8s-get`, `k8s-port-api`, `k8s-logs-api`, `k8s-describe-api`, `k8s-restart-api`, `k8s-set-image-api`
- **K8s (Redis + Worker):** `k8s-apply-redis`, `k8s-build-load-worker`, `k8s-apply-worker`, `k8s-logs-worker`, `k8s-exec-worker-ping`, `k8s-exec-worker-add`
- **Ingress:** `k8s-enable-ingress`, `k8s-apply-ingress`, `k8s-delete-ingress`, `k8s-curl-ingress`, `k8s-open-ingress`
- **HPA:** `k8s-enable-metrics`, `k8s-apply-hpa`, `k8s-hpa-status`, `k8s-top`, `load-test`
- **Helm:** `helm-lint`, `helm-template-dev`, `helm-up-dev`, `helm-del`, `helm-diff-dev`, `helm-history`, `helm-rollback`, `helm-up-dev-atomic`, `helm-rollback-last`
- **CD/Smoke:** `cd-dev`, `cd-dev-atomic`, `smoke-ci`, `smoke-pf`

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

**📊 [Track Progress in Documentation Index](docs/INDEX.md#milestone-progress)**

- **M1 (by Oct 09):** Containerized stack (FastAPI + Celery worker + Redis) deployed to Minikube.
  Includes Dockerfiles, base K8s manifests, probes, Ingress, and HPA. ✅ **DONE**
- **M2 (by Oct 14):** Helm chart (dev/prod) with templates, values, and rollback testing. ✅ **DONE**
- **M3 (by Oct 19):** CI/CD pipeline – build → test → scan → push → deploy via `helm upgrade --install`
  with automated E2E smoke test after deployment. ✅ **DONE**
  - **📚 Complete documentation suite** (3,359+ lines) ✅ **DONE**
- **M4 (by Oct 23):** Observability – Prometheus + Grafana + Alertmanager with 2 alerts (CrashLoop, CPU >80%)
  and dashboards for RPS, latency, and error rates. 🚧 **IN PROGRESS**
- **M5 (by Oct 31):** Production readiness & release polish – Redis backup/restore script,
  prod configuration, chaos testing, final README (EN) with cost analysis and diagrams.
  📦 **Release v0.1.0**

## What's Next (M4: Observability + Security)

- **DAY20:** Set up Prometheus + Grafana stack, configure scraping for `/metrics`, create dashboards (RPS, p95, 5xx)
- **DAY21:** Configure Alertmanager with 2 alerts: CrashLoopBackOff >5m, CPU >80% for 5m
- **DAY22:** Security hardening – SecurityContext (non-root, read-only filesystem), NetworkPolicy (API↔Redis isolation)
- **DAY23:** Minimal base images (alpine/distroless), update README "Security Notes" section

## Security Notes (WIP)

- Non-root containers, dropped capabilities, healthchecks
- Secrets kept out of git; example manifests provided
- **Full Security Guide**: Coming in M4 ([Architecture - Security](docs/ARCHITECTURE.md#security-architecture))

---

## Need Help?

- **📖 Browse Documentation**: [Complete Documentation Index](docs/INDEX.md)
- **🔧 Troubleshooting**: [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- **🚀 Deployment Issues**: [Deployment Guide - Troubleshooting](docs/DEPLOYMENT_GUIDE.md#troubleshooting)
- **💬 Ask Questions**: Open an issue with `[QUESTION]` label
- **🐛 Report Bugs**: Open an issue with `[BUG]` label
- **📝 Documentation Feedback**: Open an issue with `[DOCS]` label

**Quick Diagnostics**:

```bash
# Run comprehensive system check
./docs/quick-diag.sh > diagnostics.txt

# Check specific components
kubectl -n october get all
helm list -n october
make k8s-get
```

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit with milestone tags (`git commit -m "[DAY20] Add feature"`)
4. Push and open a Pull Request

See [Documentation Index](docs/INDEX.md) for contribution guidelines.

---

## License

MIT
