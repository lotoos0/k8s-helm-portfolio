# RUNBOOK: ImagePullBackOff / ErrImagePull

## 📋 Incident Overview

**Trigger**: Pod stuck in `ImagePullBackOff` or `ErrImagePull` state
**Severity**: HIGH - Pod cannot start, service unavailable
**Expected Resolution Time**: 5-10 minutes

## 🚨 Symptoms

```bash
$ kubectl -n october get pods
NAME                    READY   STATUS             RESTARTS   AGE
api-7b8c9d5f6b-xyz12   0/1     ImagePullBackOff   0          2m
```

or

```bash
NAME                    READY   STATUS         RESTARTS   AGE
api-7b8c9d5f6b-xyz12   0/1     ErrImagePull   0          30s
```

Indicators:
- Pod status: `ImagePullBackOff` or `ErrImagePull`
- Container not starting
- RESTARTS: 0 (pod never successfully started)

## 🔍 Step 1: Identify the Problem

### Check pod events
```bash
kubectl -n october describe pod <pod-name>
```

**Look for** in Events section:
```
Events:
  Type     Reason     Message
  ----     ------     -------
  Warning  Failed     Failed to pull image "october-api:dev": rpc error: code = Unknown desc = Error response from daemon: pull access denied for october-api, repository does not exist
  Warning  Failed     Error: ErrImagePull
  Normal   BackOff    Back-off pulling image "october-api:dev"
  Warning  Failed     Error: ImagePullBackOff
```

Common error messages:
- `repository does not exist`
- `pull access denied`
- `manifest unknown`
- `unauthorized`
- `image not found`

## 🛠️ Step 2: Common Causes & Solutions

### Cause A: Image Not Loaded into Minikube (LOCAL DEV)

**Most common for local development!**

**Diagnosis**:
```bash
# Check if image exists in Minikube
minikube image ls | grep october

# If empty or image missing → NOT LOADED
```

**Solution**:
```bash
# For API
make k8s-build-load
# This does: docker build + minikube image load

# For Worker
make k8s-build-load-worker

# Verify image is loaded
minikube image ls | grep october
# Should show:
# docker.io/library/october-api:dev
# docker.io/library/october-worker:dev

# Restart deployment to trigger new pull
kubectl -n october rollout restart deploy/api
kubectl -n october rollout restart deploy/worker
```

### Cause B: Wrong Image Tag

**Diagnosis**:
```bash
# Check what image deployment is trying to pull
kubectl -n october get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}'
# Example output: october-api:v1.0.0

# Check what images are available locally
minikube image ls | grep october
# Example output: october-api:dev
```

**If tags don't match → TAG MISMATCH**

**Solution**:
```bash
# Option 1: Update deployment to use correct tag
kubectl -n october set image deploy/api api=october-api:dev

# Option 2: Build image with expected tag
docker build -t october-api:v1.0.0 ./api
minikube image load october-api:v1.0.0

# Option 3: Update Helm values
# Edit: deploy/helm/api/values-dev.yaml
api:
  image:
    tag: dev  # Match available image tag

make helm-up-dev
```

### Cause C: Image Pull Policy Issue

**Diagnosis**:
```bash
kubectl -n october get deploy api -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}'
# If shows: Always
```

**Problem**: With `imagePullPolicy: Always`, Kubernetes tries to pull from registry even for local images.

**Solution**:
```yaml
# Edit: deploy/helm/api/values-dev.yaml
api:
  image:
    pullPolicy: IfNotPresent  # or Never for local-only images

# Redeploy
make helm-up-dev
```

### Cause D: Registry Authentication (PRODUCTION)

**Diagnosis**:
```bash
kubectl -n october describe pod <pod-name>
# Look for: "pull access denied" or "unauthorized"
```

**Solution**:
```bash
# Create image pull secret for GHCR
kubectl -n october create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-token>

# Update deployment to use secret
# Edit: deploy/helm/api/templates/deployment-api.yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-secret

# Or via Helm values
# Edit: deploy/helm/api/values-prod.yaml
imagePullSecrets:
  - name: ghcr-secret

make helm-up-prod
```

### Cause E: Image Doesn't Exist in Registry (PRODUCTION)

**Diagnosis**:
```bash
# Check if image exists in GHCR
docker pull ghcr.io/<username>/october-api:dev
# If fails → image not pushed to registry
```

