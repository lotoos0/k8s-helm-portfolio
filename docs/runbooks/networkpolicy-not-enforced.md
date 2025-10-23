# RUNBOOK: NetworkPolicy Not Enforced

## 📋 Incident Overview

**Trigger**: NetworkPolicy resources exist but traffic is not being blocked/allowed as expected
**Severity**: HIGH - Security policies not enforced, potential unauthorized network access
**Expected Resolution Time**: 15-30 minutes (includes CNI installation if needed)

## 🚨 Symptoms

```bash
$ kubectl get networkpolicy -n october
NAME                           POD-SELECTOR   AGE
default-deny-all               <none>         10m
api-allow-egress-redis         app=api        10m

$ kubectl exec -n october deploy/api -- curl -m 5 http://1.1.1.1
# ❌ Connection succeeds (should be blocked by default-deny-all)
<!DOCTYPE html>...
```

**Indicators**:
- NetworkPolicy resources exist (`kubectl get networkpolicy`)
- Pods can connect to destinations that should be blocked
- No errors in pod/deployment logs
- Traffic flows as if NetworkPolicy doesn't exist

## 🔍 Step 1: Verify CNI Plugin Supports NetworkPolicy

NetworkPolicy enforcement requires a CNI plugin that implements the NetworkPolicy API. Not all CNI plugins support this feature.

### Check which CNI is running

```bash
# Check for common CNI pods in kube-system
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|canal'
```

**Expected output (one of these)**:
```bash
# Calico (✅ supports NetworkPolicy)
calico-kube-controllers-xxx   1/1   Running
calico-node-xxx               1/1   Running

# Cilium (✅ supports NetworkPolicy)
cilium-xxx                    1/1   Running
cilium-operator-xxx           1/1   Running

# Weave (✅ supports NetworkPolicy)
weave-net-xxx                 2/2   Running
```

**If output is empty** ❌ - You likely have a basic CNI (bridge/kindnet) that **does NOT support NetworkPolicy**

### Verify CNI configuration

```bash
# On Minikube
minikube ssh -- cat /etc/cni/net.d/*

# On standard Kubernetes
ls -la /etc/cni/net.d/
```

**Look for**:
- `calico.conflist` (Calico)
- `cilium.conf` (Cilium)
- `10-weave.conflist` (Weave)
- `bridge` or `kindnet` = ❌ No NetworkPolicy support

## 🔧 Step 2: Solution - Install NetworkPolicy-capable CNI

### Option A: Minikube with Calico (Recommended for dev/test)

**Important**: You MUST recreate the cluster. You cannot add Calico to an existing Minikube cluster.

```bash
# 1. Save your workloads (optional)
kubectl get all -n october -o yaml > backup-october.yaml

# 2. Delete existing cluster
minikube delete

# 3. Create new cluster WITH Calico
minikube start --cni=calico --memory=4096 --cpus=2 --kubernetes-version=v1.31.0

# 4. Verify Calico is running
kubectl get pods -n kube-system | grep calico

# Expected output:
# calico-kube-controllers-xxx   1/1   Running
# calico-node-xxx               1/1   Running

# 5. Wait for Calico to be ready (may take 30-60 seconds)
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=120s
```

### Option B: Production Cluster - Install Calico Manually

**⚠️ WARNING**: Only do this on a new cluster or during maintenance window. Installing CNI on existing cluster can disrupt networking.

```bash
# 1. Download Calico manifest
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# 2. Review the manifest (check CIDR matches your cluster)
grep CALICO_IPV4POOL_CIDR calico.yaml
# Should match your pod network CIDR (usually 10.244.0.0/16 or 192.168.0.0/16)

# 3. Apply Calico
kubectl apply -f calico.yaml

# 4. Verify installation
kubectl get pods -n kube-system | grep calico
kubectl get nodes  # Should show Ready

# 5. Check Calico status
kubectl exec -n kube-system calico-node-xxx -- calicoctl node status
```

