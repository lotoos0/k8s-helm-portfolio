# RUNBOOK: CrashLoopBackOff

## 📋 Incident Overview

**Trigger**: Pod stuck in `CrashLoopBackOff` state
**Severity**: HIGH - Service degraded or unavailable
**Expected Resolution Time**: 5-15 minutes

## 🚨 Symptoms

```bash
$ kubectl -n october get pods
NAME                    READY   STATUS             RESTARTS   AGE
api-7b8c9d5f6b-xyz12   0/1     CrashLoopBackOff   5          3m
```

Indicators:
- Pod status shows `CrashLoopBackOff`
- RESTARTS counter keeps increasing
- READY shows 0/1 (container not ready)
- Service unavailable or degraded

## 🔍 Step 1: Identify the Problem

### Check pod events
```bash
kubectl -n october describe pod <pod-name>
```

**Look for**:
- Recent events at bottom
- Exit codes (127, 1, 137, etc.)
- Error messages
- Probe failures

### Check container logs
```bash
# Current logs
kubectl -n october logs <pod-name>

# Previous container logs (if restarted)
kubectl -n october logs <pod-name> --previous
```

**Common patterns**:
```
# Application error
Traceback (most recent call last):
  File "/app/main.py", line 10, in <module>
    from missing_module import something
ModuleNotFoundError: No module named 'missing_module'

# Port binding error
OSError: [Errno 98] Address already in use

# Connection error
redis.exceptions.ConnectionError: Error connecting to Redis

# OOMKilled (exit code 137)
container "api" in pod "api-xxx" is waiting to start: CrashLoopBackOff
```

## 🛠️ Step 2: Common Causes & Solutions

### Cause A: Application Error

**Diagnosis**:
```bash
kubectl -n october logs <pod-name> --previous | grep -i "error\|exception\|traceback"
```

**Solution**:
1. Fix application code
2. Rebuild image: `make k8s-build-load`
3. Redeploy: `kubectl -n october rollout restart deploy/api`

### Cause B: Missing Environment Variable

**Diagnosis**:
```bash
# Check pod environment
kubectl -n october exec <pod-name> -- env

# Compare with expected variables
kubectl -n october get configmap app-config -o yaml
kubectl -n october get secret app-secrets -o yaml
```

**Solution**:
```bash
# Update ConfigMap
kubectl -n october edit configmap app-config

# Or update via Helm
# Edit deploy/helm/api/values-dev.yaml
make helm-up-dev

# Restart pods to pick up changes
kubectl -n october rollout restart deploy/api
```

### Cause C: Port Already in Use

**Diagnosis**:
```bash
kubectl -n october logs <pod-name> --previous | grep "Address already in use"
```

**Solution**:
Check for duplicate port bindings in Dockerfile or deployment:
```yaml
# Ensure only ONE process binds to port 8000
# Check: api/Dockerfile CMD line
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Cause D: Cannot Connect to Redis

**Diagnosis**:
```bash
kubectl -n october logs <pod-name> --previous | grep -i "redis"
```

**Solution**:
```bash
# Check if Redis is running
kubectl -n october get pods -l app=redis

# Check Redis service
kubectl -n october get svc redis

# Test connectivity
kubectl -n october exec <pod-name> -- nc -zv redis 6379

# If Redis is down, restart it
kubectl -n october rollout restart deploy/redis
```

### Cause E: OOMKilled (Out of Memory)

**Diagnosis**:
```bash
kubectl -n october describe pod <pod-name> | grep -i "oomkilled"
```

**Solution**:
```bash
# Increase memory limit in values.yaml
resources:
  limits:
    memory: "1Gi"  # Increase from 512Mi

# Redeploy
make helm-up-dev
```

### Cause F: Liveness Probe Too Aggressive

**Diagnosis**:
```bash
kubectl -n october get events | grep -i "liveness probe failed"
```

**Solution**:
```yaml
# Edit deploy/helm/api/values.yaml
livenessProbe:
  failureThreshold: 5      # Increase from 3
  periodSeconds: 15        # Increase from 10
  initialDelaySeconds: 30  # Add delay
```

Redeploy:
```bash
make helm-up-dev
```

## ✅ Step 3: Verification

After applying fix:

### 1. Check pod status
```bash
kubectl -n october get pods -w
# Wait for: Running, READY 1/1, RESTARTS stable
```

### 2. Verify no new crashes
```bash
# Wait 2-3 minutes, check RESTARTS counter
kubectl -n october get pods
# Should NOT increase
```

### 3. Check logs for errors
```bash
kubectl -n october logs -l app=api --tail=50
# Should show normal startup, no errors
```

### 4. Test service endpoint
```bash
MINIKUBE_IP=$(minikube ip)
curl -f http://api.$MINIKUBE_IP.nip.io/healthz
# Should return: {"status":"ok"}
```

### 5. Monitor for 5 minutes
```bash
watch -n 5 'kubectl -n october get pods'
# Ensure stability
```

## 🔁 Step 4: Rollback (if fix doesn't work)

```bash
# View Helm history
make helm-history

# Rollback to previous working version
make helm-rollback-last

# Or specific revision
make helm-rollback REV=<number>

# Verify
kubectl -n october rollout status deploy/api
```

## 📊 Post-Incident

### Collect diagnostics
```bash
mkdir -p diagnostics/$(date +%Y%m%d-%H%M)
cd diagnostics/$(date +%Y%m%d-%H%M)

# Save pod description
kubectl -n october describe pod <pod-name> > pod-describe.txt

# Save logs
kubectl -n october logs <pod-name> --previous > pod-logs-previous.txt
kubectl -n october logs <pod-name> > pod-logs-current.txt

# Save events
kubectl -n october get events --sort-by='.lastTimestamp' > events.txt

# Save deployment config
kubectl -n october get deploy api -o yaml > deployment.yaml
```

### Root cause analysis
1. What caused the crash?
2. Why didn't we detect it earlier?
3. How can we prevent it?

### Prevention measures
- Add pre-deployment testing
- Improve health checks
- Add monitoring/alerts (M4)
- Update CI/CD pipeline

## 📚 Related Documentation

- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [Deployment Guide - Rollback](../DEPLOYMENT_GUIDE.md#rollback-process)
- [Architecture - Health Probes](../ARCHITECTURE.md#probe-configuration)

## 🔑 Quick Reference

```bash
# Fastest diagnosis path
kubectl -n october get pods                           # Check status
kubectl -n october describe pod <pod-name>            # Events
kubectl -n october logs <pod-name> --previous         # Previous logs
kubectl -n october logs <pod-name>                    # Current logs

# Common fixes
kubectl -n october rollout restart deploy/api         # Restart
kubectl -n october edit configmap app-config          # Fix config
make helm-rollback-last                               # Rollback

# Verification
kubectl -n october get pods -w                        # Watch status
curl http://api.$(minikube ip).nip.io/healthz       # Test endpoint
```

---

**Last Updated**: 2025-10-19
**Version**: 1.0
**Tested On**: Minikube 1.32, Kubernetes 1.28
