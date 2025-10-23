# RUNBOOK: Service Unreachable

## 📋 Incident Overview

**Trigger**: Cannot connect to Kubernetes Service (via port-forward or ClusterIP)
**Severity**: HIGH - Service unavailable
**Expected Resolution Time**: 10-20 minutes

## 🚨 Symptoms

```bash
$ kubectl -n october port-forward svc/api 8080:80
Forwarding from 127.0.0.1:8080 -> 8000
Forwarding from [::1]:8080 -> 8000

$ curl http://localhost:8080/healthz
curl: (52) Empty reply from server
```

or

```bash
$ curl http://localhost:8080/healthz
curl: (7) Failed to connect to localhost port 8080: Connection refused
```

## 🔍 Step 1: Verify Service Exists

```bash
kubectl -n october get svc api

# Should show:
# NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# api    ClusterIP   10.96.XXX.XXX   <none>        80/TCP    10m
```

If service doesn't exist → **Deploy service first**

## 🛠️ Common Causes & Solutions

### Cause A: No Endpoints (No Healthy Pods)

**Diagnosis**:
```bash
kubectl -n october get endpoints api

# If ENDPOINTS column is empty:
# NAME   ENDPOINTS   AGE
# api    <none>      5m

# → Service has no healthy backend pods
```

**Solution**:
```bash
# Check pods
kubectl -n october get pods -l app=api

# Fix pod issues:
# - CrashLoopBackOff → see crashloopbackoff.md
# - ImagePullBackOff → see image_pull_backoff.md
# - Pending → see pod_not_scheduling.md

# Once pods are Running and Ready, endpoints auto-populate
```

### Cause B: Port Mismatch

**Diagnosis**:
```bash
# Check Service ports
kubectl -n october get svc api -o yaml | grep -A 5 "ports:"

# Should show:
# ports:
# - port: 80          ← Service listens here
#   targetPort: 8000  ← Forwards to container port 8000

# Check container port in deployment
kubectl -n october get deploy api -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'
# Should show: 8000
```

**Solution**:
```yaml
# Fix port mismatch in deploy/helm/api/values.yaml
api:
  service:
    port: 80           # External port
    targetPort: 8000   # Container port (must match Dockerfile EXPOSE)

  containerPort: 8000  # Must match FastAPI port

# Redeploy
make helm-up-dev
```

### Cause C: Selector Mismatch

**Diagnosis**:
```bash
# Check Service selector
kubectl -n october get svc api -o yaml | grep -A 2 "selector:"

# Example output:
# selector:
#   app: api

# Check Pod labels
kubectl -n october get pods -l app=api --show-labels

# If no pods match → SELECTOR MISMATCH
```

**Solution**:
```yaml
# Ensure labels match in deployment and service
# deploy/helm/api/templates/deployment-api.yaml
metadata:
  labels:
    app: api  # ← Must match

# deploy/helm/api/templates/service-api.yaml
spec:
  selector:
    app: api  # ← Must match

# Redeploy
make helm-up-dev
```

### Cause D: Application Not Listening

**Diagnosis**:
```bash
# Exec into pod
kubectl -n october exec -it deploy/api -- sh

# Inside pod, check if process listening on port 8000
netstat -tuln | grep 8000
# or
ss -tuln | grep 8000

# Should show:
# tcp   LISTEN   0.0.0.0:8000

# If no output → APP NOT LISTENING
```

**Solution**:
```python
# Check api/app/main.py or api/Dockerfile
# Ensure uvicorn binds to 0.0.0.0 (not 127.0.0.1)

# Dockerfile CMD should be:
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# NOT:
# CMD ["uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000"]
```

### Cause E: Readiness Probe Failing

**Diagnosis**:
```bash
kubectl -n october get pods
# Check READY column:
# NAME                   READY   STATUS
# api-xxx               0/1     Running  ← Not ready!

kubectl -n october describe pod <pod-name> | grep "Readiness probe failed"
```

**Solution**:
```bash
# Check /ready endpoint works
kubectl -n october exec deploy/api -- curl -f http://localhost:8000/ready

# If fails, fix application /ready endpoint

# Or adjust probe configuration
# deploy/helm/api/values.yaml
readinessProbe:
  failureThreshold: 5     # More lenient
  periodSeconds: 15
  initialDelaySeconds: 10

make helm-up-dev
```

### Cause F: Network Policy Blocking

**Diagnosis**:
```bash
kubectl -n october get networkpolicy

# If policies exist, they may block traffic
```

**Solution**:
```bash
# Temporarily delete NetworkPolicies for testing
kubectl -n october delete networkpolicy --all

# Test service again
kubectl -n october port-forward svc/api 8080:80
curl http://localhost:8080/healthz

# If works → NetworkPolicy issue
# Recreate policies with correct rules
```

## ✅ Verification

### 1. Check endpoints exist
```bash
kubectl -n october get endpoints api
# Should show pod IP(s)
```

### 2. Test from within cluster
```bash
kubectl -n october run test --rm -it --image=curlimages/curl -- sh
# Inside test pod:
curl http://api.october.svc.cluster.local/healthz
# Should return: {"status":"ok"}
```

### 3. Test via port-forward
```bash
kubectl -n october port-forward svc/api 8080:80 &
curl http://localhost:8080/healthz
pkill -f "port-forward"
```

### 4. Test via Ingress
```bash
MINIKUBE_IP=$(minikube ip)
curl http://api.$MINIKUBE_IP.nip.io/healthz
```

## 📊 Diagnosis Flow

```
Service Unreachable
    ↓
Service exists? → NO → Deploy service
    ↓ YES
Endpoints exist? → NO → Fix pod issues (see runbooks)
    ↓ YES
Ports match? → NO → Fix port configuration
    ↓ YES
App listening? → NO → Fix app to bind 0.0.0.0
    ↓ YES
NetworkPolicy? → YES → Review/fix policies
    ↓ NO
Readiness failing? → YES → Fix /ready endpoint
    ↓ NO
Check application logs
```

## 📚 Related Documentation

- [Troubleshooting - Networking](../TROUBLESHOOTING.md#networking-issues)
- [Architecture - Network Flow](../ARCHITECTURE.md#data-flow)
- [crashloopbackoff.md](crashloopbackoff.md)

## 🔑 Quick Reference

```bash
# Diagnosis
kubectl -n october get svc api                  # Service exists?
kubectl -n october get endpoints api            # Endpoints exist?
kubectl -n october get pods -l app=api          # Pods healthy?
kubectl -n october exec deploy/api -- netstat -tuln | grep 8000  # Listening?

# Testing
kubectl -n october port-forward svc/api 8080:80  # Port-forward
kubectl run test --rm -it --image=curlimages/curl -- curl http://api.october.svc.cluster.local/healthz

# Common fixes
make helm-up-dev                                # Redeploy
kubectl -n october rollout restart deploy/api   # Restart pods
kubectl -n october delete networkpolicy --all   # Remove blocking policies
```

---

**Last Updated**: 2025-10-19
