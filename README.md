# October DevOps – K8s + Helm + CI/CD + Observability

[![Milestone](https://img.shields.io/badge/Milestone-M5%20Complete-success)](docs/INDEX.md)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/lotoos0/k8s-helm-cicd-portfolio/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![progress](https://img.shields.io/badge/Project_Progress-100%25-purple)

**FastAPI API + Celery Worker + Redis** — production-grade mini-stack with Helm (dev/prod), CI/CD (build→scan→deploy→smoke), Prometheus+Grafana, `helm --atomic` rollback, and security hardening (non-root, ROFS, NetworkPolicy).

### Highlights

- **Multi-stage Docker** (Alpine) + Trivy gate → **-59% image size** (245MB→100MB API)
- **Helm chart** with dev/prod values, HPA, Ingress
- **Observability**: ServiceMonitor, dashboards, 2 alerts (CrashLoop, CPU >80%)
- **Security**: non-root, ROFS, NetworkPolicy default-deny, PDB
- **Chaos validated**: Pod kill, HPA scaling, atomic rollback

---

## Quickstart

### Local (Compose)

```bash
make compose-up
make worker-ping && make worker-add
make compose-down
```

### Minikube + Helm (dev)

```bash
minikube start && make k8s-enable-ingress
IP=$(minikube ip)
helm upgrade --install app deploy/helm/api -n october --create-namespace \
  -f deploy/helm/api/values.yaml -f deploy/helm/api/values-dev.yaml \
  --set api.ingress.host=api.$IP.nip.io \
  --atomic --timeout 5m
curl -s http://api.$IP.nip.io/healthz
```

**Or use Makefile**:

```bash
make helm-up-dev
```

---

## Architecture

```
Client ──HTTP──► Ingress (NGINX) ──► Service api ──► Deployment API (FastAPI + /metrics)
                                          │
                                          │ Celery (broker/backend)
                                          ▼
                                   Service redis ──► Deployment Worker (Celery)
                                          │
                                          ▼
                                       PVC/data
```

**📐 For detailed architecture**: [Architecture Guide](docs/ARCHITECTURE.md)

---

## Documentation

**[📍 START HERE: Complete Documentation Index](docs/INDEX.md)**

| Document                                                       | Description                                                 |
| -------------------------------------------------------------- | ----------------------------------------------------------- |
| **[🏗️ Architecture](docs/ARCHITECTURE.md)**                    | System design, components, CI/CD pipeline, data flows       |
| **[🚀 Deployment Guide](docs/DEPLOYMENT_GUIDE.md)**            | Step-by-step deployment: Docker → K8s → Helm → Production   |
| **[🔌 API Reference](docs/API_REFERENCE.md)**                  | Complete API docs with code examples (Python, cURL, JS, Go) |
| **[🔒 Security Guide](docs/SECURITY.md)**                      | Security implementation, NetworkPolicy, secrets management  |
| **[📊 Observability](docs/observability.md)**                  | Prometheus, Grafana, metrics, dashboards, alerts            |
| **[🛠️ Operations & Chaos Testing](docs/operations/README.md)** | Resilience testing, pod kill, HPA, rollback scenarios       |
| **[🔁 CI/CD Pipeline](docs/CI_CD.md)**                         | Build, scan, deploy, smoke tests, automatic rollback        |
| **[🔧 Troubleshooting](docs/TROUBLESHOOTING.md)**              | Problem-solving guide with quick diagnostics                |

**Total Documentation**: 4,500+ lines covering architecture, deployment, operations, observability, and security.

---

## What's Inside

| Area                | Content                                                               |
| ------------------- | --------------------------------------------------------------------- |
| **Container**       | Multi-stage Docker (Alpine), Trivy scans in CI, -59% image reduction  |
| **Kubernetes/Helm** | Dev/Prod values, Ingress, HPA, Redis PVC, health probes               |
| **CI/CD**           | Build → Scan → Deploy (Helm) → E2E Smoke → Rollback on failure        |
| **Observability**   | ServiceMonitor, Grafana dashboards (RPS, p95, 5xx), 2 PrometheusRules |
| **Security**        | non-root (UID 10001), ROFS + /tmp, NetworkPolicy default-deny, PDB    |
| **Resilience**      | Pod kill (self-healing), CPU burn (HPA), broken image (rollback)      |

---

## Key Features

### Containerization 🐳

- Multi-stage Docker builds with Alpine Linux 3.20
- **API**: 99.8MB (was 245MB) → **-59.3%**
- **Worker**: 88MB (was 169MB) → **-47.9%**
- Trivy security scanning (fail on HIGH/CRITICAL)

### Kubernetes & Helm ☸️

- Production-ready Helm chart with dev/prod values
- Health probes (startup, liveness, readiness)
- HPA for automatic scaling (1→5 replicas @ 60% CPU)
- Ingress with NGINX for HTTP routing
- PersistentVolumeClaims for Redis data

### CI/CD Pipeline 🚀

- Automated build, test, and deployment
- Multi-registry support (GHCR + DockerHub)
- Security scanning at every stage (Trivy)
- E2E smoke tests post-deployment
- **Automatic rollback on failure** (`helm --atomic`)

### Observability 📊

- **Prometheus** metrics: `http_requests_total`, `http_request_duration_seconds`
- **Grafana** dashboards: RPS, latency p95, 5xx rate
- **ServiceMonitor** for automatic metrics scraping
- **PrometheusRule** alerts: CrashLoopBackOff, High CPU (>80% for 5m)
- Health check endpoints: `/healthz`, `/ready`, `/metrics`

**Setup**:

```bash
make mon-install   # Install kube-prometheus-stack
make mon-pf-grafana  # Access Grafana (http://localhost:3000)
make mon-grafana-pass  # Get admin password
```

**📖 Full Observability Guide**: [docs/observability.md](docs/observability.md)

### Security & Networking 🔒

- Containers run as **non-root** (UID 10001)
- **ReadOnlyRootFilesystem** with writable `/tmp` emptyDir
- **NetworkPolicy**: default-deny with explicit allow rules:
  - Ingress from NGINX → API (port 8000)
  - Egress API/Worker → Redis:6379
  - Egress all → kube-dns (TCP/UDP 53)
- **PodDisruptionBudget**: API (66% minAvailable), Worker (50% minAvailable)
- **Image Scanning**: Trivy in CI/CD (fail on HIGH/CRITICAL)

**Verification**:

```bash
kubectl -n october get pdb,networkpolicy
make sec-test
```

**📖 Full Security Guide**: [docs/SECURITY.md](docs/SECURITY.md)

### Chaos Testing & Resilience 🔥

- **Pod Kill**: Self-healing in 5-10s, zero downtime
- **HPA Scaling**: 1→3 replicas in ~60s, handles 3x traffic
- **Atomic Rollback**: Auto-rollback on broken deployments (ImagePullBackOff, CrashLoopBackOff)

**🎯 Resilience Score: 95%** (validated through chaos testing)

**📖 Full Chaos Testing Guide**: [docs/operations/README.md](docs/operations/README.md)

---

## Roadmap (Milestones)

- **M1 (Oct 09)**: Containerized stack (FastAPI + Celery + Redis) on Minikube ✅ **DONE**
- **M2 (Oct 14)**: Helm chart (dev/prod) with templates and rollback ✅ **DONE**
- **M3 (Oct 19)**: CI/CD pipeline – build → scan → deploy + E2E smoke ✅ **DONE**
- **M4 (Oct 23)**: Observability – Prometheus + Grafana + Alertmanager, security hardening ✅ **DONE**
- **M5 (Oct 31)**: Production readiness – Redis backup, prod config, chaos testing, docs polish ✅ **DONE**

📦 **Release v0.1.0** – Production-ready K8s platform with comprehensive DevOps automation

---

## Make Targets

Run `make help` for full list. Key targets:

### Setup & Development

```bash
make install         # Install dependencies
make run-api         # Run FastAPI locally
make lint            # Lint code
make test            # Run tests
```

### Docker

```bash
make build-api       # Build API image
make build-worker    # Build worker image
make compose-up      # Start full stack
make compose-down    # Stop stack
```

### Kubernetes (Minikube)

```bash
make k8s-build-load      # Build & load images
make k8s-apply           # Apply K8s manifests
make k8s-port-api        # Port-forward API (:8080)
make k8s-enable-ingress  # Enable NGINX Ingress
```

### Helm

```bash
make helm-lint           # Lint chart
make helm-template-dev   # Preview templates
make helm-up-dev         # Deploy dev
make helm-up-dev-atomic  # Deploy with auto-rollback
make helm-history        # View revisions
make helm-rollback REV=N # Rollback to revision
```

### Monitoring

```bash
make mon-install         # Install Prometheus + Grafana
make mon-pf-grafana      # Access Grafana (:3000)
make mon-pf-prom         # Access Prometheus (:9090)
make mon-fire-crash      # Test CrashLoop alert
make mon-fire-cpu        # Test High CPU alert
```

### CI/CD & Testing

```bash
make cd-dev              # Local CD simulation
make smoke-ci HOST=...   # Run smoke tests
make load-test URL=...   # Load testing (HPA)
```

---

## Repo Layout

```
api/                     # FastAPI app (+ tests, lint)
worker/                  # Celery tasks
deploy/
  helm/
    api/                 # <── SOURCE OF TRUTH (Helm chart)
  k8s-examples/          # Raw K8s manifests (educational only)
scripts/                 # Tools (load tester, smoke tests)
docs/                    # Comprehensive documentation
.github/workflows/       # CI/CD pipelines
docker-compose.yml
Makefile
```

> **Note**: `deploy/k8s-examples/` contains raw K8s manifests for educational reference only. Always use Helm for deployments.

---

## Development Approach

This project demonstrates modern DevOps workflow combining hands-on infrastructure work with AI-assisted tooling:

**Human-driven** (manual implementation):

- ✅ All infrastructure code (K8s manifests, Helm charts, NetworkPolicies, PDBs)
- ✅ Shell scripts (backup/restore, smoke tests, deployment automation)
- ✅ CI/CD pipeline design and GitHub Actions workflows
- ✅ Docker multi-stage builds and security hardening
- ✅ Architecture decisions, troubleshooting, and testing
- ✅ Prometheus metrics instrumentation and Grafana dashboards

**AI-assisted** (Claude Code for productivity):

- 📝 Documentation writing and formatting
- 🔍 Code review and best practices suggestions
- 🐛 Debugging assistance and error analysis

---

## Need Help?

- **📖 Browse Documentation**: [Complete Documentation Index](docs/INDEX.md)
- **🔧 Troubleshooting**: [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- **🚀 Deployment Issues**: [Deployment Guide - Troubleshooting](docs/DEPLOYMENT_GUIDE.md#troubleshooting)
- **💬 Ask Questions**: Open an issue with `[QUESTION]` label
- **🐛 Report Bugs**: Open an issue with `[BUG]` label

**Quick Diagnostics**:

```bash
# Check system status
kubectl -n october get all
helm list -n october
make k8s-get
```

---

> Status: Completed / Archived — This project is finished and no longer actively maintained.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**🎉 Project Complete** – 28-day journey from zero to production-ready Kubernetes platform

**Tech Stack**: FastAPI • Celery • Redis • Docker • Kubernetes • Helm • Prometheus • Grafana • GitHub Actions • Trivy

**Skills Demonstrated**: Container orchestration • GitOps • Observability • Security hardening • CI/CD automation • Chaos engineering • Infrastructure as Code
