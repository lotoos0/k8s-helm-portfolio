# RUNBOOK: Ingress Not Working

## 📋 Incident Overview

**Trigger**: Cannot access service via Ingress URL (404, 503, or connection refused)
**Severity**: MEDIUM-HIGH - Service accessible via port-forward but not via Ingress
**Expected Resolution Time**: 10-20 minutes

## 🚨 Symptoms

```bash
$ curl http://api.192.168.49.2.nip.io/healthz
curl: (7) Failed to connect to api.192.168.49.2.nip.io port 80: Connection refused
```

or

```bash
$ curl http://api.192.168.49.2.nip.io/healthz
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

or

```bash
$ curl http://api.192.168.49.2.nip.io/healthz
<html>
<head><title>503 Service Temporarily Unavailable</title></head>
...
```

## 🔍 Step 1: Verify Service Works

**First, confirm the service itself is healthy:**

```bash
# Test via port-forward (bypass Ingress)
kubectl -n october port-forward svc/api 8080:80 &
curl http://localhost:8080/healthz

# If this works → INGRESS ISSUE
# If this fails → SERVICE/POD ISSUE (see service_unreachable.md)
```

Kill port-forward:
```bash
pkill -f "port-forward"
```

## 🛠️ Step 2: Common Causes & Solutions

### Cause A: Ingress Controller Not Running

**Diagnosis**:
```bash
# Check if Ingress Controller exists
kubectl -n ingress-nginx get pods

# Should show running pods:
# NAME                                        READY   STATUS
# ingress-nginx-controller-xxxxx             1/1     Running
```

**If no pods or namespace doesn't exist → CONTROLLER NOT ENABLED**

**Solution**:
```bash
# Enable Ingress addon
make k8s-enable-ingress

# Or manually:
minikube addons enable ingress

# Wait for controller to be ready (can take 1-2 minutes)
kubectl -n ingress-nginx wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=120s

# Verify
kubectl -n ingress-nginx get pods
```

### Cause B: Incorrect Ingress Host

**Diagnosis**:
```bash
# Check Ingress configuration
kubectl -n october get ingress api-ingress -o yaml

# Look at host field:
spec:
  rules:
  - host: api.192.168.49.2.nip.io  # ← Should match Minikube IP

# Get actual Minikube IP
minikube ip
# Example: 192.168.49.2
```

**If host doesn't match Minikube IP → WRONG HOST**

**Solution**:
```bash
# Get Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Correct host should be: api.$MINIKUBE_IP.nip.io"

# Update Ingress
kubectl -n october patch ingress api-ingress -p "{\"spec\":{\"rules\":[{\"host\":\"api.$MINIKUBE_IP.nip.io\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"api\",\"port\":{\"number\":80}}}}]}}]}}"

# Or redeploy with Helm
# Edit: deploy/helm/api/values-dev.yaml
api:
  ingress:
    host: api.192.168.49.2.nip.io  # Update with correct IP

make helm-up-dev

# Verify
kubectl -n october get ingress api-ingress -o yaml | grep host
```

### Cause C: DNS Resolution Issues (nip.io)

**Diagnosis**:
```bash
# Test DNS resolution
nslookup api.192.168.49.2.nip.io

# If fails → DNS ISSUE
```

**Solution Option 1: Use /etc/hosts**
```bash
# Add to /etc/hosts
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP api.$MINIKUBE_IP.nip.io" | sudo tee -a /etc/hosts

# Test
curl http://api.$MINIKUBE_IP.nip.io/healthz
```

**Solution Option 2: Use Host header**
```bash
# Bypass DNS, use IP with Host header
MINIKUBE_IP=$(minikube ip)
curl -H "Host: api.$MINIKUBE_IP.nip.io" http://$MINIKUBE_IP/healthz
```

**Solution Option 3: Use port-forward** (fallback)
```bash
# Access via port-forward instead
make k8s-port-api
curl http://localhost:8080/healthz
```

### Cause D: Service Has No Endpoints

**Diagnosis**:
```bash
# Check service endpoints
kubectl -n october get endpoints api

# Should show pod IPs:
# NAME   ENDPOINTS           AGE
# api    10.244.0.5:8000     5m

# If ENDPOINTS column is empty → NO HEALTHY PODS
```

**Solution**:
```bash
# Check why pods aren't ready
kubectl -n october get pods -l app=api

# If pods not ready, check:
kubectl -n october describe pod -l app=api
kubectl -n october logs -l app=api

# Fix pod issues first (see crashloopbackoff.md, image_pull_backoff.md)
# Then endpoints will auto-populate
```

### Cause E: Wrong Service Port Configuration

**Diagnosis**:
```bash
# Check Ingress backend configuration
kubectl -n october get ingress api-ingress -o yaml

# Look for:
backend:
  service:
    name: api
    port:
      number: 80  # ← Should match Service port

# Check Service port
kubectl -n october get svc api -o yaml | grep -A 3 "ports:"

