# RUNBOOK: Pod Not Scheduling (Pending)

## 📋 Incident Overview

**Trigger**: Pod stuck in `Pending` state
**Severity**: HIGH - Pod cannot start
**Expected Resolution Time**: 5-15 minutes

## 🚨 Symptoms

```bash
$ kubectl -n october get pods
NAME                   READY   STATUS    RESTARTS   AGE
api-7b8c9d5f6b-xyz12   0/1     Pending   0          5m
```

## 🔍 Step 1: Identify the Problem

```bash
kubectl -n october describe pod <pod-name>
```

**Look for Events**:
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedScheduling  0/1 nodes are available: 1 Insufficient cpu
  Warning  FailedScheduling  0/1 nodes are available: 1 Insufficient memory
  Warning  FailedScheduling  persistentvolumeclaim "redis-data" not found
```

## 🛠️ Common Causes & Solutions

### Cause A: Insufficient CPU

**Diagnosis**:
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"

# Shows CPU/memory usage
```

**Solution**:
```bash
# Option 1: Reduce resource requests
# Edit: deploy/helm/api/values-dev.yaml
resources:
  requests:
    cpu: 50m      # Reduce from 100m
    memory: 64Mi  # Reduce from 128Mi

make helm-up-dev

# Option 2: Add more resources to Minikube
minikube stop
minikube start --cpus=4 --memory=8192

# Option 3: Delete unused pods
kubectl -n october delete pod <unused-pod>
```

### Cause B: Insufficient Memory

**Solution**: Same as CPU (see above)

### Cause C: PVC Not Found/Pending

**Diagnosis**:
```bash
kubectl -n october get pvc

# If PVC is Pending:
kubectl -n october describe pvc <pvc-name>
```

**Solution**:
```bash
# Ensure storage provisioner is enabled
minikube addons list | grep storage
minikube addons enable storage-provisioner

# Delete and recreate PVC if needed
kubectl -n october delete pvc redis-data
make helm-up-dev  # Will recreate PVC
```

### Cause D: Node Not Ready

**Diagnosis**:
```bash
kubectl get nodes

# Should show Ready:
# NAME       STATUS   ROLES    AGE   VERSION
# minikube   Ready    master   10m   v1.28.0
```

**Solution**:
```bash
# If Not Ready, restart Minikube
minikube stop
minikube start --cpus=4 --memory=8192
```

## ✅ Verification

```bash
# Wait for Running status
kubectl -n october get pods -w

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated"

# Verify pod scheduled
kubectl -n october describe pod <pod-name> | grep "Successfully assigned"
```

## 🔑 Quick Reference

```bash
# Diagnosis
kubectl -n october describe pod <pod-name>
kubectl describe nodes

# Common fixes
minikube start --cpus=4 --memory=8192   # More resources
make helm-up-dev                         # Reduce requests
minikube addons enable storage-provisioner  # Enable storage
```

---

**Last Updated**: 2025-10-19
