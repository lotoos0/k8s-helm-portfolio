# October DevOps – K8s + Helm + CI/CD + Observability

A small two-service demo (FastAPI **API** + Celery **worker** with Redis) built:

- Docker & Compose

- Kubernetes (manifests → Helm)

- CI/CD (build, test, scan, deploy, E2E smoke)

- Observability (Prometheus + Grafana, alerts)

## Architecture (current state)

```

[Client] --> [API (FastAPI)]

| /healthz /ready /metrics

|

(K8s: Deployment + Service)

|

[Minikube cluster]

```

> Coming up: Redis + worker, Ingress + HPA, Helm, CI/CD, Prometheus/Grafana.

## Quickstart

### Local (Docker)

```bash

make build-api

make run-api-docker

curl -s localhost:8000/healthz

make stop-api

```

### Stack (Compose)

```bash

make compose-up # api + redis + worker

make compose-logs

make worker-ping # enqueue ping()

make worker-add # enqueue add(1,2)

make compose-down

```

### Kubernetes (Minikube)

```bash

minikube start

make k8s-build-load # build & load october-api:dev into minikube

make k8s-apply

make k8s-get

make k8s-port-api # forwards :8080 -> svc/api

curl -s localhost:8080/healthz

```

## Health & Probes

- **/healthz** → liveness (process alive)

- **/ready** → readiness (accepts traffic)

- **/metrics** → Prometheus exposition format

K8s probes:

- `startupProbe`: /healthz (gives the app warmup time)

- `readinessProbe`: /ready

- `livenessProbe`: /healthz

## Make targets

Run `make help` for a list. Highlights:

- **Dev:** `install`, `lint`, `fmt`, `test`

- **Docker:** `build-api`, `run-api-docker`, `stop-api`

- **Compose:** `compose-up|logs|down`, `worker-ping`, `worker-add`

- **K8s:** `k8s-build-load`, `k8s-apply`, `k8s-get`, `k8s-port-api`, `k8s-logs-api`,

`k8s-describe-api`, `k8s-restart-api`, `k8s-set-image-api`

## Roadmap (Milestones)

- **M1 (by Oct 14):** Docker + base K8s manifests + probes ✅ in progress

- **M2 (by Oct 23):** Helm chart (dev/prod), rollout/rollback

- **M3 (by Oct 28):** CI/CD: build → test → scan → push → `helm upgrade --install` + E2E smoke

- **M4 (by Oct 31):** Prometheus + Grafana, 2 alerts, final README (incl. costs)

## Security Notes (WIP)

- Non-root containers, dropped capabilities, healthchecks

- Secrets kept out of git; example manifests provided

## License

MIT

```

```
