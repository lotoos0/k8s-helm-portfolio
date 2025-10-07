# Local Dev vs K8s Runbook

## Local (Docker/Compose)

- Dev loop: fast `make run-api` or `compose-up`.
- Troubleshooting:
  - `docker logs`, `compose-logs`.
  - Ports: 8000 mapped → `curl localhost:8000/healthz`.

## Kubernetes (Minikube)

### Quick checklist (Ingress not working?)

1. **Controller running?**
   - `kubectl -n ingress-nginx get pods`
2. **Service endpoints exist?**
   - `kubectl -n october get svc api -o wide`
   - `kubectl -n october get endpointslices | grep api`
3. **Pod ready?**
   - `kubectl -n october get po -l app=api`
   - `kubectl -n october describe po -l app=api`
   - Check readiness/liveness events.
4. **Ingress rule applied & correct host?**
   - `kubectl -n october describe ingress api`
   - Host should be `api.<minikube-ip>.nip.io`
   - Get IP: `minikube ip`
5. **Test via Node IP**
   - `curl -H "Host: api.<ip>.nip.io" http://<minikube-ip>/healthz`
6. **Logs**
   - `kubectl -n ingress-nginx logs deploy/ingress-nginx-controller`

### Common pitfalls

- Image not present inside Minikube:
  - Run `make k8s-build-load` after each code change affecting the image.
- Probes failing:
  - Check `/healthz` and `/ready` locally.
  - Tune `startupProbe`/`readinessProbe` thresholds.
- Wrong service port/targetPort naming:
  - Ensure Service `port: 80` → `targetPort: http` and container `ports.name: http`.

| Aspect                     | Docker Compose (Local)                | Kubernetes (Minikube)                                        |
| :------------------------- | :------------------------------------ | :----------------------------------------------------------- |
| **Scope**                  | Local, single-node environment        | Cluster orchestration (multi-node capable)                   |
| **Setup speed**            | Seconds (`make compose-up`)           | Minutes (`k8s-build-load`, `apply`, probes, Ingress)         |
| **Networking**             | Simple `localhost:PORT` mapping       | Cluster IP + Service + Ingress routing                       |
| **Scaling**                | Manual (`docker-compose up --scale`)  | Declarative via `replicas:` in Deployment                    |
| **Configuration**          | YAML, one file (`docker-compose.yml`) | Multiple manifests (Deployment, Service, Ingress, ConfigMap) |
| **Service discovery**      | Container names                       | DNS inside cluster (`<svc>.<ns>.svc.cluster.local`)          |
| **Logs**                   | `docker logs`, `compose logs`         | `kubectl logs`, centralized per pod                          |
| **Environment management** | `.env` file                           | ConfigMaps + Secrets                                         |
| **Probes / health checks** | Basic manual curl tests               | Automated `livenessProbe` / `readinessProbe`                 |
| **Rollback / restart**     | Recreate containers                   | Rolling updates & rollbacks                                  |
| **Load balancing**         | N/A (single host)                     | Built-in via `Service` & `Ingress`                           |
| **Use case**               | Rapid local development               | Pre-production / cluster simulation                          |