### Option C: Alternative CNIs

**Cilium** (advanced features, eBPF-based):
```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin

# Install Cilium
cilium install
cilium status --wait
```

**Weave** (simple, good for small clusters):
```bash
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
```

## 🧪 Step 3: Redeploy Application & NetworkPolicies

After installing CNI, redeploy your application:

```bash
# 1. Load container images (Minikube only)
minikube image load your-app:tag

# 2. Deploy application
helm upgrade --install app ./deploy/helm/api -n october \
  --set api.ingress.host=october.local \
  --create-namespace

# 3. Verify NetworkPolicies are created
kubectl get networkpolicy -n october

# Expected:
# NAME                           POD-SELECTOR   AGE
# default-deny-all               <none>         30s
# api-allow-from-ingress-nginx   app=api        30s
# api-allow-egress-redis         app=api        30s
# worker-allow-egress-redis      app=worker     30s
# allow-egress-dns               <none>         30s
# redis-allow-from-api-worker    app=redis      30s
```

## ✅ Step 4: Verify NetworkPolicy Enforcement

### Test 1: Default Deny Works (Internet should be BLOCKED)

```bash
# This should TIMEOUT (connection blocked)
kubectl exec -n october deploy/api -- python3 -c \
  "import socket; s=socket.socket(); s.settimeout(5); s.connect(('1.1.1.1', 80))"

# Expected output:
# TimeoutError: timed out
# ✅ PASS - Internet is blocked
```

### Test 2: Allowed Connections Work

```bash
# API to Redis should WORK
kubectl exec -n october deploy/api -- python3 -c \
  "import socket; s=socket.socket(); s.settimeout(3); s.connect(('redis', 6379)); print('✅ Connected')"

# Expected output:
# ✅ Connected
# ✅ PASS - Allowed connection works

# Worker to Redis should WORK
kubectl exec -n october deploy/worker -- python3 -c \
  "import socket; s=socket.socket(); s.settimeout(3); s.connect(('redis', 6379)); print('✅ Connected')"

# Expected output:
# ✅ Connected
# ✅ PASS - Allowed connection works
```

### Test 3: DNS Resolution Works

```bash
# DNS should work (allowed by allow-egress-dns policy)
kubectl exec -n october deploy/api -- nslookup redis

# Expected output:
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      redis
# Address 1: 10.x.x.x redis.october.svc.cluster.local
# ✅ PASS - DNS resolution works
```

### Test 4: Check Calico NetworkPolicy Status

```bash
# Describe a specific policy
kubectl describe networkpolicy default-deny-all -n october

# Check Calico logs for errors
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50 | grep -i error

# Verify pod has network interface managed by Calico
kubectl exec -n october deploy/api -- ip addr show | grep cali
# Should see interface like: cali123abc456@if7
```

## 🔍 Common Issues & Solutions

### Issue 1: Pods can't communicate even with allow rules

**Symptom**: API can't connect to Redis despite `api-allow-egress-redis` policy

**Root Cause**: Missing INGRESS policy on Redis side

**Solution**:
```yaml
# Redis needs INGRESS policy to accept connections
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-allow-from-api-worker
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
        - podSelector:
            matchLabels:
              app: worker
      ports:
        - protocol: TCP
          port: 6379
```

**Remember**: With default-deny, you need **both**:
- EGRESS policy on source pod (API → Redis)
- INGRESS policy on destination pod (Redis accepts from API)

### Issue 2: DNS doesn't work after enabling NetworkPolicy

**Symptom**: Pods can't resolve domain names

**Solution**: Add DNS egress policy:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-dns
spec:
  podSelector: {}  # All pods
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### Issue 3: Ingress traffic blocked from Ingress Controller

**Symptom**: External traffic can't reach API through Ingress

