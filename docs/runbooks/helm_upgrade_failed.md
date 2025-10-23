# RUNBOOK: Helm Upgrade Failed

## 📋 Incident Overview

**Trigger**: `helm upgrade` command fails or times out
**Severity**: HIGH - Deployment blocked, possible service degradation
**Expected Resolution Time**: 10-20 minutes

## 🚨 Symptoms

```bash
$ make helm-up-dev
Error: UPGRADE FAILED: timed out waiting for the condition
```

or

```bash
Error: UPGRADE FAILED: cannot patch "api" with kind Deployment
```

or

```bash
Error: UPGRADE FAILED: release app failed, and has been rolled back
```

## 🔍 Step 1: Identify the Problem

### Check Helm release status
```bash
helm list -n october

# Shows status: deployed, failed, pending-upgrade, etc.
```

### Check release history
```bash
helm history app -n october

# Example output:
# REVISION  STATUS        DESCRIPTION
# 1         superseded    Install complete
# 2         pending-upgrade  Upgrade in progress
```

### Check deployment status
```bash
kubectl -n october get deploy,pod,svc
kubectl -n october rollout status deploy/api
```

## 🛠️ Common Causes & Solutions

### Cause A: Timeout (Pods Not Ready)

**Diagnosis**:
```bash
kubectl -n october get pods
# Check if pods are CrashLoopBackOff, ImagePullBackOff, etc.
```

**Solution**:
```bash
# Fix underlying pod issue first
# See: crashloopbackoff.md, image_pull_backoff.md

# Then retry with longer timeout
helm upgrade --install app deploy/helm/api \
  -n october \
  -f deploy/helm/api/values-dev.yaml \
  --timeout 10m  # Increase from default 5m

# Or use atomic flag for auto-rollback
make helm-up-dev-atomic
```

### Cause B: Pending Upgrade Stuck

**Diagnosis**:
```bash
helm history app -n october
# Shows: pending-upgrade, pending-install, or pending-rollback
```

**Solution**:
```bash
# Rollback to clear stuck state
helm rollback app -n october

# Or force delete and reinstall
helm delete app -n october
make helm-up-dev
```

### Cause C: Resource Conflicts

**Diagnosis**:
```bash
# Error message shows: "cannot patch" or "already exists"
kubectl -n october get all
```

**Solution**:
```bash
# Delete conflicting resources manually
kubectl -n october delete <resource-type> <resource-name>

# Or delete entire release and reinstall
helm delete app -n october
kubectl -n october delete all --all
make helm-up-dev
```

### Cause D: Invalid Values/Templates

**Diagnosis**:
```bash
# Lint chart
helm lint deploy/helm/api --strict

# Template rendering
helm template app deploy/helm/api -f deploy/helm/api/values-dev.yaml
```

**Solution**:
```bash
# Fix template errors in deploy/helm/api/templates/
# Fix values in deploy/helm/api/values-dev.yaml

# Validate before upgrade
make helm-lint
make helm-template-dev

# Then upgrade
make helm-up-dev
```

### Cause E: Corrupted Release

**Diagnosis**:
```bash
helm get manifest app -n october
# If shows errors or incomplete YAML
```

**Solution**:
```bash
# Delete and reinstall
helm delete app -n october
make helm-up-dev
```

## ✅ Verification

```bash
# Check release status
helm list -n october
# Should show: STATUS = deployed

# Check deployment rollout
kubectl -n october rollout status deploy/api
kubectl -n october rollout status deploy/worker
kubectl -n october rollout status deploy/redis

# Verify pods running
kubectl -n october get pods

# Test service
MINIKUBE_IP=$(minikube ip)
curl -f http://api.$MINIKUBE_IP.nip.io/healthz
```

## 🔁 Step 3: Rollback

```bash
# View history
make helm-history

# Rollback to previous working revision
make helm-rollback-last

# Or specific revision
make helm-rollback REV=<number>

# Verify rollback
helm history app -n october
kubectl -n october get pods
```

## 🚀 Prevention

### Use Atomic Upgrades
```bash
# Auto-rollback on failure
make helm-up-dev-atomic

# Or manually:
helm upgrade --install app deploy/helm/api \
  --atomic \
  --timeout 5m \
  -n october \
  -f deploy/helm/api/values-dev.yaml
```

### Pre-deployment Checks
```bash
# Always run before upgrade:
make helm-lint           # Validate chart
make helm-template-dev   # Check rendering
make helm-diff-dev       # Preview changes
```

### Test in Dev First
```bash
# Test changes in dev environment
make helm-up-dev

# Monitor for 5-10 minutes
kubectl -n october get pods -w

# Then deploy to prod
make helm-up-prod
```

## 📚 Related Documentation

- [Deployment Guide - Helm](../DEPLOYMENT_GUIDE.md#helm-deployment)
- [Deployment Guide - Rollback](../DEPLOYMENT_GUIDE.md#rollback-process)
- [Troubleshooting](../TROUBLESHOOTING.md#helm-issues)

## 🔑 Quick Reference

```bash
# Diagnosis
helm list -n october                    # Check status
helm history app -n october             # Check history
kubectl -n october get all              # Check resources

# Common fixes
helm rollback app -n october            # Rollback stuck upgrade
helm delete app -n october              # Delete and reinstall
make helm-up-dev-atomic                 # Upgrade with auto-rollback

# Prevention
make helm-lint                          # Validate
make helm-diff-dev                      # Preview changes
make helm-up-dev-atomic                 # Safe upgrade
```

---

**Last Updated**: 2025-10-19
