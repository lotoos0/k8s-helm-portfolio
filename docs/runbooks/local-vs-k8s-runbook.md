# RUNBOOK: Local vs K8s Development

## 📋 Overview

**Purpose**: Comparison guide for troubleshooting in different environments
**Audience**: Developers switching between local Docker and Kubernetes
**When to Use**: Environment-specific issues, deployment troubleshooting

---

## 🐳 Local Development (Docker/Compose)

### When to Use
- Fast development iteration
- Testing individual services
- Debugging without K8s complexity

### Quick Commands

```bash
# Start services
make compose-up

# View logs
make compose-logs
docker-compose logs -f api
docker-compose logs -f worker

# Restart service
docker-compose restart api

# Stop all
make compose-down
```

### Accessing Services

```bash
# API is exposed on port 8000
curl http://localhost:8000/healthz

# Redis on port 6379 (localhost)
redis-cli -h localhost -p 6379 ping
```

### Common Issues & Solutions

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| Port already in use | `docker-compose up` shows port conflict | Change port in `docker-compose.yml` or stop conflicting service |
| Cannot connect to Redis | Worker logs show connection errors | Check `docker-compose ps` - ensure Redis is running |
| Hot reload not working | Code changes don't reflect | Check volume mounts in `docker-compose.yml` |
| Container crashes | `docker-compose ps` shows Exit status | Check logs: `docker-compose logs <service>` |

### Debugging Commands

```bash
# Check container status
docker-compose ps

# Exec into container
docker-compose exec api sh
docker-compose exec worker sh

# View resource usage
docker stats

# Inspect container
docker inspect october-api

# Remove all and rebuild
docker-compose down -v
docker-compose build --no-cache
docker-compose up
```

---

## ☸️ Kubernetes Development (Minikube)

### When to Use
- Testing K8s-specific features (Ingress, HPA, probes)
- Multi-replica deployments
- Production-like environment
- Helm chart development

### Quick Commands

```bash
# Check cluster
kubectl cluster-info
kubectl get nodes

# View resources
kubectl -n october get all
kubectl -n october get pods -o wide

# View logs
kubectl -n october logs -l app=api --tail=100
kubectl -n october logs -l app=worker -f

# Restart deployment
kubectl -n october rollout restart deploy/api

# Delete and recreate
helm delete app -n october
make helm-up-dev
```

### Accessing Services

```bash
# Option 1: Port-forward
kubectl -n october port-forward svc/api 8080:80
curl http://localhost:8080/healthz

# Option 2: Ingress
MINIKUBE_IP=$(minikube ip)
curl http://api.$MINIKUBE_IP.nip.io/healthz

# Option 3: Direct to pod
kubectl -n october port-forward pod/<pod-name> 8080:8000
```

### Common Issues & Solutions

#### Ingress Not Working

**Quick Checklist**:

1. **Controller running?**
   ```bash
   kubectl -n ingress-nginx get pods
   # If not running: make k8s-enable-ingress
   ```

2. **Service endpoints exist?**
   ```bash
   kubectl -n october get svc api -o wide
   kubectl -n october get endpoints api
   # If empty: pods not ready (see pod issues below)
   ```

3. **Pod ready?**
   ```bash
   kubectl -n october get pods -l app=api
   kubectl -n october describe pod -l app=api
   # Check readiness/liveness probe events
   ```

4. **Ingress rule correct?**
   ```bash
   kubectl -n october describe ingress api-ingress
   # Host should match: api.$(minikube ip).nip.io
   MINIKUBE_IP=$(minikube ip)
   echo "Expected host: api.$MINIKUBE_IP.nip.io"
   ```

5. **Test via Node IP (bypass DNS)**
   ```bash
   MINIKUBE_IP=$(minikube ip)
   curl -H "Host: api.$MINIKUBE_IP.nip.io" http://$MINIKUBE_IP/healthz
   ```

6. **Check Ingress Controller logs**
   ```bash
   kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50
   ```

**Full runbook**: [ingress_not_working.md](ingress_not_working.md)

#### Pod Issues

**CrashLoopBackOff**:
```bash
# Check events
kubectl -n october describe pod <pod-name>

# Check logs
kubectl -n october logs <pod-name> --previous

# Common causes:
# - Application error (check logs)
# - Missing env vars (check configmap/secret)
# - Can't connect to Redis
```

**Full runbook**: [crashloopbackoff.md](crashloopbackoff.md)

**ImagePullBackOff**:
```bash
# Most common in local dev: image not loaded
make k8s-build-load          # API
make k8s-build-load-worker   # Worker

# Verify loaded
minikube image ls | grep october
```

**Full runbook**: [image_pull_backoff.md](image_pull_backoff.md)

**Pending (Not Scheduling)**:
```bash
# Check resources
kubectl describe nodes | grep -A 5 "Allocated"

# Reduce requests if needed (values-dev.yaml)
resources:
  requests:
    cpu: 50m
    memory: 64Mi
```

**Full runbook**: [pod_not_scheduling.md](pod_not_scheduling.md)

#### Common Pitfalls

