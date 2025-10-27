# Troubleshooting Guide

## Table of Contents
- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Runbooks (Detailed Procedures)](#runbooks-detailed-procedures)
- [Common Error Messages](#common-error-messages)
- [Debugging Commands](#debugging-commands)

---

## Quick Diagnostics

**Run comprehensive system check**:
```bash
./scripts/quick-diag.sh > diagnostics.txt
```

**Check cluster status**:
```bash
kubectl cluster-info
kubectl get nodes
kubectl -n october get all
kubectl -n october get events --sort-by='.lastTimestamp' | tail -20
```

**Check specific components**:
```bash
# Pods
kubectl -n october get pods -o wide
kubectl -n october describe pod <pod-name>
kubectl -n october logs <pod-name> --tail=100

# Services
kubectl -n october get svc
kubectl -n october get endpoints

# Helm
helm list -n october
helm history app -n october
```

---

## Common Issues

### 🔴 Pod Issues

| Issue | Symptom | Quick Fix | Detailed Runbook |
|-------|---------|-----------|------------------|
| **CrashLoopBackOff** | Pod restarts continuously | Check logs: `kubectl logs <pod> --previous` | **[→ crashloopbackoff.md](runbooks/crashloopbackoff.md)** |
| **ImagePullBackOff** | Cannot pull container image | Load image: `make k8s-build-load` | **[→ image_pull_backoff.md](runbooks/image_pull_backoff.md)** |
| **Pending** | Pod not scheduling | Check resources: `kubectl describe nodes` | **[→ pod_not_scheduling.md](runbooks/pod_not_scheduling.md)** |
| **OOMKilled** | Out of memory | Increase memory limits in `values.yaml` | **[→ crashloopbackoff.md#cause-e](runbooks/crashloopbackoff.md#cause-e-oomkilled-out-of-memory)** |

### 🌐 Network Issues

| Issue | Symptom | Quick Fix | Detailed Runbook |
|-------|---------|-----------|------------------|
| **Ingress Not Working** | 404/503 via Ingress URL | Enable controller: `make k8s-enable-ingress` | **[→ ingress_not_working.md](runbooks/ingress_not_working.md)** |
| **Service Unreachable** | Cannot connect to service | Check endpoints: `kubectl get endpoints` | **[→ service_unreachable.md](runbooks/service_unreachable.md)** |
| **No Route to Host** | kubectl connection fails | Restart Minikube | **[→ kubectl_no_route_to_host.md](runbooks/kubectl_no_route_to_host.md)** |

### ⎈ Helm Issues

| Issue | Symptom | Quick Fix | Detailed Runbook |
|-------|---------|-----------|------------------|
| **Upgrade Failed** | Helm upgrade times out | Rollback: `make helm-rollback-last` | **[→ helm_upgrade_failed.md](runbooks/helm_upgrade_failed.md)** |
| **Lint Errors** | `helm lint` fails | Check YAML syntax in `templates/` | [Deployment Guide](DEPLOYMENT_GUIDE.md#helm-debugging) |
| **Pending Upgrade** | Stuck in pending-upgrade state | Force rollback: `helm rollback app -n october` | **[→ helm_upgrade_failed.md#cause-b](runbooks/helm_upgrade_failed.md#cause-b-pending-upgrade-stuck)** |

### 🚀 CI/CD Issues

| Issue | Symptom | Quick Fix | Detailed Runbook |
|-------|---------|-----------|------------------|
| **Trivy Scan Failed** | HIGH/CRITICAL vulnerabilities | Update base image & dependencies | [Deployment Guide](DEPLOYMENT_GUIDE.md#issue-trivy-security-scan-failing) |
| **Workflow Failed** | GitHub Actions red X | Check workflow logs on GitHub | [Deployment Guide](DEPLOYMENT_GUIDE.md#issue-github-actions-workflow-failing) |
| **Smoke Test Failed** | Post-deploy health check fails | Check diagnostics artifacts | [Deployment Guide](DEPLOYMENT_GUIDE.md#issue-helm-deployment-failing-in-cd) |

---

## Runbooks (Detailed Procedures)

**Step-by-step incident response procedures:**

### Pod & Container Issues
- **[CrashLoopBackOff](runbooks/crashloopbackoff.md)** - Pod continuously restarting
- **[ImagePullBackOff](runbooks/image_pull_backoff.md)** - Cannot pull container image
- **[Pod Not Scheduling](runbooks/pod_not_scheduling.md)** - Pod stuck in Pending state

### Network & Connectivity
- **[Ingress Not Working](runbooks/ingress_not_working.md)** - Cannot access service via Ingress
- **[Service Unreachable](runbooks/service_unreachable.md)** - Cannot connect to Kubernetes Service
- **[kubectl No Route to Host](runbooks/kubectl_no_route_to_host.md)** - kubectl connectivity issues
- **[NetworkPolicy Not Enforced](runbooks/networkpolicy-not-enforced.md)** - NetworkPolicy rules not being applied

### Helm & Deployment
- **[Helm Upgrade Failed](runbooks/helm_upgrade_failed.md)** - Helm deployment issues

### Environment Comparison
- **[Local vs K8s Development](runbooks/local-vs-k8s-runbook.md)** - Environment-specific troubleshooting

---

## Common Error Messages

### Pod Status Messages

| Error | Meaning | Action |
|-------|---------|--------|
| `CrashLoopBackOff` | Container crashes after starting | **[→ Runbook](runbooks/crashloopbackoff.md)** |
| `ImagePullBackOff` | Cannot pull image | **[→ Runbook](runbooks/image_pull_backoff.md)** |
| `ErrImagePull` | Image pull failed | **[→ Runbook](runbooks/image_pull_backoff.md)** |
| `Pending` | Cannot schedule pod | **[→ Runbook](runbooks/pod_not_scheduling.md)** |
| `OOMKilled` | Out of memory | Increase memory limits |
| `Error` | Generic error | Check logs: `kubectl logs <pod>` |
| `Evicted` | Pod evicted due to resource pressure | Check node resources |
| `Unknown` | Kubelet lost contact | Check node status |

### Network Errors

| Error | Meaning | Action |
|-------|---------|--------|
| `Connection refused` | Service not listening on port | **[→ Runbook](runbooks/service_unreachable.md)** |
| `No route to host` | Network unreachable | **[→ Runbook](runbooks/kubectl_no_route_to_host.md)** |
| `Timeout` | Connection timed out | Check firewalls, **[→ NetworkPolicy](runbooks/networkpolicy-not-enforced.md)** |
| `404 Not Found` | Ingress route not configured | **[→ Runbook](runbooks/ingress_not_working.md)** |
| `503 Service Unavailable` | No healthy backends | **[→ Runbook](runbooks/service_unreachable.md)** |

### Helm Errors

| Error | Meaning | Action |
|-------|---------|--------|
| `UPGRADE FAILED: timed out` | Deployment timed out | **[→ Runbook](runbooks/helm_upgrade_failed.md)** |
| `cannot patch` | Resource conflict | **[→ Runbook](runbooks/helm_upgrade_failed.md#cause-c)** |
| `release: not found` | Release doesn't exist | Install: `make helm-up-dev` |
| `validation failed` | Invalid YAML | Fix templates: `make helm-lint` |

---

## Debugging Commands

### Pod Debugging

```bash
# Get pod status
kubectl -n october get pods
kubectl -n october get pods -o wide

# Describe pod (events)
kubectl -n october describe pod <pod-name>

# View logs
kubectl -n october logs <pod-name>
kubectl -n october logs <pod-name> --previous  # Previous container
kubectl -n october logs <pod-name> -f          # Follow logs
kubectl -n october logs -l app=api --tail=100  # All pods with label

# Execute commands in pod
kubectl -n october exec <pod-name> -- env
kubectl -n october exec -it <pod-name> -- sh

# Port forward
kubectl -n october port-forward <pod-name> 8080:8000
kubectl -n october port-forward svc/api 8080:80
```

### Service & Network Debugging

```bash
# Check services
kubectl -n october get svc
kubectl -n october get endpoints
kubectl -n october describe svc api

# Check Ingress
kubectl -n october get ingress
kubectl -n october describe ingress api-ingress

# Test connectivity
kubectl -n october run test --rm -it --image=curlimages/curl -- sh
# Inside pod:
curl http://api.october.svc.cluster.local/healthz
```

### Helm Debugging

```bash
# List releases
helm list -n october

# View history
helm history app -n october

# Get manifest
helm get manifest app -n october

# Get values
helm get values app -n october

# Lint chart
helm lint deploy/helm/api --strict

# Template (dry-run)
helm template app deploy/helm/api -f deploy/helm/api/values-dev.yaml

# Debug install
helm upgrade --install app deploy/helm/api --debug --dry-run
```

### Resource Usage

```bash
# Node resources
kubectl top nodes
kubectl describe nodes

# Pod resources
kubectl -n october top pods

# Check HPA
kubectl -n october get hpa
kubectl -n october describe hpa api
```

### Events & Logs

```bash
# Recent events
kubectl -n october get events --sort-by='.lastTimestamp'
kubectl -n october get events --sort-by='.lastTimestamp' | tail -20

# Watch events
kubectl -n october get events -w

# Ingress Controller logs
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=100
```

---

## Escalation

If you cannot resolve the issue:

### 1. Collect Diagnostics

```bash
# Run diagnostics script
./scripts/quick-diag.sh > diagnostics.txt

# Save pod info
kubectl -n october describe pod <pod-name> > pod-describe.txt
kubectl -n october logs <pod-name> > pod-logs.txt

# Save events
kubectl -n october get events --sort-by='.lastTimestamp' > events.txt
```

### 2. Check Documentation

- **Runbooks**: [runbooks/](runbooks/) - Step-by-step procedures
- **Deployment Guide**: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **API Reference**: [API_REFERENCE.md](API_REFERENCE.md)

### 3. Create GitHub Issue

Include:
- Problem description
- Error messages
- Steps to reproduce
- Diagnostics output
- What you've tried

---

## Prevention

### Pre-Deployment Checks

```bash
# Validate before deploying
make lint                    # Code quality
make test                    # Unit tests
make helm-lint              # Helm validation
make helm-template-dev      # Template rendering
make helm-diff-dev          # Preview changes
```

### Monitoring (M4)

- Set up Prometheus + Grafana
- Configure alerts for:
  - CrashLoopBackOff > 5 minutes
  - CPU > 80% for 5 minutes
  - Error rate > 5%

### Regular Maintenance

```bash
# Check cluster health
kubectl get nodes
kubectl get componentstatuses

# Check resource usage
kubectl top nodes
kubectl -n october top pods

# Review events
kubectl -n october get events --sort-by='.lastTimestamp' | tail -50
```

---

## Next Steps

After resolving the issue:

1. **Document** what happened in diagnostics/
2. **Update runbook** if new pattern discovered
3. **Prevent recurrence** - add monitoring, improve CI/CD
4. **Share learnings** - update documentation

---

**For detailed step-by-step procedures, see**: **[runbooks/](runbooks/)**

**For deployment issues, see**: **[Deployment Guide](DEPLOYMENT_GUIDE.md)**

**For architecture questions, see**: **[Architecture Documentation](ARCHITECTURE.md)**

---

**Document Version**: 2.0 (Refactored)
**Last Updated**: 2025-10-27
**Lines**: ~300 (reduced from 1,015)
