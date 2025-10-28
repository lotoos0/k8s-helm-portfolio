# Documentation Index

Welcome to the comprehensive documentation for the K8s-Helm-CICD-Portfolio project.

## Table of Contents

### 📘 Getting Started
- **[README](../README.md)** - Project overview, quickstart, and roadmap
- **[Deployment Guide](DEPLOYMENT_GUIDE.md)** - Complete deployment instructions from local to production

### 🏗️ Architecture & Design
- **[Architecture Documentation](ARCHITECTURE.md)** - System architecture, components, data flows, and design principles
- **[API Reference](API_REFERENCE.md)** - Complete API endpoint documentation with examples

### 🔧 Operations

- **[Observability Guide](observability.md)** - Prometheus, Grafana, metrics, dashboards, alerts, runbook
- **[Operations & Chaos Testing](operations/README.md)** - Resilience testing: pod kill, HPA scaling, rollback scenarios
- **[CI/CD Pipeline](CI_CD.md)** - Build, scan, deploy, smoke tests, automatic rollback, secrets management
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Quick reference guide with links to detailed runbooks (336 lines)
- **[Release Checklist](release-checklist.md)** - Pre-deployment and release checklist

> **📖 Understanding Documentation:**
> - **TROUBLESHOOTING.md** - Quick reference, diagnostic commands, common errors → Links to runbooks
> - **runbooks/** - Detailed step-by-step incident response procedures
> - **observability.md** - Complete observability setup and monitoring
> - **operations/README.md** - Chaos engineering and resilience validation
> - **CI_CD.md** - Continuous integration and deployment workflows

### 📚 Runbooks (Step-by-Step Procedures)

**Pod & Container Issues:**
- **[CrashLoopBackOff](runbooks/crashloopbackoff.md)** - Pod continuously restarting
- **[ImagePullBackOff](runbooks/image_pull_backoff.md)** - Cannot pull container image
- **[Pod Not Scheduling](runbooks/pod_not_scheduling.md)** - Pod stuck in Pending state

**Network & Connectivity:**
- **[Ingress Not Working](runbooks/ingress_not_working.md)** - Cannot access via Ingress
- **[Service Unreachable](runbooks/service_unreachable.md)** - Cannot connect to service
- **[kubectl No Route to Host](runbooks/kubectl_no_route_to_host.md)** - kubectl connectivity
- **[NetworkPolicy Not Enforced](runbooks/networkpolicy-not-enforced.md)** - NetworkPolicy not blocking traffic (CNI issues)

**Helm & Deployment:**
- **[Helm Upgrade Failed](runbooks/helm_upgrade_failed.md)** - Helm deployment issues

**Environment & Tools:**
- **[Local vs K8s Development](runbooks/local-vs-k8s-runbook.md)** - Environment comparison
- **[k9s Cheat Sheet](k9s-cheats.md)** - Quick reference for k9s TUI

### 🚀 Release Documentation
- **[Release Artifacts](releases/)** - Historical release snapshots and manifests

---

## Quick Navigation by Role

### 👨‍💻 Developer

**I want to...**
- **Get started quickly**: [README Quickstart](../README.md#quickstart)
- **Run locally with Docker**: [Local Development](DEPLOYMENT_GUIDE.md#local-development)
- **Understand the API**: [API Reference](API_REFERENCE.md)
- **Debug an issue**: [Troubleshooting Guide](TROUBLESHOOTING.md)

**Key Files**:
- [`api/app/main.py`](../api/app/main.py) - FastAPI application
- [`worker/app/tasks.py`](../worker/app/tasks.py) - Celery tasks
- [`Makefile`](../Makefile) - Development commands

### 🚢 DevOps Engineer

**I want to...**
- **Deploy to Kubernetes**: [Kubernetes Deployment](DEPLOYMENT_GUIDE.md#kubernetes-deployment)
- **Deploy with Helm**: [Helm Deployment](DEPLOYMENT_GUIDE.md#helm-deployment)
- **Set up CI/CD**: [CI/CD Deployment](DEPLOYMENT_GUIDE.md#cicd-deployment)
- **Troubleshoot pods**: [Container Issues](TROUBLESHOOTING.md#container-issues)

**Key Files**:
- [`deploy/helm/api/`](../deploy/helm/api/) - Helm chart (SOURCE OF TRUTH)
- [`.github/workflows/`](../.github/workflows/) - CI/CD pipelines
- [`deploy/k8s-examples/`](../deploy/k8s-examples/) - Raw K8s examples (educational)

### 🏗️ Platform Engineer

**I want to...**
- **Understand architecture**: [Architecture Documentation](ARCHITECTURE.md)
- **Review CI/CD pipeline**: [CI/CD Pipeline Guide](CI_CD.md)
- **Plan production deployment**: [Production Deployment](DEPLOYMENT_GUIDE.md#production-deployment)
- **Configure monitoring**: [Observability Guide](observability.md)
- **Test resilience**: [Chaos Testing](operations/README.md)

**Key Files**:
- [`ARCHITECTURE.md`](ARCHITECTURE.md#infrastructure-architecture)
- [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md#production-best-practices)
- [`observability.md`](observability.md) - Prometheus + Grafana setup
- [`CI_CD.md`](CI_CD.md) - Pipeline design and automation

### 🔒 Security Engineer

**I want to...**
- **Review security posture**: [Security Architecture](ARCHITECTURE.md#security-architecture)
- **Check vulnerability scanning**: [CI/CD Security](ARCHITECTURE.md#cicd-architecture)
- **Understand secrets management**: [Secret Management](ARCHITECTURE.md#secret-management)
- **Review network policies**: [NetworkPolicy Runbook](runbooks/networkpolicy-not-enforced.md)

**Key Files**:
- [`.github/workflows/cd.yml`](../.github/workflows/cd.yml) - Trivy scanning
- [`deploy/helm/api/templates/secret.yaml`](../deploy/helm/api/templates/secret.yaml)

### 🎯 SRE (Site Reliability Engineer)

**I want to...**
- **Set up monitoring**: [Observability Guide](observability.md) (Prometheus + Grafana + ServiceMonitor)
- **Configure alerts**: [Observability: Alerts](observability.md#alerts-prometheusrule) (CrashLoopBackOff, High CPU)
- **Perform rollbacks**: [Upgrade & Rollback](DEPLOYMENT_GUIDE.md#upgrade--rollback)
- **Test resilience**: [Chaos Testing](operations/README.md)
- **Troubleshoot incidents**: [Troubleshooting Guide](TROUBLESHOOTING.md)

**Key Files**:
- [`observability.md`](observability.md) - Complete observability setup
- [`operations/README.md`](operations/README.md) - Chaos engineering
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#quick-diagnostics)
- [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md#rollback-process)

---

## Documentation Structure

```
docs/
├── INDEX.md                    # This file - Documentation index
├── ARCHITECTURE.md             # System architecture and design
├── API_REFERENCE.md            # Complete API documentation
├── DEPLOYMENT_GUIDE.md         # Deployment instructions (with production config)
├── SECURITY.md                 # Security implementation guide
├── observability.md            # NEW: Prometheus, Grafana, metrics, alerts
├── CI_CD.md                    # NEW: CI/CD pipeline, secrets, smoke tests
├── TROUBLESHOOTING.md          # Problem-solving guide
├── release-checklist.md        # Pre-deployment checklist
├── k9s-cheats.md              # k9s quick reference
├── REDIS_BACKUP.md             # Redis backup/restore procedures
├── operations/
│   └── README.md               # NEW: Chaos testing and resilience
├── runbooks/                   # Detailed incident response procedures
│   ├── crashloopbackoff.md
│   ├── image_pull_backoff.md
│   ├── ingress_not_working.md
│   ├── helm_upgrade_failed.md
│   └── ...
└── releases/                   # Release snapshots
    └── dev-2025-10-14/
```

**New Documentation (DAY27)**:
- `observability.md` - 500+ lines on monitoring, dashboards, alerts
- `operations/README.md` - 400+ lines on chaos testing (pod kill, HPA, rollback)
- `CI_CD.md` - 500+ lines on CI/CD pipeline, secrets, smoke tests
- Updated `DEPLOYMENT_GUIDE.md` with production configuration details

---

## Common Tasks

### Deploy to Local Minikube

```bash
# 1. Start Minikube
minikube start --cpus=4 --memory=8192

# 2. Enable addons
make k8s-enable-ingress
make k8s-enable-metrics

# 3. Deploy with Helm
make helm-up-dev

# 4. Test
MINIKUBE_IP=$(minikube ip)
curl http://api.$MINIKUBE_IP.nip.io/healthz
```

**Reference**: [Helm Deployment](DEPLOYMENT_GUIDE.md#helm-deployment)

### Run CI/CD Pipeline Locally

```bash
# 1. Lint and test
make lint
make test

# 2. Build and load images
make k8s-build-load
make k8s-build-load-worker

# 3. Deploy
make cd-dev DEV_HOST=api.$(minikube ip).nip.io

# 4. Run smoke tests
make smoke-ci HOST=api.$(minikube ip).nip.io
```

**Reference**: [Local CD Simulation](DEPLOYMENT_GUIDE.md#local-cd-simulation)

### Rollback Failed Deployment

```bash
# 1. Check history
make helm-history

# 2. Rollback
make helm-rollback-last
# Or specific revision:
# make helm-rollback REV=1

# 3. Verify
kubectl -n october rollout status deploy/api
```

**Reference**: [Rollback Process](DEPLOYMENT_GUIDE.md#rollback-process)

### Troubleshoot Pod Issues

```bash
# 1. Check pod status
kubectl -n october get pods

# 2. Describe pod
kubectl -n october describe pod <pod-name>

# 3. Check logs
kubectl -n october logs <pod-name> --tail=100

# 4. Check events
kubectl -n october get events --sort-by='.lastTimestamp'
```

**Reference**: [Container Issues](TROUBLESHOOTING.md#container-issues)

### Test API Endpoints

```bash
# Health check
curl -s http://localhost:8000/healthz

# Readiness
curl -s http://localhost:8000/ready

# Metrics
curl -s http://localhost:8000/metrics | head -20

# Via Ingress
MINIKUBE_IP=$(minikube ip)
curl -s http://api.$MINIKUBE_IP.nip.io/healthz
```

**Reference**: [API Reference](API_REFERENCE.md#endpoints)

---

## Milestone Progress

### ✅ M1: Container & K8s Stack (Oct 09)
- Docker + Compose setup
- Basic K8s manifests
- Health probes, Ingress, HPA
- Redis + Worker deployment

**Documentation**: [Architecture](ARCHITECTURE.md#component-architecture)

### ✅ M2: Helm Charts (Oct 14)
- Helm chart with dev/prod values
- Templates for all resources
- Rollout/rollback procedures

**Documentation**: [Helm Deployment](DEPLOYMENT_GUIDE.md#helm-deployment)

### ✅ M3: CI/CD Pipeline (Oct 19)
- Build, test, scan workflow
- Push to GHCR/DockerHub
- Helm deployment automation
- E2E smoke tests
- Auto-rollback on failure

**Documentation**: [CI/CD Deployment](DEPLOYMENT_GUIDE.md#cicd-deployment)

### ✅ M4: Observability (Oct 23) - COMPLETED
- [x] Prometheus + Grafana (kube-prometheus-stack)
- [x] Metrics dashboards (RPS, latency p95, 5xx rate)
- [x] ServiceMonitor with automatic scraping
- [x] PrometheusRule (CrashLoopBackOff, High CPU alerts)
- [x] Alertmanager configuration (Slack integration)
- [x] Security hardening (Alpine images, -59% reduction)
- [x] NetworkPolicy (default-deny)

**Documentation**:
- [Observability Guide](observability.md)
- [Security Guide](SECURITY.md)
- [Architecture - Observability](ARCHITECTURE.md#observability-architecture)

### ✅ M5: Production Ready (Oct 31) - COMPLETED
- [x] Redis backup/restore scripts
- [x] Production configuration (resources, HA, PDB)
- [x] Chaos testing (pod kill, HPA, rollback)
- [x] Documentation restructure (slim README + comprehensive docs)
- [x] Release v0.1.0

**Documentation**:
- [Operations & Chaos Testing](operations/README.md)
- [CI/CD Pipeline](CI_CD.md)
- [Deployment Guide: Production](DEPLOYMENT_GUIDE.md#production-configuration-details)
- [Redis Backup](REDIS_BACKUP.md)

---

## Contributing to Documentation

### Documentation Standards

- **Format**: Markdown (.md)
- **Structure**: Clear headings, table of contents for long docs
- **Code Examples**: Use fenced code blocks with language tags
- **Commands**: Show both Makefile shortcuts and full commands
- **Cross-references**: Link to related documentation

### Adding New Documentation

1. Create markdown file in `docs/` directory
2. Add to this index under appropriate section
3. Update table of contents
4. Add cross-references from related docs
5. Test all code examples

### Documentation Review Checklist

- [ ] All code examples tested and working
- [ ] Commands use proper syntax highlighting
- [ ] Cross-references are valid links
- [ ] Table of contents is up to date
- [ ] No broken links
- [ ] Follows project documentation style

---

## External Resources

### Kubernetes
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

### Helm
- [Helm Documentation](https://helm.sh/docs/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)

### Docker
- [Docker Documentation](https://docs.docker.com/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best_practices/)

### FastAPI
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [FastAPI Tutorial](https://fastapi.tiangolo.com/tutorial/)

### Prometheus & Grafana
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

### CI/CD
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)

---

## Glossary

| Term | Definition |
|------|------------|
| **HPA** | Horizontal Pod Autoscaler - Automatically scales pods based on metrics |
| **PVC** | PersistentVolumeClaim - Request for storage in Kubernetes |
| **GHCR** | GitHub Container Registry - GitHub's Docker image registry |
| **Ingress** | K8s resource for HTTP routing to services |
| **Helm** | Package manager for Kubernetes |
| **nip.io** | Wildcard DNS service for local development |
| **Minikube** | Local Kubernetes cluster for development |
| **k9s** | Terminal UI for managing Kubernetes clusters |
| **Celery** | Distributed task queue for Python |
| **Redis** | In-memory data store used as message broker |
| **Trivy** | Security vulnerability scanner |
| **Atomic Deployment** | Helm deployment that auto-rolls back on failure |

---

**Documentation Version**: 2.0
**Last Updated**: 2025-10-27
**Project Version**: 0.1.0 (M5 Complete - Production Ready)

---

## Need Help?

- **Documentation Issues**: Create an issue in the GitHub repository
- **Questions**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
- **Contributions**: See [Contributing to Documentation](#contributing-to-documentation)