**Solution**:
```bash
# Verify CI/CD pushed images
# Check GitHub Actions: .github/workflows/ci.yml

# Manual push (if needed)
docker tag october-api:dev ghcr.io/<username>/october-api:dev
docker push ghcr.io/<username>/october-api:dev

# Verify
docker pull ghcr.io/<username>/october-api:dev

# Restart deployment
kubectl -n october rollout restart deploy/api
```

### Cause F: Network Issues

**Diagnosis**:
```bash
# Test registry connectivity
kubectl -n october run test --rm -it --image=alpine -- sh
# Inside container:
nslookup ghcr.io
# Should resolve to IP address

# Test internet connectivity
ping -c 3 8.8.8.8
```

**If fails → NETWORK ISSUE**

**Solution**:
```bash
# Check Minikube network
minikube ssh
# Inside Minikube:
ping -c 3 ghcr.io
ping -c 3 8.8.8.8

# Restart Minikube networking
minikube stop
minikube start

# Or recreate cluster
minikube delete
minikube start --cpus=4 --memory=8192
```

## ✅ Step 3: Verification

### 1. Check image is available
```bash
# For local dev
minikube image ls | grep october

# For production
docker pull ghcr.io/<username>/october-api:dev
```

### 2. Check pod status
```bash
kubectl -n october get pods -w
# Wait for: Running, READY 1/1
```

### 3. Verify container started
```bash
kubectl -n october describe pod <pod-name>
# Events should show:
# - Successfully pulled image
# - Created container
# - Started container
```

### 4. Check logs
```bash
kubectl -n october logs -l app=api --tail=20
# Should show application startup logs
```

### 5. Test service
```bash
MINIKUBE_IP=$(minikube ip)
curl -f http://api.$MINIKUBE_IP.nip.io/healthz
# Should return: {"status":"ok"}
```

## 🔁 Step 4: Rollback (if needed)

```bash
# If new image version is problematic
make helm-rollback-last

# Or specific revision
make helm-history
make helm-rollback REV=<working-revision>
```

## 🚀 Prevention

### For Local Development
```yaml
# deploy/helm/api/values-dev.yaml
api:
  image:
    repository: october-api
    tag: dev
    pullPolicy: IfNotPresent  # Don't pull if exists locally

worker:
  image:
    repository: october-worker
    tag: dev
    pullPolicy: IfNotPresent
```

### For Production
```yaml
# deploy/helm/api/values-prod.yaml
api:
  image:
    repository: ghcr.io/<username>/october-api
    tag: v0.1.0  # Use specific version, NOT :dev
    pullPolicy: Always  # Always pull latest from registry

imagePullSecrets:
  - name: ghcr-secret
```

### CI/CD Checks
```yaml
# .github/workflows/ci.yml
# Ensure images are pushed successfully
- name: Verify image exists
  run: |
    docker pull ${{ env.IMAGE_NAME }}:dev
```

## 📊 Post-Incident

### Document the issue
1. Which image was problematic?
2. What was the root cause?
3. How was it fixed?

### Update runbook
- Add new patterns if discovered
- Update troubleshooting steps

## 📚 Related Documentation

- [Deployment Guide - Kubernetes](../DEPLOYMENT_GUIDE.md#kubernetes-deployment)
- [Deployment Guide - Registry Setup](../DEPLOYMENT_GUIDE.md#registry--image-tags)
- [Troubleshooting Guide](../TROUBLESHOOTING.md)

## 🔑 Quick Reference

### Local Development
```bash
# Build and load images
make k8s-build-load          # API
make k8s-build-load-worker   # Worker

# Verify loaded
minikube image ls | grep october

# Restart pods
kubectl -n october rollout restart deploy/api
kubectl -n october rollout restart deploy/worker
```

### Production
```bash
# Check image exists
docker pull ghcr.io/<username>/october-api:dev

# Create pull secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<user> \
  --docker-password=<token> \
  -n october

# Update deployment
make helm-up-prod
```

### Diagnosis
```bash
kubectl -n october describe pod <pod-name>          # Check events
kubectl -n october get deploy api -o yaml | grep image  # Check image config
minikube image ls | grep october                    # Check local images
```

---

**Last Updated**: 2025-10-19
**Version**: 1.0
**Tested On**: Minikube 1.32, Kubernetes 1.28
