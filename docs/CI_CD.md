# CI/CD Pipeline Guide

Complete guide to the Continuous Integration and Continuous Deployment pipeline for the October DevOps platform.

## Table of Contents

- [Overview](#overview)
- [CI Pipeline](#ci-pipeline)
- [CD Pipeline](#cd-pipeline)
- [Registry & Image Tags](#registry--image-tags)
- [Secrets Management](#secrets-management)
- [E2E Smoke Tests](#e2e-smoke-tests)
- [Automatic Rollback](#automatic-rollback)
- [Local CD Testing](#local-cd-testing)
- [Troubleshooting](#troubleshooting)

---

## Overview

**CI/CD Philosophy**: Automate everything from code commit to production deployment.

**Pipeline Stages**:
1. **Build** → Compile Docker images
2. **Test** → Run unit tests, linting
3. **Scan** → Security scanning with Trivy
4. **Push** → Push images to registry (GHCR)
5. **Deploy** → Helm upgrade with `--atomic` flag
6. **Smoke** → E2E smoke tests post-deployment
7. **Rollback** → Automatic rollback on failure

**Tools**:
- **GitHub Actions** - CI/CD orchestration
- **Trivy** - Container vulnerability scanning
- **Helm** - Kubernetes package manager with atomic deployments
- **GHCR** - GitHub Container Registry

---

## CI Pipeline

### Trigger

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

### Stages

#### 1. Lint & Test

```yaml
- name: Lint API
  run: |
    cd api
    pip install ruff
    ruff check .

- name: Test API
  run: |
    cd api
    pytest
```

#### 2. Build Docker Images

```yaml
- name: Build API image
  run: docker build -t october-api:${{ github.sha }} ./api

- name: Build Worker image
  run: docker build -t october-worker:${{ github.sha }} ./worker
```

#### 3. Security Scan (Trivy)

```yaml
- name: Scan API image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: october-api:${{ github.sha }}
    severity: 'HIGH,CRITICAL'
    exit-code: '1'  # Fail on HIGH/CRITICAL
```

**Policy**: Pipeline fails if HIGH or CRITICAL vulnerabilities are found.

#### 4. Push to Registry

```yaml
- name: Log in to GHCR
  run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

- name: Tag and push
  run: |
    docker tag october-api:${{ github.sha }} ghcr.io/${{ github.repository_owner }}/october-api:dev
    docker push ghcr.io/${{ github.repository_owner }}/october-api:dev
```

---

## CD Pipeline

### Trigger

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:  # Manual trigger
```

### Required Secrets

Configure these in GitHub repository settings (`Settings` → `Secrets and variables` → `Actions`):

| Secret | Description | Example |
|--------|-------------|---------|
| `DEV_KUBECONFIG` | Kubeconfig for dev cluster | Base64-encoded kubeconfig file |
| `DEV_NAMESPACE` | Target namespace | `october` |
| `DEV_INGRESS_HOST` | Ingress hostname | `api.192.168.49.2.nip.io` |

**Creating DEV_KUBECONFIG**:
```bash
# Minikube
cat ~/.kube/config | base64 -w0

# Or for specific cluster
kubectl config view --flatten --minify | base64 -w0
```

### Deployment Stages

#### 1. Lint Helm Chart

```yaml
- name: Helm lint
  run: helm lint deploy/helm/api
```

#### 2. Template Preview

```yaml
- name: Helm template (dry-run)
  run: |
    helm template app deploy/helm/api \
      -n ${{ secrets.DEV_NAMESPACE }} \
      -f deploy/helm/api/values-dev.yaml \
      --set api.ingress.host=${{ secrets.DEV_INGRESS_HOST }}
```

#### 3. Deploy with Helm (Atomic)

```yaml
- name: Helm upgrade (atomic)
  run: |
    helm upgrade --install app deploy/helm/api \
      -n ${{ secrets.DEV_NAMESPACE }} \
      --create-namespace \
      -f deploy/helm/api/values.yaml \
      -f deploy/helm/api/values-dev.yaml \
      --set api.ingress.host=${{ secrets.DEV_INGRESS_HOST }} \
      --set api.image.tag=dev \
      --atomic \
      --timeout 5m \
      --history-max 10
```

**`--atomic` Flag**: Automatically rolls back if deployment fails.

#### 4. E2E Smoke Tests

```yaml
- name: Run smoke tests
  run: ./scripts/smoke.sh ${{ secrets.DEV_INGRESS_HOST }}
```

#### 5. Rollback on Failure

```yaml
- name: Rollback on failure
  if: failure()
  run: |
    helm rollback app -n ${{ secrets.DEV_NAMESPACE }}
    kubectl -n ${{ secrets.DEV_NAMESPACE }} get pods
```

---

## Registry & Image Tags

### Registry: GitHub Container Registry (GHCR)

**Image Naming**:
- `ghcr.io/<username>/october-api`
- `ghcr.io/<username>/october-worker`

**Visibility**: Public (can be changed to private in GitHub package settings)

### Tagging Strategy

| Tag | Description | Use Case | Immutable? |
|-----|-------------|----------|-----------|
| `:dev` | Latest dev build | Dev/staging deployments | ❌ No (mutable) |
| `:sha-<short>` | Git commit SHA | Reproducible builds | ✅ Yes |
| `:vX.Y.Z` | Semantic version | Production releases | ✅ Yes |
| `:latest` | Latest stable | Quick testing | ❌ No (avoid in prod) |

**Example**:
```bash
# After git commit abc123d:
ghcr.io/myuser/october-api:dev           # Mutable, points to latest
ghcr.io/myuser/october-api:sha-abc123d   # Immutable
ghcr.io/myuser/october-api:v0.1.0        # Immutable (after git tag)
```

### Creating a Release

```bash
# Tag release
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0

# CI will automatically build and push:
# - ghcr.io/<user>/october-api:v0.1.0
# - ghcr.io/<user>/october-worker:v0.1.0
```

### Pulling Images Locally

```bash
# Log in to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u <username> --password-stdin

# Pull images
docker pull ghcr.io/<username>/october-api:dev
docker pull ghcr.io/<username>/october-worker:v0.1.0
```

---

## Secrets Management

### Kubernetes Secrets

Secrets are stored in Kubernetes Secret resources and injected via environment variables.

**values.yaml**:
```yaml
secrets:
  CELERY_BROKER_URL: redis://redis:6379/0
  CELERY_RESULT_BACKEND: redis://redis:6379/0
  # Add more secrets here
```

**Helm template** (`templates/secret.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: {{ .Values.namespace }}
type: Opaque
data:
  {{- range $key, $value := .Values.secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
```

**Injection** (`deployment.yaml`):
```yaml
envFrom:
  - secretRef:
      name: app-secret
```

### Best Practices

✅ **Do**:
- Store secrets in Kubernetes Secrets (not ConfigMaps)
- Use base64 encoding (automatic with Helm `b64enc`)
- Inject via `envFrom.secretRef` (cleaner than individual env vars)
- Use different secrets for dev/staging/prod
- Rotate secrets regularly

❌ **Don't**:
- Commit secrets to Git (use `.gitignore`)
- Use plaintext ConfigMaps for sensitive data
- Hard-code secrets in Dockerfiles or code
- Share secrets across environments

### External Secrets (Advanced)

For production, consider external secret management:

- **AWS Secrets Manager** + External Secrets Operator
- **HashiCorp Vault** + Vault Agent Injector
- **Google Secret Manager** + Workload Identity

---

## E2E Smoke Tests

### Overview

Smoke tests run **after deployment** to validate the system is working correctly.

**Location**: `scripts/smoke.sh`

**Purpose**: Catch deployment issues before they affect users.

### Test Coverage

```bash
#!/bin/bash
# scripts/smoke.sh

HOST=$1

# Test 1: Health check
curl -f http://$HOST/healthz || exit 1

# Test 2: Readiness
curl -f http://$HOST/ready || exit 1

# Test 3: Metrics endpoint
curl -f http://$HOST/metrics | grep -q "http_requests_total" || exit 1

# Test 4: API functionality
curl -f http://$HOST/compute/prime?n=100 || exit 1

echo "✅ All smoke tests passed"
```

### Running Smoke Tests

**In CI/CD**:
```yaml
- name: Smoke tests
  run: ./scripts/smoke.sh ${{ secrets.DEV_INGRESS_HOST }}
```

**Locally (via Ingress)**:
```bash
IP=$(minikube ip)
make smoke-ci HOST=api.$IP.nip.io
```

**Locally (via port-forward)**:
```bash
kubectl -n october port-forward svc/api 8080:8000 &
make smoke-pf
# Or:
./scripts/smoke.sh localhost:8080
```

### Smoke Test Failures

**If smoke tests fail**:
1. Deployment is marked as failed
2. Diagnostics are collected (kubectl/helm output)
3. Automatic rollback is triggered (if `--atomic` used)
4. Logs are uploaded as artifacts

**Example CI failure handling**:
```yaml
- name: Collect diagnostics on failure
  if: failure()
  run: |
    kubectl -n ${{ secrets.DEV_NAMESPACE }} get all
    kubectl -n ${{ secrets.DEV_NAMESPACE }} describe pods
    helm list -n ${{ secrets.DEV_NAMESPACE }}

- name: Upload diagnostics
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: diagnostics
    path: |
      diagnostics.txt
      kubectl-output.txt
```

---

## Automatic Rollback

### Helm --atomic Flag

The `--atomic` flag ensures safe deployments with automatic rollback on failure.

**Behavior**:
```bash
helm upgrade --install app deploy/helm/api \
  --atomic \
  --timeout 5m
```

- Helm waits for all pods to be Ready (up to 5 minutes)
- If any pod fails (CrashLoopBackOff, ImagePullBackOff), rollback is triggered
- Old ReplicaSet is restored
- Deployment is marked as failed

**Example Timeline**:
```
0:00 - New ReplicaSet created
0:30 - Pods fail to start (ImagePullBackOff)
5:00 - Timeout reached
5:05 - Helm triggers automatic rollback
5:10 - Old ReplicaSet restored, system healthy
```

### Manual Rollback

If automatic rollback fails or you need to rollback later:

```bash
# View history
helm history app -n october

# Rollback to previous
helm rollback app -n october

# Rollback to specific revision
helm rollback app 3 -n october
```

**Using Makefile**:
```bash
make helm-history
make helm-rollback REV=3
```

### Rollback in CI/CD

```yaml
- name: Deploy with atomic
  id: deploy
  run: |
    helm upgrade --install app deploy/helm/api \
      --atomic --timeout 5m \
      -n ${{ secrets.DEV_NAMESPACE }}

- name: Rollback on smoke test failure
  if: failure() && steps.deploy.outcome == 'success'
  run: |
    echo "Smoke tests failed, rolling back..."
    helm rollback app -n ${{ secrets.DEV_NAMESPACE }}
```

---

## Local CD Testing

### Test CD Pipeline Locally

```bash
# Set variables
export DEV_HOST=api.$(minikube ip).nip.io

# Run CD (Helm upgrade)
make cd-dev DEV_HOST=$DEV_HOST

# Or atomic version (with auto-rollback)
make cd-dev-atomic DEV_HOST=$DEV_HOST
```

### Simulate CD Workflow

```bash
# 1. Lint
make helm-lint

# 2. Template (dry-run)
make helm-template-dev

# 3. Deploy (atomic)
make helm-up-dev-atomic

# 4. Smoke tests
make smoke-ci HOST=api.$(minikube ip).nip.io

# 5. Check status
kubectl -n october get pods
helm list -n october
```

### Testing Rollback

```bash
# Deploy broken image
helm upgrade app deploy/helm/api -n october \
  --set api.image.tag=non-existent \
  --atomic --timeout 2m

# Expected: Auto-rollback after 2 minutes

# Verify rollback
helm history app -n october
kubectl -n october get pods
```

---

## Troubleshooting

### Problem: ImagePullBackOff in CI/CD

**Cause**: Image not pushed to registry or wrong tag

**Solutions**:
```bash
# Check image exists in GHCR
docker pull ghcr.io/<user>/october-api:dev

# Check imagePullSecrets (if private registry)
kubectl -n october get secrets

# Check pod events
kubectl -n october describe pod <pod-name>
```

### Problem: Helm upgrade fails with timeout

**Cause**: Pods not becoming Ready within timeout

**Solutions**:
```bash
# Check pod status
kubectl -n october get pods

# Check pod logs
kubectl -n october logs -f <pod-name>

# Increase timeout
helm upgrade --atomic --timeout 10m ...

# Check health probes
kubectl -n october describe pod <pod-name> | grep -A 10 "Liveness\|Readiness"
```

### Problem: Smoke tests fail

**Cause**: Service not accessible or returning errors

**Solutions**:
```bash
# Check service
kubectl -n october get svc

# Check ingress
kubectl -n october get ingress

# Test service directly (port-forward)
kubectl -n october port-forward svc/api 8080:8000
curl http://localhost:8080/healthz

# Check logs
kubectl -n october logs -l app=api --tail=50
```

### Problem: Rollback doesn't work

**Cause**: No previous revision or Helm history corrupted

**Solutions**:
```bash
# Check Helm history
helm history app -n october

# If history is empty, redeploy
make helm-up-dev

# If history is corrupted, uninstall and reinstall
helm uninstall app -n october
make helm-up-dev
```

---

## Quick Reference

### Essential Commands

```bash
# Local CD
make cd-dev DEV_HOST=api.$(minikube ip).nip.io
make cd-dev-atomic DEV_HOST=api.$(minikube ip).nip.io

# Smoke tests
make smoke-ci HOST=api.$(minikube ip).nip.io
make smoke-pf  # via port-forward

# Helm operations
make helm-lint
make helm-template-dev
make helm-up-dev-atomic
make helm-history
make helm-rollback REV=2

# Image operations
docker build -t october-api:dev ./api
docker tag october-api:dev ghcr.io/<user>/october-api:dev
docker push ghcr.io/<user>/october-api:dev

# Check deployment
kubectl -n october get pods
helm list -n october
kubectl -n october rollout status deploy/api
```

### CI/CD Workflow

```
1. Developer pushes code to main branch
   ↓
2. CI pipeline runs:
   - Lint & test
   - Build Docker images
   - Scan with Trivy
   - Push to GHCR
   ↓
3. CD pipeline runs:
   - Helm lint
   - Helm template (preview)
   - Helm upgrade --atomic
   ↓
4. Smoke tests run
   ↓
5. If success: Deployment complete ✅
   If failure: Auto-rollback triggered 🔄
```

---

## Related Documentation

- **[Architecture: CI/CD Pipeline](ARCHITECTURE.md#cicd-architecture)** - Pipeline design
- **[Deployment Guide: Helm Deployment](DEPLOYMENT_GUIDE.md#helm-deployment)** - Helm usage
- **[Operations: Rollback Testing](operations/README.md#scenario-3-rollback-atomic-deployments)** - Chaos testing
- **[Troubleshooting: Deployment Issues](TROUBLESHOOTING.md#deployment-issues)** - Debugging
- **[Security: Image Scanning](SECURITY.md#image-security)** - Trivy configuration