| Pitfall | Symptom | Solution |
|---------|---------|----------|
| **Image not loaded** | `ImagePullBackOff` | Run `make k8s-build-load` after code changes |
| **Probes failing** | Pod restarts, not Ready | Check `/healthz` locally, tune probe thresholds |
| **Wrong ports** | Service unreachable | Ensure Service `port: 80` → `targetPort: 8000` matches container |
| **Minikube IP changed** | Ingress 404 | Update Ingress host with new `minikube ip` |

### Debugging Commands

```bash
# Pod inspection
kubectl -n october get pods -o wide
kubectl -n october describe pod <pod-name>
kubectl -n october logs <pod-name> --tail=100
kubectl -n october logs <pod-name> --previous

# Exec into pod
kubectl -n october exec -it <pod-name> -- sh

# Check events
kubectl -n october get events --sort-by='.lastTimestamp'

# Resource usage
kubectl top nodes
kubectl -n october top pods

# Service debugging
kubectl -n october get svc
kubectl -n october get endpoints
kubectl -n october describe svc api

# Helm debugging
helm list -n october
helm history app -n october
helm get values app -n october
helm get manifest app -n october
```

---

## 🔄 Environment Comparison

| Aspect | Local (Docker Compose) | Kubernetes (Minikube) |
|--------|----------------------|----------------------|
| **Scope** | Local, single-node | Cluster orchestration (multi-node capable) |
| **Setup Speed** | Seconds (`make compose-up`) | Minutes (`k8s-build-load` + deploy + probes) |
| **Iteration Speed** | Very fast | Moderate (build → load → deploy) |
| **Networking** | Simple `localhost:PORT` | Cluster IP + Service + Ingress |
| **Service Discovery** | Container names | DNS: `<svc>.<ns>.svc.cluster.local` |
| **Scaling** | Manual (`--scale`) | Declarative (`replicas:` in Deployment) |
| **Configuration** | Single YAML file | Multiple manifests (Deploy, Svc, Ing, CM) |
| **Logs** | `docker logs` | `kubectl logs` per pod |
| **Environment Vars** | `.env` file | ConfigMaps + Secrets |
| **Health Checks** | Manual curl tests | Automated probes (liveness/readiness) |
| **Rollback** | Recreate containers | Rolling updates & `helm rollback` |
| **Load Balancing** | N/A (single host) | Built-in via Service & Ingress |
| **Resource Usage** | Low | Higher (full K8s stack) |
| **Production Parity** | Low | High |
| **Use Case** | Rapid local development | Pre-production / cluster simulation |

---

## 🚀 Workflow Recommendations

### Development Workflow

```
1. Local Docker (docker-compose)
   ↓ Write code, test locally
2. Kubernetes (Minikube)
   ↓ Test K8s features, Helm chart
3. CI/CD Pipeline
   ↓ Automated tests, security scans
4. Production Deployment
```

### When to Switch Environments

**Use Local Docker when**:
- ✅ Developing new API endpoints
- ✅ Debugging application logic
- ✅ Quick iteration needed
- ✅ Testing without K8s complexity

**Use Kubernetes when**:
- ✅ Testing health probes
- ✅ Testing Ingress configuration
- ✅ Testing HPA (autoscaling)
- ✅ Validating Helm charts
- ✅ Multi-replica behavior
- ✅ Production-like testing

---

## 🔑 Quick Reference

### Local Docker
```bash
# Start
make compose-up

# Logs
docker-compose logs -f api

# Restart
docker-compose restart api

# Clean rebuild
docker-compose down -v && docker-compose build && docker-compose up
```

### Kubernetes
```bash
# Deploy
make helm-up-dev

# Logs
kubectl -n october logs -l app=api -f

# Restart
kubectl -n october rollout restart deploy/api

# Clean redeploy
helm delete app -n october && make helm-up-dev
```

### Quick Troubleshooting

**Local not working?**
```bash
docker-compose ps               # Check status
docker-compose logs api         # Check logs
docker-compose restart api      # Restart
```

**K8s not working?**
```bash
kubectl -n october get pods     # Check pod status
kubectl -n october describe pod <pod-name>  # Events
kubectl -n october logs <pod-name>          # Logs
```

**Ingress not working?**
```bash
# Bypass Ingress with port-forward
make k8s-port-api
curl http://localhost:8080/healthz
```

---

## 📚 Related Runbooks

**Pod Issues**:
- [CrashLoopBackOff](crashloopbackoff.md)
- [ImagePullBackOff](image_pull_backoff.md)
- [Pod Not Scheduling](pod_not_scheduling.md)

**Network Issues**:
- [Ingress Not Working](ingress_not_working.md)
- [Service Unreachable](service_unreachable.md)
- [kubectl No Route to Host](kubectl_no_route_to_host.md)

**Deployment**:
- [Helm Upgrade Failed](helm_upgrade_failed.md)

**Documentation**:
- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [Deployment Guide](../DEPLOYMENT_GUIDE.md)

---

**Last Updated**: 2025-10-19
**Version**: 2.0 (Improved format)
**Environments**: Docker Compose 2.x, Minikube 1.32, Kubernetes 1.28