**Solution**: Allow from ingress-nginx namespace:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-from-ingress-nginx
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8000
```

### Issue 4: Calico pods stuck in Init or CrashLoopBackOff

**Symptom**: `calico-node` pods not starting

**Check**:
```bash
kubectl logs -n kube-system calico-node-xxx -c install-cni
kubectl describe pod -n kube-system calico-node-xxx
```

**Common causes**:
- Conflicting CNI configuration in `/etc/cni/net.d/`
- Wrong pod CIDR (check cluster vs Calico configuration)
- Missing kernel modules (iptables, ip_tables, etc.)

**Solution**:
```bash
# Check kernel modules (on node)
minikube ssh -- lsmod | grep -E 'ip_tables|iptable'

# If missing, load modules
minikube ssh -- sudo modprobe ip_tables
minikube ssh -- sudo modprobe iptable_filter

# Restart Calico
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

## 🛡️ Prevention & Best Practices

### 1. Always use NetworkPolicy-capable CNI

**For Minikube**:
```bash
# Always create with --cni=calico
minikube start --cni=calico --memory=4096 --cpus=2
```

**For Production**:
- Install Calico/Cilium/Weave during cluster bootstrap
- Document CNI choice in cluster setup documentation

### 2. Test NetworkPolicy in CI/CD

Add validation to your pipeline:
```bash
# In CI/CD after deploy
- name: Verify NetworkPolicy enforcement
  run: |
    # Test that internet is blocked
    ! kubectl exec -n october deploy/api -- timeout 5 curl http://1.1.1.1

    # Test that Redis is accessible
    kubectl exec -n october deploy/api -- nc -zv redis 6379
```

### 3. Use policy templates

Create reusable policy templates:
```yaml
# templates/networkpolicy-egress-redis.yaml
{{- if .Values.redis.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Values.component }}-allow-egress-redis
spec:
  podSelector:
    matchLabels:
      app: {{ .Values.component }}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
{{- end }}
```

### 4. Monitor NetworkPolicy effectiveness

```bash
# Check policy count
kubectl get networkpolicy --all-namespaces

# Audit policies regularly
kubectl get networkpolicy -n october -o yaml > networkpolicies-backup.yaml

# Use Calico policy tester (if available)
calicoctl policy-board
```

### 5. Document network architecture

Create a network flow diagram:
```
[Ingress NGINX] --✅--> [API pods]
                          |
                          ✅ (egress to Redis)
                          v
                      [Redis pod] <--✅-- [Worker pods]
                          ^
                          | (ingress from API/Worker)
                          ✅

[API/Worker] --❌--> [Internet] (blocked by default-deny)
[API/Worker] --✅--> [kube-dns] (allowed by allow-egress-dns)
```

## 📚 Related Documentation

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico NetworkPolicy Guide](https://docs.tigera.io/calico/latest/network-policy/)
- [Project Calico Installation](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)

## 🔗 Related Runbooks

- [CrashLoopBackOff](./crashloopbackoff.md) - If Calico pods fail to start
- [Service Unreachable](./service_unreachable.md) - Network connectivity issues
- [Ingress Not Working](./ingress_not_working.md) - If ingress-nginx can't reach pods

## 📊 Summary Checklist

After following this runbook, verify:

- [ ] NetworkPolicy-capable CNI installed (Calico/Cilium/Weave)
- [ ] Calico/CNI pods running in kube-system namespace
- [ ] NetworkPolicy resources created in application namespace
- [ ] Default-deny policy blocks unauthorized traffic
- [ ] Allowed connections work (Redis, DNS, Ingress)
- [ ] DNS resolution functional
- [ ] Application health checks passing

**If all checks pass**: NetworkPolicy is properly enforced! ✅

**If issues persist**: Check CNI logs and consult [Calico Troubleshooting Guide](https://docs.tigera.io/calico/latest/operations/troubleshoot/)

---

**Last Updated**: 2025-10-22
**Tested On**: Minikube v1.37.0, Kubernetes v1.31.0, Calico v3.28.0
**Author**: DevOps Team