# Should show:
ports:
- port: 80         # ← Ingress connects here
  targetPort: 8000 # → Forwards to container
```

**If ports don't match → PORT MISMATCH**

**Solution**:
```bash
# Update Ingress to use correct port
# Edit: deploy/helm/api/templates/ingress-api.yaml
# Or update via Helm values

make helm-up-dev
```

### Cause F: Path Configuration Issues

**Diagnosis**:
```bash
kubectl -n october get ingress api-ingress -o yaml | grep -A 5 "paths:"

# Check:
paths:
- path: /          # ← Should be / for catch-all
  pathType: Prefix # ← Should be Prefix
```

**Solution**:
```yaml
# Correct configuration:
paths:
- path: /
  pathType: Prefix
  backend:
    service:
      name: api
      port:
        number: 80
```

### Cause G: Ingress Class Missing/Incorrect

**Diagnosis**:
```bash
kubectl -n october get ingress api-ingress -o yaml | grep ingressClassName

# Should show:
ingressClassName: nginx
```

**Solution**:
```yaml
# Add to Ingress manifest:
spec:
  ingressClassName: nginx
  rules:
    ...
```

## ✅ Step 3: Verification

### 1. Check Ingress Controller is running
```bash
kubectl -n ingress-nginx get pods
# Should be: Running, READY 1/1
```

### 2. Check Ingress resource
```bash
kubectl -n october get ingress

# Should show:
# NAME          CLASS   HOSTS                         ADDRESS         PORTS
# api-ingress   nginx   api.192.168.49.2.nip.io      192.168.49.2    80
```

### 3. Check service endpoints
```bash
kubectl -n october get endpoints api
# Should show pod IP(s)
```

### 4. Test with curl
```bash
MINIKUBE_IP=$(minikube ip)

# Method 1: Direct URL
curl -f http://api.$MINIKUBE_IP.nip.io/healthz

# Method 2: With Host header (if DNS fails)
curl -f -H "Host: api.$MINIKUBE_IP.nip.io" http://$MINIKUBE_IP/healthz

# Should return: {"status":"ok"}
```

### 5. Test all endpoints
```bash
MINIKUBE_IP=$(minikube ip)
BASE_URL="http://api.$MINIKUBE_IP.nip.io"

curl -s $BASE_URL/healthz  # Should: {"status":"ok"}
curl -s $BASE_URL/ready    # Should: {"ready":true}
curl -s $BASE_URL/metrics | head -10  # Should: prometheus metrics
```

### 6. Check Ingress Controller logs
```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50

# Should show successful requests:
# 192.168.49.1 - - [19/Oct/2025:12:34:56 +0000] "GET /healthz HTTP/1.1" 200
```

## 🔧 Step 4: Advanced Debugging

### Enable Ingress Controller Debug Logs
```bash
kubectl -n ingress-nginx edit deploy ingress-nginx-controller

# Add to container args:
args:
  - --v=3  # Increase verbosity

# Check logs
kubectl -n ingress-nginx logs -f deploy/ingress-nginx-controller
```

### Test from within cluster
```bash
# Create test pod
kubectl -n october run test-curl --rm -it --image=curlimages/curl -- sh

# Inside test pod:
curl http://api.october.svc.cluster.local/healthz  # Direct to Service
curl -H "Host: api.192.168.49.2.nip.io" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/healthz  # Via Ingress
```

### Check Ingress Controller configuration
```bash
# Get nginx config from controller
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -A 10 "api.192"
```

## 📊 Post-Incident

### Document the issue
- What was the symptom?
- What was the root cause?
- How long was service unavailable?

### Preventive measures
- Add Ingress health check to CI/CD
- Monitor Ingress Controller status
- Document correct Minikube IP update procedure

## 📚 Related Documentation

- [Deployment Guide - Ingress](../DEPLOYMENT_GUIDE.md#option-b-ingress-recommended)
- [Troubleshooting Guide](../TROUBLESHOOTING.md#issue-ingress-not-working)
- [kubectl no route to host](kubectl_no_route_to_host.md)

## 🔑 Quick Reference

```bash
# Fastest diagnosis path
kubectl -n ingress-nginx get pods                    # Controller running?
kubectl -n october get ingress                       # Ingress exists?
kubectl -n october get endpoints api                 # Service has endpoints?
minikube ip                                          # Get correct IP

# Common fixes
make k8s-enable-ingress                             # Enable controller
make k8s-apply-ingress                              # Redeploy Ingress
MINIKUBE_IP=$(minikube ip); echo "Use: api.$MINIKUBE_IP.nip.io"

# Verification
curl -f http://api.$(minikube ip).nip.io/healthz   # Test endpoint
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller  # Check logs

# Fallback
make k8s-port-api                                   # Port-forward instead
```

---

**Last Updated**: 2025-10-19
**Version**: 1.0
**Tested On**: Minikube 1.32, Kubernetes 1.28, NGINX Ingress
