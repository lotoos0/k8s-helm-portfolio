# Security Documentation

This document outlines the security features, practices, and configurations implemented in the October DevOps project.

## 📋 Table of Contents

- [Security Overview](#security-overview)
- [Container Security](#container-security)
- [Network Security](#network-security)
- [Secrets Management](#secrets-management)
- [Access Control & RBAC](#access-control--rbac)
- [High Availability & Resilience](#high-availability--resilience)
- [Monitoring & Compliance](#monitoring--compliance)
- [Security Checklist](#security-checklist)
- [Threat Model](#threat-model)
- [Incident Response](#incident-response)

---

## 🛡️ Security Overview

The project implements **defense-in-depth** security with multiple layers:

1. **Container Security** - Non-root execution, read-only filesystems, dropped capabilities
2. **Network Isolation** - NetworkPolicy with zero-trust default-deny model
3. **Secrets Management** - Kubernetes Secrets with environment variable injection
4. **Access Control** - RBAC with dedicated ServiceAccounts
5. **Image Security** - Trivy scanning in CI/CD pipeline
6. **High Availability** - PodDisruptionBudgets for resilience

**Security Philosophy**: **Least Privilege** + **Zero Trust** + **Defense in Depth**

---

## 🐳 Container Security

### Non-Root Containers

All application containers run as **non-root user** (UID 10001):

```yaml
# values.yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
```

**Benefits**:
- ✅ Prevents privilege escalation attacks
- ✅ Limits damage if container is compromised
- ✅ Complies with security best practices (CIS Benchmarks, NSA/CISA Hardening Guide)

**Verification**:
```bash
# Check user inside container
kubectl exec -n october deploy/api -- id
# Output: uid=10001 gid=10001 groups=10001
```

---

### Read-Only Root Filesystem

Containers use **read-only root filesystem** with writable `/tmp`:

```yaml
# values.yaml
containerSecurityContext:
  readOnlyRootFilesystem: true

tmpVolume:
  enabled: true
  mountPath: /tmp
```

**Benefits**:
- ✅ Prevents runtime modification of binaries
- ✅ Blocks malware installation
- ✅ Reduces attack surface

**Verification**:
```bash
# Try to write to root filesystem (should fail)
kubectl exec -n october deploy/api -- touch /test
# Error: Read-only file system

# Verify /tmp is writable
kubectl exec -n october deploy/api -- touch /tmp/test && echo "✅ /tmp is writable"
```

---

### Dropped Capabilities

All **Linux capabilities** are dropped by default:

```yaml
# values.yaml
containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

**Capabilities Dropped**:
- `CAP_NET_ADMIN` - Network configuration
- `CAP_SYS_ADMIN` - System administration
- `CAP_SETUID` / `CAP_SETGID` - Change user/group ID
- **ALL** other Linux capabilities

**Benefits**:
- ✅ Prevents container breakout attempts
- ✅ Limits syscall access
- ✅ Reduces kernel attack surface

---

### Image Scanning (Trivy)

All images are scanned for vulnerabilities in CI/CD:

```yaml
# .github/workflows/cd.yml
- name: Trivy Scan
  uses: aquasecurity/trivy-action@master
  with:
    severity: 'HIGH,CRITICAL'
    exit-code: '1'  # Fail pipeline on vulnerabilities
```

**Scan Targets**:
- Operating system packages (Alpine APK)
- Python dependencies (pip packages)
- Known CVEs in application code

**Policy**: Pipeline **fails** on HIGH/CRITICAL vulnerabilities

**Manual Scan**:
```bash
# Scan local image
trivy image october-api:dev

# Scan with severity filter
trivy image --severity HIGH,CRITICAL october-api:dev
```

---

## 🌐 Network Security

### NetworkPolicy Overview

The project implements **zero-trust networking** with Kubernetes NetworkPolicy:

**Default Posture**: **DENY ALL** traffic (ingress & egress)

**Explicit Allow Rules**:
1. Ingress NGINX → API pods (port 8000)
2. API pods → Redis (port 6379)
3. Worker pods → Redis (port 6379)
4. All pods → kube-dns (port 53 TCP/UDP)
5. Redis accepts from API/Worker (port 6379)

**Total Policies**: 6 NetworkPolicy resources

---

### NetworkPolicy Details

#### 1. Default Deny All

Blocks **all** ingress and egress traffic by default:

```yaml
# networkpolicy-default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}  # Applies to all pods
  policyTypes:
    - Ingress
    - Egress
```

**Impact**: Without explicit allow rules, pods cannot communicate

---

#### 2. Allow Ingress from NGINX to API

```yaml
# networkpolicy-api-ingress.yaml
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8000  # Container port
```

**Purpose**: Allow external HTTP traffic via Ingress Controller

---

#### 3. Allow API Egress to Redis

```yaml
# networkpolicy-api-redis.yaml
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
```

**Purpose**: API can connect to Redis for Celery tasks

---

#### 4. Allow Worker Egress to Redis

```yaml
# networkpolicy-worker-redis.yaml
spec:
  podSelector:
    matchLabels:
      app: worker
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
```

**Purpose**: Worker can connect to Redis for task queue

---

#### 5. Allow DNS Resolution

```yaml
# networkpolicy-egress-dns.yaml
spec:
  podSelector: {}  # All pods
  policyTypes: [Egress]
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

**Purpose**: Pods can resolve DNS names (e.g., `redis` → `10.96.x.x`)

---

#### 6. Allow Redis Ingress from API/Worker

```yaml
# networkpolicy-redis-ingress.yaml
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes: [Ingress]
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

**Purpose**: Redis accepts connections only from API and Worker

---

### Network Flow Diagram

```
┌─────────────────┐
│ Internet        │ ❌ BLOCKED (default-deny)
└─────────────────┘

┌─────────────────┐
│ Ingress NGINX   │
│ (ingress-nginx) │
└────────┬────────┘
         │ ✅ Allow (port 8000)
         ▼
    ┌────────┐
    │  API   │
    │  pod   │
    └───┬────┘
        │ ✅ Allow egress to Redis (6379)
        │ ✅ Allow DNS (53)
        │ ❌ Internet blocked
        ▼
   ┌─────────┐  ◄─── ✅ Allow ingress from API/Worker
   │  Redis  │
   │   pod   │
   └─────────┘
        ▲
        │ ✅ Allow egress to Redis (6379)
        │
   ┌────────┐
   │ Worker │
   │  pod   │
   └────────┘
```

---

### NetworkPolicy Verification

**Quick Test**:
```bash
# Should work (allowed)
kubectl exec -n october deploy/api -- python3 -c \
  "import socket; s=socket.socket(); s.connect(('redis', 6379)); print('✅ Connected')"

# Should timeout (blocked)
kubectl exec -n october deploy/api -- python3 -c \
  "import socket; s=socket.socket(); s.settimeout(5); s.connect(('1.1.1.1', 80))"
# Expected: TimeoutError (internet blocked)
```

**List Policies**:
```bash
kubectl get networkpolicy -n october
```

**Expected Output**:
```
NAME                           POD-SELECTOR   AGE
default-deny-all               <none>         10m
api-allow-from-ingress-nginx   app=api        10m
api-allow-egress-redis         app=api        10m
worker-allow-egress-redis      app=worker     10m
allow-egress-dns               <none>         10m
redis-allow-from-api-worker    app=redis      10m
```

---

### CNI Plugin Requirement

⚠️ **NetworkPolicy requires a CNI plugin** that supports the NetworkPolicy API.

**Supported CNIs**:
- ✅ **Calico** (recommended, used in this project)
- ✅ **Cilium** (eBPF-based, advanced features)
- ✅ **Weave Net**
- ❌ Bridge/Kindnet (default in some Minikube setups) - **NO NetworkPolicy support**

**Minikube Setup**:
```bash
# Create cluster with Calico
minikube start --cni=calico --memory=4096 --cpus=2
```

**Verification**:
```bash
# Check CNI pods
kubectl get pods -n kube-system | grep calico

# Expected:
# calico-kube-controllers-xxx   1/1   Running
# calico-node-xxx               1/1   Running
```

**Troubleshooting**: See [NetworkPolicy Runbook](runbooks/networkpolicy-not-enforced.md)

---

## 🔐 Secrets Management

### Kubernetes Secrets

Sensitive data is stored in **Kubernetes Secrets** (base64 encoded at rest):

```yaml
# templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: {{ .Values.namespace }}
type: Opaque
data:
  {{- range $key, $val := .Values.secrets }}
  {{ $key }}: {{ $val | b64enc | quote }}
  {{- end }}
```

**Usage**:
```yaml
# values.yaml
secrets:
  DB_PASSWORD: "changeme"
  API_KEY: "secret123"
```

**Injection**:
```yaml
# Deployment
envFrom:
  - secretRef:
      name: app-secret
```

---

### Environment Variables

Non-sensitive configuration uses **ConfigMap**:

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_NAME: "DevOps October API"
  APP_ENV: "dev"
  BROKER_URL: "redis://redis:6379/0"
```

**Best Practices**:
- ✅ Use **Secrets** for: passwords, API keys, certificates
- ✅ Use **ConfigMap** for: application config, URLs, feature flags
- ❌ **NEVER** commit secrets to Git (use `.gitignore`)
- ❌ **NEVER** log secrets (sanitize logs)

---

### Secret Rotation

**Manual Rotation**:
```bash
# Update secret
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD=new-password \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl rollout restart deployment/api -n october
```

**Automated Options** (not implemented):
- External Secrets Operator (sync from Vault, AWS Secrets Manager)
- Sealed Secrets (encrypted secrets in Git)
- cert-manager (TLS certificate rotation)

---

## 🔑 Access Control & RBAC

### ServiceAccount

Each deployment uses a **dedicated ServiceAccount**:

```yaml
# templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: october
```

**Usage**:
```yaml
# Deployment
spec:
  serviceAccountName: app-sa
```

**Benefits**:
- ✅ Pods use specific identity (not default)
- ✅ Enables fine-grained RBAC
- ✅ Audit trail for pod actions

---

### RBAC (Future Enhancement)

**Current State**: Using default permissions

**Recommended** (for production):
```yaml
# Role limiting API server access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
  # No access to secrets, deployments, etc.
```

---

## 🏗️ High Availability & Resilience

### PodDisruptionBudget (PDB)

**Prevents** too many pods from being terminated simultaneously:

```yaml
# templates/pdb-api.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
spec:
  minAvailable: 50%  # At least 50% of pods must remain
  selector:
    matchLabels:
      app: api
```

**Configuration**:
- **API**: `minAvailable: 50%` (ensures availability during drains)
- **Worker**: `minAvailable: 0` (allows drain for single-replica deployments)

**Use Cases**:
- ✅ Cluster upgrades (node drains)
- ✅ Autoscaling down
- ✅ Manual pod eviction

**Verification**:
```bash
kubectl get pdb -n october

# Try to evict pod (respects PDB)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

---

### PriorityClass (Optional)

**Defines pod scheduling priority** (higher = more important):

```yaml
# templates/priorityclass.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: app-medium
value: 1000  # 0-1000 = user apps, 1000+ = system
globalDefault: false
description: "Business app pods"
```

**Status**: Disabled by default (`priorityClass.enabled: false`)

**When to Enable**:
- Multi-tenant clusters (prioritize critical apps)
- Resource contention scenarios
- Production environments with mixed workloads

---

## 📊 Monitoring & Compliance

### Security Alerts

**PrometheusRule** includes security-relevant alerts:

```yaml
# CrashLoopBackOff (potential security incident)
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
  annotations:
    summary: "Pod {{ $labels.pod }} is crash looping"
```

**Additional Monitoring** (recommended):
- Failed login attempts (application logs)
- Unauthorized API calls (HTTP 401/403)
- Secret access patterns (Kubernetes audit logs)
- Image pull failures (potential supply chain attack)

---

### Audit Logging

**Current State**: Not enabled (requires API server configuration)

**Recommended** (production):
```yaml
# kube-apiserver flags
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit.log
--audit-log-maxage=30
```

**What to Audit**:
- Secret access (who read which secret?)
- RBAC changes (role/rolebinding modifications)
- Pod exec commands (container access)
- NetworkPolicy changes

---

### Compliance Scanning

**Manual Scans**:
```bash
# Trivy cluster scan
trivy k8s --report summary cluster

# kubescape (NSA/CISA hardening guide)
kubescape scan framework nsa

# kube-bench (CIS Kubernetes Benchmark)
kube-bench run --targets node,master
```

**CI/CD Integration**: Trivy image scanning (already implemented)

---

## ✅ Security Checklist

### Container Security
- [x] Containers run as non-root (UID 10001)
- [x] Read-only root filesystem enabled
- [x] All Linux capabilities dropped
- [x] Privilege escalation prevented
- [x] Images scanned with Trivy (fail on HIGH/CRITICAL)
- [x] Multi-stage Docker builds (minimal attack surface)

### Network Security
- [x] NetworkPolicy default-deny implemented
- [x] Explicit allow rules for required traffic
- [x] Ingress isolated to NGINX namespace
- [x] DNS resolution allowed
- [x] Internet egress blocked (except allowed services)
- [x] CNI plugin supports NetworkPolicy (Calico)

### Secrets & Configuration
- [x] Secrets stored in Kubernetes Secrets (not ConfigMap)
- [x] Secrets injected as environment variables
- [x] No secrets in Git repository
- [ ] Secret rotation process (manual only)
- [ ] External secret management (not implemented)

### Access Control
- [x] Dedicated ServiceAccount per deployment
- [ ] RBAC roles limiting permissions (using defaults)
- [ ] Pod Security Standards enforcement (not configured)

### High Availability
- [x] PodDisruptionBudget configured (API: 50%, Worker: 0)
- [x] Health probes (startup, liveness, readiness)
- [x] HPA for automatic scaling
- [ ] PriorityClass (disabled by default)

### Monitoring
- [x] Prometheus metrics exposed
- [x] PrometheusRule alerts (CrashLoop, CPU)
- [x] Health check endpoints
- [ ] Security-specific alerts (not configured)
- [ ] Audit logging (not enabled)

---

## 🚨 Threat Model

### Identified Threats

| Threat | Mitigation | Status |
|--------|------------|--------|
| **Container Escape** | Non-root user, dropped capabilities, read-only FS | ✅ Mitigated |
| **Lateral Movement** | NetworkPolicy default-deny, pod isolation | ✅ Mitigated |
| **Secret Exposure** | Kubernetes Secrets, no Git commits | ✅ Mitigated |
| **Malicious Image** | Trivy scanning, image signing (not impl.) | ⚠️ Partial |
| **Supply Chain Attack** | Dependency scanning, pinned versions | ⚠️ Partial |
| **Privilege Escalation** | RBAC (defaults), PSP/PSS (not configured) | ⚠️ Partial |
| **DoS Attack** | Resource limits, PDB, HPA | ✅ Mitigated |
| **Data Exfiltration** | NetworkPolicy egress restrictions | ✅ Mitigated |

---

### Attack Surface

**Entry Points**:
1. **Ingress NGINX** → API pods (port 8000)
   - Mitigation: Rate limiting (not impl.), WAF (not impl.)
2. **Container Images** (supply chain)
   - Mitigation: Trivy scanning, trusted registries
3. **Kubernetes API** (unauthorized access)
   - Mitigation: RBAC (defaults), network isolation
4. **Dependencies** (Python packages)
   - Mitigation: Dependency scanning, version pinning

**Attack Scenarios**:
- **Scenario 1**: Attacker exploits API vulnerability
  - Defense: Read-only FS (can't install tools), NetworkPolicy (can't exfiltrate data), Non-root (limited damage)
- **Scenario 2**: Compromised container image
  - Defense: Trivy blocks deployment, immutable infrastructure
- **Scenario 3**: Lateral movement after initial compromise
  - Defense: NetworkPolicy blocks pod-to-pod communication (except allowed paths)

---

## 🔧 Incident Response

### Security Incident Runbooks

**Available Runbooks**:
- [CrashLoopBackOff](runbooks/crashloopbackoff.md) - Pod restart loops (potential exploit attempt)
- [NetworkPolicy Not Enforced](runbooks/networkpolicy-not-enforced.md) - Network isolation failure
- [Image Pull Backoff](runbooks/image_pull_backoff.md) - Image integrity issues

### Incident Response Steps

**1. Detection**
```bash
# Check for anomalies
kubectl get events -n october --sort-by='.lastTimestamp'
kubectl top pods -n october
kubectl logs -n october deploy/api --tail=100
```

**2. Containment**
```bash
# Isolate compromised pod
kubectl label pod <pod-name> quarantine=true -n october

# Apply deny-all NetworkPolicy to pod
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-<pod-name>
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  policyTypes:
    - Ingress
    - Egress
EOF
```

**3. Investigation**
```bash
# Capture pod state
kubectl describe pod <pod-name> -n october > incident-pod.txt
kubectl logs <pod-name> -n october --previous > incident-logs.txt

# Exec into pod (if safe)
kubectl exec -it <pod-name> -n october -- /bin/sh
```

**4. Remediation**
```bash
# Delete compromised pod
kubectl delete pod <pod-name> -n october

# Rollback to known-good version
helm rollback app -n october

# Force redeploy
kubectl rollout restart deployment/api -n october
```

**5. Post-Incident**
- Document timeline in `docs/incidents/INCIDENT-YYYY-MM-DD-<title>.md`
- Update threat model
- Implement additional mitigations
- Conduct blameless postmortem

---

## 🔗 Related Documentation

- [Architecture](ARCHITECTURE.md#security-architecture) - Security architecture overview
- [Deployment Guide](DEPLOYMENT_GUIDE.md#security-considerations) - Deployment security
- [Troubleshooting](TROUBLESHOOTING.md) - Security-related issues
- [NetworkPolicy Runbook](runbooks/networkpolicy-not-enforced.md) - Network isolation troubleshooting

---

## 📚 External Resources

**Kubernetes Security**:
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [NSA/CISA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

**NetworkPolicy**:
- [NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico NetworkPolicy Guide](https://docs.tigera.io/calico/latest/network-policy/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)

**Container Security**:
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP Container Security](https://owasp.org/www-project-docker-top-10/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)

---

**Last Updated**: 2025-10-22
**Security Review**: M4 (Observability & Security)
**Next Review**: M5 (Production Hardening)
