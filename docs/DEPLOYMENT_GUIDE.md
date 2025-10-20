# Deployment Guide

## Table of Contents
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Local Development](#local-development)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Helm Deployment](#helm-deployment)
- [CI/CD Deployment](#cicd-deployment)
- [Production Deployment](#production-deployment)
- [Upgrade & Rollback](#upgrade--rollback)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| Docker | 24.0+ | Container runtime | [Install Docker](https://docs.docker.com/get-docker/) |
| Kubernetes | 1.28+ | Container orchestration | Included with Minikube |
| Minikube | 1.32+ | Local K8s cluster | [Install Minikube](https://minikube.sigs.k8s.io/docs/start/) |
| kubectl | 1.28+ | K8s CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| Helm | 3.14+ | K8s package manager | [Install Helm](https://helm.sh/docs/intro/install/) |
| k9s | 0.30+ (optional) | K8s TUI | [Install k9s](https://k9scli.io/topics/install/) |
| Python | 3.11+ | Development | [Install Python](https://www.python.org/downloads/) |

### System Requirements

**Development Environment**:
- CPU: 4 cores (recommended)
- RAM: 8GB minimum, 16GB recommended
- Disk: 20GB free space
- OS: Linux, macOS, Windows (WSL2)

**Minikube Configuration**:
```bash
minikube start --cpus=4 --memory=8192 --disk-size=20g
```

### Network Requirements

- Ports:
  - `8000`: API (Docker local)
  - `8080`: API (K8s port-forward)
  - `6379`: Redis (internal only)
- Ingress access requires Minikube tunnel or nip.io DNS

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/<your-username>/k8s-helm-cicd-portfolio.git
cd k8s-helm-cicd-portfolio
```

### 2. Install Development Dependencies

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# Install dependencies
make install  # or: pip install -r api/requirements.txt
```

### 3. Verify Installation

```bash
# Check versions
docker --version
kubectl version --client
helm version
minikube version

# Check Makefile targets
make help
```

## Local Development

### Docker Standalone

**1. Build Image**:
```bash
make build-api
# Equivalent to:
# docker build -t october-api:dev ./api
```

**2. Run Container**:
```bash
make run-api-docker
# Equivalent to:
# docker run -d --name october-api -p 8000:8000 october-api:dev
```

**3. Test Endpoints**:
```bash
curl -s http://localhost:8000/healthz
curl -s http://localhost:8000/ready
curl -s http://localhost:8000/metrics | head -20
```

**4. View Logs**:
```bash
docker logs -f october-api
```

**5. Stop Container**:
```bash
make stop-api
# Equivalent to:
# docker stop october-api && docker rm october-api
```

### Docker Compose (Full Stack)

**1. Start Stack**:
```bash
make compose-up
# Starts: api + redis + worker
```

**2. View Logs**:
```bash
make compose-logs
# Or specific service:
# docker-compose logs -f api
# docker-compose logs -f worker
```

**3. Test Celery Tasks**:
```bash
# Enqueue ping task
make worker-ping

# Enqueue add(1, 2) task
make worker-add
```

**4. Check Worker Logs**:
```bash
docker-compose logs worker
# Should show: "Task ping[...] succeeded in 0.001s: 'pong'"
```

**5. Stop Stack**:
```bash
make compose-down
```

### Local Testing

```bash
# Lint code
make lint  # ruff + black

# Run tests
make test  # pytest with coverage

# Format code
make fmt   # black auto-format
```

## Kubernetes Deployment

### 1. Start Minikube

```bash
# Start cluster
minikube start --cpus=4 --memory=8192

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### 2. Deploy API

**Build and Load Image**:
```bash
# Build image and load into Minikube
make k8s-build-load

# Equivalent to:
# docker build -t october-api:dev ./api
# minikube image load october-api:dev
```

**Deploy Resources**:
```bash
# Create namespace + deployment + service
make k8s-apply

# Equivalent to:
# kubectl apply -f deploy/k8s-examples/ns.yaml
# kubectl apply -f deploy/k8s-examples/deployment-api.yaml
# kubectl apply -f deploy/k8s-examples/service-api.yaml
```

**Verify Deployment**:
```bash
make k8s-get
# Or:
# kubectl -n october get deploy,pod,svc
```

### 3. Deploy Redis

```bash
# Deploy PVC + Redis deployment + service
make k8s-apply-redis

# Verify
kubectl -n october get pvc,deploy,svc -l app=redis
```

### 4. Deploy Worker

```bash
# Build and load worker image
make k8s-build-load-worker

# Deploy worker
make k8s-apply-worker

# Check logs
make k8s-logs-worker
```

### 5. Access API

**Option A: Port Forward**:
```bash
# Forward port 8080 → service:80
make k8s-port-api

# Test (in another terminal)
curl -s http://localhost:8080/healthz
```

**Option B: Ingress** (recommended):
```bash
# Enable NGINX Ingress Controller (one-time)
make k8s-enable-ingress

# Deploy Ingress resource
make k8s-apply-ingress

# Get Minikube IP
minikube ip
# Example: 192.168.49.2

# Test
MINIKUBE_IP=$(minikube ip)
curl -s http://api.$MINIKUBE_IP.nip.io/healthz

# Or use Makefile:
make k8s-curl-ingress
```

### 6. Enable HPA (Optional)

```bash
# Enable metrics-server (one-time)
make k8s-enable-metrics

# Deploy HPA
make k8s-apply-hpa

# Watch HPA status
kubectl -n october get hpa api -w

# Generate load
MINIKUBE_IP=$(minikube ip)
make load-test URL=http://api.$MINIKUBE_IP.nip.io/healthz CONC=200 DUR=120

# Observe scaling
make k8s-top
```

### 7. Test Celery Tasks

```bash
# Enqueue ping task
make k8s-exec-worker-ping

# Enqueue add task
make k8s-exec-worker-add

# Check worker logs
make k8s-logs-worker
```

## Helm Deployment

### Why Use Helm?

✅ **Use Helm for**:
- Production deployments
- Environment-specific configurations (dev/prod)
- Atomic deployments with rollback
- Version-controlled releases

❌ **Do NOT use raw K8s manifests**:
- Raw manifests (`deploy/k8s-examples/`) are for learning only
- Helm provides better deployment management

### 1. Lint Chart

```bash
make helm-lint
# Checks:
# - Chart.yaml validity
# - Template syntax
# - Values schema
```

### 2. Preview Rendered Templates

```bash
# Preview dev configuration
make helm-template-dev

# Preview prod configuration
make helm-template-prod
```

### 3. Deploy to Dev

**Prerequisites**:
```bash
# Build and load images into Minikube
make k8s-build-load
make k8s-build-load-worker

# Enable Ingress Controller
make k8s-enable-ingress
```

**Install/Upgrade**:
```bash
# Deploy with values-dev.yaml
make helm-up-dev

# Equivalent to:
# helm upgrade --install app deploy/helm/api \
#   -n october --create-namespace \
#   -f deploy/helm/api/values.yaml \
#   -f deploy/helm/api/values-dev.yaml \
#   --set api.ingress.host=api.$(minikube ip).nip.io
```

**Verify**:
```bash
# Check release status
helm list -n october

# Check resources
kubectl -n october get all

# Test endpoints
MINIKUBE_IP=$(minikube ip)
curl -s http://api.$MINIKUBE_IP.nip.io/healthz
```

### 4. Deploy to Prod (Simulation)

**Update Image Tags** in `values-prod.yaml`:
```yaml
api:
  image:
    repository: ghcr.io/<username>/october-api
    tag: v0.1.0  # Use specific version, NOT :dev

worker:
  image:
    repository: ghcr.io/<username>/october-worker
    tag: v0.1.0
```

**Preview Changes**:
```bash
make helm-diff-prod
# Shows what will change
```

**Deploy**:
```bash
make helm-up-prod
# Uses values-prod.yaml with production settings:
# - Higher replicas (2+)
# - Resource limits
# - HPA enabled
# - Production ingress host
```

### 5. Atomic Deployment (Recommended)

```bash
# Deploy with automatic rollback on failure
make helm-up-dev-atomic

# Equivalent to:
# helm upgrade --install app deploy/helm/api \
#   --atomic --timeout 5m \
#   -n october --create-namespace \
#   -f deploy/helm/api/values.yaml \
#   -f deploy/helm/api/values-dev.yaml
```

Benefits:
- Waits for all pods to be ready
- Automatically rolls back if deployment fails
- Timeout protection (5 minutes)

## CI/CD Deployment

### GitHub Actions Setup

**1. Required Secrets**:

Navigate to: `Settings → Secrets and variables → Actions`

| Secret | Description | Example |
|--------|-------------|---------|
| `GHCR_USERNAME` | GitHub username | `octocat` |
| `GHCR_TOKEN` | GitHub PAT with `write:packages` | `ghp_xxx...` |
| `DOCKERHUB_USERNAME` | DockerHub username | `octocat` |
| `DOCKERHUB_TOKEN` | DockerHub access token | `dckr_pat_xxx...` |
| `DEV_KUBECONFIG` | Base64-encoded kubeconfig | `apiVersion: v1...` |
| `DEV_NAMESPACE` | K8s namespace | `october` |
| `DEV_INGRESS_HOST` | Ingress hostname | `api.dev.example.com` |

**2. Generate Kubeconfig**:

For Minikube:
```bash
# Get kubeconfig
kubectl config view --flatten --minify > kubeconfig

# Base64 encode
cat kubeconfig | base64 -w 0

# Add to GitHub Secrets as DEV_KUBECONFIG
```

**3. Trigger CI Pipeline**:

```bash
# CI runs on PR and push to main/develop
git checkout -b feature/new-feature
# Make changes...
git add .
git commit -m "[DAY20] Add new feature"
git push origin feature/new-feature

# Open PR on GitHub
# CI will run: lint → test → build → push to GHCR
```

**4. Trigger CD Pipeline**:

```bash
# CD runs after successful CI on main/develop
git checkout main
git merge feature/new-feature
git push origin main

# CD will run:
# 1. Trivy security scan
# 2. Helm lint + template
# 3. Helm upgrade --install --atomic
# 4. E2E smoke test
# 5. Auto-rollback on failure
```

### Local CD Simulation

```bash
# Simulate CD pipeline locally
make cd-dev DEV_HOST=api.$(minikube ip).nip.io

# Runs:
# - Trivy scan
# - Helm upgrade --atomic
# - Smoke test
```

## Production Deployment

### Pre-Deployment Checklist

- [ ] All images tagged with semantic version (`:v0.1.0`)
- [ ] Images scanned with Trivy (no HIGH/CRITICAL vulnerabilities)
- [ ] `values-prod.yaml` reviewed and updated
- [ ] Resource limits configured appropriately
- [ ] Ingress host points to production domain
- [ ] Secrets created in production namespace
- [ ] Database/Redis backups verified
- [ ] Monitoring and alerts configured
- [ ] Runbooks updated

### Production Best Practices

**1. Use Immutable Image Tags**:
```yaml
# ❌ BAD: Mutable tag
image:
  tag: dev

# ✅ GOOD: Immutable tag
image:
  tag: v0.1.0  # or sha-a1b2c3d
```

**2. Configure Resource Limits**:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**3. Enable HPA**:
```yaml
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

**4. Use Atomic Deployments**:
```bash
helm upgrade --install app deploy/helm/api \
  --atomic --timeout 10m \
  -n production --create-namespace \
  -f deploy/helm/api/values-prod.yaml
```

### Production Deployment Steps

**1. Tag Release**:
```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
# CI builds images with :v0.1.0 tag
```

**2. Update values-prod.yaml**:
```yaml
api:
  image:
    tag: v0.1.0
  replicas: 2
  ingress:
    host: api.example.com

worker:
  image:
    tag: v0.1.0
  replicas: 2
```

**3. Preview Changes**:
```bash
helm diff upgrade app deploy/helm/api \
  -n production \
  -f deploy/helm/api/values-prod.yaml
```

**4. Deploy**:
```bash
helm upgrade --install app deploy/helm/api \
  --atomic --timeout 10m \
  -n production --create-namespace \
  -f deploy/helm/api/values-prod.yaml
```

**5. Monitor Rollout**:
```bash
# Watch deployment status
kubectl -n production rollout status deploy/api

# Check pod status
kubectl -n production get pods -w

# View release history
helm history app -n production
```

**6. Smoke Test**:
```bash
./scripts/smoke.sh api.example.com
```

**7. Monitor Metrics**:
- Check Grafana dashboards (M4)
- Verify error rates < 1%
- Confirm latency p99 < 500ms

## Upgrade & Rollback

### Upgrade Process

**1. Preview Changes**:
```bash
# Show what will change
make helm-diff-dev
```

**2. Upgrade with Atomic Flag**:
```bash
# Automatically rollback on failure
make helm-up-dev-atomic
```

**3. Monitor Upgrade**:
```bash
# Watch deployment
kubectl -n october rollout status deploy/api

# Check pod status
kubectl -n october get pods -l app=api -w
```

**4. Verify Health**:
```bash
# Check all pods are ready
kubectl -n october get deploy api

# Test endpoints
MINIKUBE_IP=$(minikube ip)
curl -s http://api.$MINIKUBE_IP.nip.io/healthz
```

### Rollback Process

**1. View Release History**:
```bash
make helm-history
# Or:
# helm history app -n october
```

Output:
```
REVISION  UPDATED                   STATUS      CHART      APP VERSION  DESCRIPTION
1         Mon Oct 14 10:00:00 2025  superseded  app-0.1.0  0.1.0        Install complete
2         Mon Oct 14 12:00:00 2025  deployed    app-0.1.0  0.1.0        Upgrade complete
```

**2. Rollback to Previous**:
```bash
# Rollback to immediately previous revision
make helm-rollback-last

# Equivalent to:
# REV=$(helm history app -n october --output json | jq '.[1].revision')
# helm rollback app $REV -n october
```

**3. Rollback to Specific Revision**:
```bash
make helm-rollback REV=1
# Or:
# helm rollback app 1 -n october
```

**4. Verify Rollback**:
```bash
# Check rollout status
kubectl -n october rollout status deploy/api

# Verify revision
helm list -n october
```

### Automatic Rollback (CI/CD)

The CD pipeline includes automatic rollback on failure:

```yaml
- name: Auto-rollback to previous revision
  if: failure()
  run: |
    helm history app -n $NS
    PREV=$(helm history app -n $NS --output json | jq '.[1].revision')
    helm rollback app "$PREV" -n $NS
```

Triggers:
- Helm upgrade failure
- E2E smoke test failure
- Deployment timeout

## Troubleshooting

### Common Issues

**1. Image Pull Errors**:
```bash
# Check pod events
kubectl -n october describe pod <pod-name>

# Common causes:
# - Image not loaded into Minikube
# - Incorrect image tag
# - Registry authentication failure

# Fix for Minikube:
make k8s-build-load
make k8s-build-load-worker
```

**2. CrashLoopBackOff**:
```bash
# Check logs
kubectl -n october logs <pod-name>

# Common causes:
# - Application crash on startup
# - Missing environment variables
# - Redis connection failure

# Debug:
kubectl -n october describe pod <pod-name>
```

**3. Ingress Not Working**:
```bash
# Verify Ingress Controller is running
kubectl -n ingress-nginx get pods

# Check Ingress resource
kubectl -n october get ingress

# Enable if missing:
make k8s-enable-ingress

# Test with port-forward instead:
make k8s-port-api
curl http://localhost:8080/healthz
```

**4. HPA Not Scaling**:
```bash
# Check metrics-server
kubectl -n kube-system get pods -l k8s-app=metrics-server

# Enable if missing:
make k8s-enable-metrics

# Check HPA status
kubectl -n october describe hpa api

# Verify pod metrics available:
kubectl -n october top pods
```

### Debugging Commands

```bash
# Get all resources
kubectl -n october get all

# Describe deployment
kubectl -n october describe deploy api

# View pod logs
kubectl -n october logs -l app=api --tail=100 -f

# Execute command in pod
kubectl -n october exec -it deploy/api -- /bin/sh

# Port forward to pod
kubectl -n october port-forward pod/<pod-name> 8080:8000

# View events
kubectl -n october get events --sort-by='.lastTimestamp'
```

### Helm Debugging

```bash
# Lint chart
helm lint deploy/helm/api --strict

# Render templates (dry-run)
helm template app deploy/helm/api -f deploy/helm/api/values-dev.yaml

# Install with debug output
helm upgrade --install app deploy/helm/api --debug --dry-run

# View release manifest
helm get manifest app -n october

# View release values
helm get values app -n october
```

---

## Next Steps

After successful deployment:

1. **Configure Monitoring** (M4): [Observability Guide](OBSERVABILITY_GUIDE.md)
2. **Set Up Alerts**: [Alert Configuration](../runbooks/alerts.md)
3. **Review Security**: [Security Hardening](SECURITY_GUIDE.md)
4. **Backup Strategy**: [Backup & Restore](../runbooks/redis-backup-restore.md)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-19
**Tested With**: Minikube 1.32, Kubernetes 1.28, Helm 3.14
