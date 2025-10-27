.PHONY: help venv install run-api run-worker clean

PY ?= python3
VENV ?= .venv
PIP := $(VENV)/bin/pip/
PYTHON := $(VENV)/bin/python
SHELL := /bin/bash
NS ?= $(HELM_NS)

help: ## Show help for targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' | sort

venv: ## Create virtualenv
	@test -d $(VENV) || $(PY) -m venv $(VENV)

install: venv ## Install all dependencies (API + worker + scripts)
	$(PIP) install --upgrade pip
	$(PIP) install -r api/requirements.txt
	$(PIP) install -r worker/requirements.txt
	$(PIP) install -r scripts/requirements.txt

run-api: ## Run FastAPI locally on :800 (reload)
	$(VENV)/bin/uvicorn api.app.main:app --host 0.0.0.0 --port 8000 --reload

run-worker: ## Run Celery workder ( requires Redis running )
	cd worker && ../$(VENV)/bin/celery -A app.celery_app.app worker -l info

clean: ## Remove cache
	find . -name "__pycache__" -type d -exec rm -rf {} + 
	rm -rf .pytest_cache

# ----------- Docker (API) ----------
  
IMAGE_API ?= october-api:dev
CONTAINER_API ?= october-api

build-api: ## Build API Docker image
	docker build -t $(IMAGE_API) ./api

run-api-docker: ## Run API container on :8000
	- docker rm -f $(CONTAINER_API) >/dev/null 2>&1 || true
	docker run -d --name $(CONTAINER_API) -p 8000:8000 $(IMAGE_API)

logs-api: ## Tail logs from API container
	docker logs -f $(CONTAINER_API)

stop-api: ## Stop and remove API container
	- docker rm -f $(CONTAINER_API) >/dev/null 2>&1 || true

# --------- Docker Compose ----------
compose-up: ## Build & run all services (api, redis, worker)
	docker compose up -d --build

compose-logs: ## Tail logs of all services
	docker compose logs -f

compose-down: ## Stop and remove all services
	docker compose down -v 

# ---------- Smoke helpers (Celery calls via docker exec) ---------
worker-ping: ## Call ping task on worker (result in logs)
	docker exec october-worker python -c "from worker.app.tasks import ping; print(ping.delay().id)"

worker-add: ## Call add(1,2) task on worker (result id printed)
	docker exec october-worker python -c "from worker.app.tasks import add; print(add.delay(1,2).id)"

# Y Can retrieve result if backend is enabled and reachable
worker-result: ## Get result by id: make worker-result ID=<task_id>
	@if [ -z "$(ID)" ]; then echo "Usage: make worker-result ID=<task_id>"; exit 1; fi
	docker exec october-worker python -c "from celery.result import AsyncResult; from worker.app.celery_app import app; r=AsyncResult('$(ID)', app=app); print(r.status, r.result)"

# ----------- Dev quality ------------
lint: ## Run Ruff (lint + imports)
	$(VENV)/bin/ruff check api

fmt: ## Format with Black + Ruff imports
	$(VENV)/bin/black api
	$(VENV)/bin/ruff check --select I --fix api

test: ## Run pytest with coverage 
	$(VENV)/bin/pytest --cov=api --cov-report=term-missing

ci: ## Lint + Test (for local CI-like run)
	make lint && make fmt && make test


# ------------ Kubernates (MInikube) -------------
KNS ?= october

k8s-build-load: ## Build images and load to Minikube
	make build-api
	minikube image load october-api:dev

minikube-cleanup-images: ## Remove old dev-* images from Minikube (keeps last 3)
	@minikube ssh "docker images --format '{{.Repository}}:{{.Tag}}' | grep 'october-api:dev-' | sort -r | tail -n +4" | \
	  xargs -I {} sh -c 'minikube ssh "docker rmi -f {}" || true'

dev-deploy: ## Quick dev: build + load + helm upgrade (uses timestamp tag)
	@TAG=dev-$$(date +%s); \
	echo "Deploying with tag: $$TAG"; \
	docker build -t october-api:$$TAG ./api; \
	minikube image load october-api:$$TAG; \
	IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	helm upgrade --install $(HELM_NAME) $(HELM_DIR) \
	  -n $(HELM_NS) --create-namespace \
	  -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	  --set api.ingress.host=$$HOST \
	  --set api.image.tag=$$TAG \
	  --atomic --timeout 5m --history-max 10

dev-deploy-quick: ## Quick deploy: build + kubectl set image (faster, no helm)
	@TAG=dev-$$(date +%s); \
	echo "Deploying with tag: $$TAG"; \
	docker build -t october-api:$$TAG ./api; \
	minikube image load october-api:$$TAG; \
	kubectl -n $(HELM_NS) set image deploy/api api=october-api:$$TAG; \
	kubectl -n $(HELM_NS) rollout status deploy/api --timeout=60s

k8s-apply: ## Apply namespace + config + api (deployment, service)
	kubectl apply -f deploy/k8s/ns.yaml
	kubectl apply -f deploy/k8s/configmap.yaml
	kubectl apply -f deploy/k8s/deployment-api.yaml
	kubectl apply -f deploy/k8s/service-api.yaml

k8s-delete: ## Delete all app resources
	- kubectl delete -f deploy/k8s/service-api.yaml --ignore-not-found
	- kubectl delete -f deploy/k8s/deployment-api.yaml --ignore-not-found
	- kubectl delete -f deploy/k8s/configmap.yaml --ignore-not-found
	- kubectl delete -f deploy/k8s/ns.yaml --ignore-not-found

k8s-port-api: ## Port-forward API :8080 -> svc/api:80
	kubectl -n $(KNS) port-forward svc/api 8080:80

k8s-logs-api: ## Tail API pod logs
	kubectl -n $(KNS) logs -l app=api -f --max-log-requests=3

k8s-describe-api: ## Describe API deployment and pod
	kubectl -n $(KNS) describe deploy/api
	kubectl -n $(KNS) get po -l app=api
	kubectl -n $(KNS) describe po -l app=api | sed -n '1,120p'

k8s-restart-api: ## Rollout restart API
	kubectl -n $(KNS) rollout restart deploy/api
	kubectl -n $(KNS) rollout status deploy/api

k8s-set-image-api: ## Update image (usage: make k8s-set-image-api IMG=myrepo/october-api:tag)
	@if [ -z "$(IMG)" ]; then echo "Usage: make k8s-set-image-api IMG=<image>"; exit 1; fi 
	kubectl -n $(KNS) set image deploy/api api=$(IMG)
	kubectl -n $(KNS) rollout status deploy/api

k8s-get: ## Quick view
	kubectl -n $(KNS) get deploy,po,svc

# ------------- Ingress (MInikube) -----------

k8s-enable-ingress: ## Enable NGINX ingress addon in Minikube
	minikube addons enable ingress
	kubectl -n ingress-nginx get pods

k8s-apply-ingress: ## Apply API ingress with dynamic host api.<minikube-ip>.nip.io
	@IP=$$(minikube ip); \
	  HOST=api.$$IP.nip.io; \
	  echo "Using host: $$HOST"; \
	  cat deploy/k8s/ingress-api.yaml | sed "s/api\.[0-9.]*\.nip\.io/$$HOST/g" | kubectl apply -f -

k8s-delete-ingress: ## Delete API ingress (host-insensitive)
	- kubectl -n $(KNS) delete ingress/api --ignore-not-found

k8s-curl-ingress: ## Curl ingress /healthz
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  echo "GET http://$$HOST/healthz"; \
	  curl -sS --max-time 5 http://$$HOST/healthz | jq .

k8s-open-ingress: ## Open in browser (Linux xdg-open/mac open)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; URL=http://$$HOST/healthz; \
	  echo $$URL; \
	  ( command -v xdg-open >/dev/null && xdg-open $$URL ) || ( command -v open >/dev/null && open $$URL ) || true

# ----- Metrics server / HPA ----------
k8s-enable-metrics: ## Enable metrics-server in Minikube
	minikube addons enable metrics-server
	kubectl -n kube-system get pods | grep metrics-server || true

k8s-apply-hpa: ## Apply HPA for API
	kubectl apply -f deploy/k8s/hpa-api.yaml 

k8s-hpa-status: ## Watch HPA & ReplicaSet status
	@echo "HPA:"
	@kubectl -n $(KNS) get hpa api -o wide || true
	@echo "\nDeploy:"
	@kubectl -n $(KNS) get deploy api || true
	@echo "\nPods:"
	@kubectl -n $(KNS) get po -l app=api -w 

k8s-top: ## Show CPU/mem usage for pods and nodes
	@echo "Pods usage:"; kubectl -n $(KNS) top pods || true
	@echo "Nodes usage:"; kubectl top nodes || true


# ---------- Load tester -----------
load-test: ## Run HTTP load test (use URL=... CONC=... DUR=...)
	$(PYTHON) scripts/load_tester.py --url=$(URL) --concurrency=$(CONC) --duration=$(DUR)

# Defaults for convenience 
URL ?= http://localhost:8080/healthz
CONC ?= 100
DUR ?= 90

# --------- K8s: Redis & Worker -----------
k8s-apply-redis: ## Apply Redis (PVC + Deployment + Service)
	kubectl apply -f deploy/k8s/redis/pvc.yaml
	kubectl apply -f deploy/k8s/redis/deployment.yaml
	kubectl apply -f deploy/k8s/redis/service.yaml
	kubectl -n $(KNS) rollout status deploy/redis

k8s-build-load-worker: # Build and load worker image into Minikube
	docker build -t october-worker:dev ./worker
	minikube image load october-worker:dev

k8s-apply-worker: ## Apply Celery worker deployment
	kubectl apply -f deploy/k8s/worker/deployment.yaml
	kubectl -n $(KNS) rollout status deploy/worker 

k8s-logs-worker: ## Tail worker logs 
	kubectl -n $(KNS) logs -l app=worker -f --max-log-requests=3 

# Exec helpers: run python in worker pod
k8s-exec-worker-ping: ## Call ping() via python inside worker pod
	@POD=$$(kubectl -n $(KNS) get po -l app=worker -o jsonpath='{.items[0].metadata.name}'); \
	kubectl -n $(KNS) exec $$POD -- python -c "from worker.app.tasks import ping; print(ping.delay().id)"

k8s-exec-worker-add: ## Call add(1,2) via python inside worker pod
	@POD=$$(kubectl -n $(KNS) get po -l app=worker -o jsonpath='{.items[0].metadata.name}'); \
	kubectl -n $(KNS) exec $$POD -- python -c "from worker.app.tasks import add; print(add.delay(1,2).id)"

# ---------- Helm -------------
HELM_NAME ?= app
HELM_DIR  ?= deploy/helm/api
HELM_NS   ?= october

helm-lint: ## Helm lint (strict) 
	helm lint $(HELM_DIR) --strict

helm-template-dev: ## Render templates (dev, validate)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  helm template $(HELM_NAME) $(HELM_DIR) \
	    --namespace $(HELM_NS) \
	    -f $(HELM_DIR)/values.yaml \
	    -f $(HELM_DIR)/values-dev.yaml \
	    --set api.ingress.host=$$HOST \
	    --debug --validate | sed -n '1,200p'

helm-up-dev: ## Upgrade/Install dev (Minikube)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  helm upgrade --install $(HELM_NAME) $(HELM_DIR) \
	    --namespace $(HELM_NS) --create-namespace \
	    -f $(HELM_DIR)/values.yaml \
	    -f $(HELM_DIR)/values-dev.yaml \
	    --set api.ingress.host=$$HOST

helm-del: ## Uninstall release
	helm uninstall $(HELM_NAME) -n $(HELM_NS) || true

helm-history: ## Show release history 
	helm history $(HELM_NAME) -n $(HELM_NS) || true

helm-diff-dev: ## Show diff vs current (dev)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  helm diff upgrade --allow-unreleased $(HELM_NAME) $(HELM_DIR) \
	    -n $(HELM_NS) \
	    -f $(HELM_DIR)/values.yaml \
	    -f $(HELM_DIR)/values-dev.yaml \
	    --set api.ingress.host=$$HOST || true

helm-rollback: ## Rollback to a given REV (use: make helm-rollback REV=2)
	@if [ -z "$(REV)" ]; then echo "Usage: make helm-rollback REV=<revision>"; exit 1; fi
	helm rollback $(HELM_NAME) $(REV) -n $(HELM_NS)
	helm history $(HELM_NAME) -n $(HELM_NS)


ci-python: ## Local: lint + format-check + tests
	$(VENV)/bin/ruff check api
	$(VENV)/bin/black --check api
	$(VENV)/bin/pytest -q --cov=api --cov-report=term-missing

ci-docker: ## Local: build API & worker (no push)
	docker build -t october-api:ci ./api
	docker build -t october-worker:ci ./worker 

ci-all: ## Local: run all CI steps
	make ci-python && make ci-docker

# ----- Registry push (local helper) -----
REGISTRY ?= ghcr.io
ORG ?= lotoos0
API_IMAGE ?= $(REGISTRY)/$(ORG)/october-api
WORKER_IMAGE ?= $(REGISTRY)/$(ORG)/october-worker
SHA ?= $(shell git rev-parse --short HEAD)
API_TAG ?= dev
WORKER_TAG ?= dev

push-api: ## Build & push API (tags: dev, sha-<short>)
	docker build -t $(API_IMAGE):dev -t $(API_IMAGE):sha-$(SHA) ./api
	docker push $(API_IMAGE):dev
	docker push $(API_IMAGE):sha-$(SHA)

push-worker: ## Build & push Worker (tags: dev, sha-<short>)
	docker build -t $(WORKER_IMAGE):dev -t $(WORKER_IMAGE):sha-$(SHA) ./worker
	docker push $(WORKER_IMAGE):dev
	docker push $(WORKER_IMAGE):sha-$(SHA)

push-all: ## Push both images
	make push-api && make push-worker

# -------- CD local helper (uses provided kubeconfig file) ---------
KUBECONFIG_PATH ?= $(HOME)/.kube/config
DEV_NS ?= october
DEV_HOST ?= api.localdev.invalid  # nadpisz przy wywołaniu

cd-dev: ## Helm upgrade/install to dev using local kubeconfig (override DEV_HOST, images)
	helm upgrade --install $(HELM_NAME) $(HELM_DIR) \
	  -n $(DEV_NS) --create-namespace \
	  -f $(HELM_DIR)/values.yaml \
	  -f $(HELM_DIR)/values-dev.yaml \
	  --set api.ingress.host=$(DEV_HOST) \
	  --set api.image.repository=$(REGISTRY)/$(ORG)/october-api \
	  --set api.image.tag=dev \
	  --set worker.image.repository=$(REGISTRY)/$(ORG)/october-worker \
	  --set worker.image.tag=dev

helm-up-dev-atomic: ## Helm upgrade/install (atomic, timeout)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  helm upgrade --install $(HELM_NAME) $(HELM_DIR) \
	    -n $(HELM_NS) --create-namespace \
	    -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	    --set api.ingress.host=$$HOST \
	    --atomic --timeout 5m --history-max 10 

helm-rollback-last: ## Rollback to previous revision
	@REV=$$(helm history $(HELM_NAME) -n $(HELM_NS) | awk 'NR==2{print $$1}'); \
	  echo "Rolling back to $$REV"; \
	  helm rollback $(HELM_NAME) $$REV -n $(HELM_NS); \
	  helm history $(HELM_NAME) -n $(HELM_NS)

cd-dev-atomic: ## Local CD (atomic) with images from GHCR (override ORG/REGISTRY/TAGS)
	@IP=$$(minikube ip); HOST=api.$$IP.nip.io; \
	  helm upgrade --install $(HELM_NAME) $(HELM_DIR) \
	    -n $(HELM_NS) --create-namespace \
	    -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	    --set api.ingress.host=$$HOST \
	    --set api.image.repository=$(REGISTRY)/$(ORG)/october-api \
	    --set api.image.tag=$(API_TAG) \
	    --set worker.image.repository=$(REGISTRY)/$(ORG)/october-worker \
	    --set worker.image.tag=$(WORKER_TAG) \
	    --atomic --timeout 5m --history-max 10

smoke-ci: ## Run E2E smoke (Ingerss) using scripts/smoke.sh; override HOST=...
	@if [ -z "$(HOST)" ]; then echo "Usage: make smoke-ci HOST=api.<minikube-ip>.nip.io"; exit 2; fi
	./scripts/smoke.sh "$(HOST)"

smoke-pf: ## Run E2E via port-forward (local fallback)
	@echo "Port-forwarding svc/api -> :8080 (namespace $(NS))"
	(kubectl -n $(NS) port-forward svc/api 8080:80 >/dev/null 2>&1 & echo $$! > .pf.pid)
	sleep 2
	./scripts/smoke.sh "localhost:8080"; RC=$$?
	@if [ -f .pf.pid ]; then kill $$(cat .pf.pid) || true; rm .pf.pid; fi
	@exit $$RC

# --------- Monitoring stack ( kube-prometheus-stack ) ----------
MON_NS ?= monitoring
MON_REL ?= mon

mon-install: ## Install/upgrade kube-prometheus-stack
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install $(MON_REL) prometheus-community/kube-prometheus-stack \
		-n $(MON_NS) --create-namespace

mon-status: ## Show monitoring components 
	kubectl -n $(MON_NS) get pods,svc

mon-pf-grafana: ## Port-forward Grafana :3000
	@SVC=$$(kubectl -n $(MON_NS) get svc -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}'); \
	echo "Port-forwarding $$SVC -> :3000"; \
	kubectl -n $(MON_NS) port-forward svc/$$SVC 3000:80

mon-pf-prom: ## Port-forward Prometheus :9090
	@SVC=$$(kubectl -n $(MON_NS) get svc -l app=kube-prometheus-stack-prometheus -o jsonpath='{.items[0].metadata.name}'); \
	echo "Port-forwading $$SVC -> :9090"; \
	kubectl -n $(MON_NS) port-forward svc/$$SVC 9090:9090

mon-grafana-pass: ## Print Grafana admin password
	@kubectl -n $(MON_NS) get secret $(MON_REL)-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo

mon-pf-am: ## Port-forward Alertmanager :9093
	@SVC=$$(kubectl -n $(MON_NS) get svc -l app=kube-prometheus-stack-alertmanager -o jsonpath='{.items[0].metadata.name}'); \
	echo "Port-forwarding $$SVC -> :9093"; \
	kubectl -n $(MON_NS) port-forward svc/$$SVC 9093:9093

mon-alerts-apply: ## Apply alertmanager values (Slack)
	helm upgrade --install $(MON_REL) prometheus-community/kube-prometheus-stack \
		-n $(MON_NS) -f deploy/monitoring/values-alerting.yaml -f deploy/monitoring/values-extra.yaml

mon-alerts-status: ## Check AM routes/receivers
	kubectl -n $(MON_NS) get pods,svc | grep alertmanager || true

# ---- Day21 helpers ----
mon-fire-crash: ## Trigger Crash LoopBackOff on API (sets env.FAIL_HEALTHZ=true)
	@IP=$$(minikube ip); \
	helm upgrade --install $(HELM_NAME) $(HELM_DIR) -n $(HELM_NS) \
	  -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	  --set api.ingress.host=api.$$IP.nip.io --set env.FAIL_HEALTHZ=true \
	  --atomic --timeout 5m && echo "CrashLoop induced. Wait a few minutes for alert."

mon-heal-crash: ## Heal CrashLoop (sets env.FAIL_HEALTHZ=false)
	@IP=$$(minikube ip); \
	helm upgrade --install $(HELM_NAME) $(HELM_DIR) -n $(HELM_NS) \
	  -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	  --set api.ingress.host=api.$$IP.nip.io --set env.FAIL_HEALTHZ=false \
	  --atomic --timeout 5m

mon-fire-cpu: ## Generate CPU load via /burn
	@IP=$$(minikube ip); for i in $$(seq 1 20); do curl -s "http://api.$$IP.nip.io/burn?seconds=5" >/dev/null & done; wait; \
	echo "CPU load fired. Watch alerts in ~5m."

# ----- Security ------
sec-apply: ## Apply security hardening (NP/PDB/PriorityClass via Helm)
	make helm-up-dev-atomic

sec-test: ## Quick NP test: block external HTTP, allow Redis & DNS
	@NS=$(HELM_NS); echo "Spinning ephemeral tester..."; \
	kubectl -n $$NS run netshoot --image=nicolaka/netshoot -it --rm --restart=Never -- \
	  sh -c 'echo "1) Test DNS (should work)"; nslookup kubernetes.default || exit 1; \
	         echo "2) Test outbound 1.1.1.1:80 (should FAIL)"; (timeout 3 bash -lc ">/dev/tcp/1.1.1.1/80" && exit 2) || echo BLOCKED_OK; \
	         echo "3) Test Redis svc (should work from api/worker only)"; exit 0'

sec-off: ## Disable default-deny (for troubleshooting) - not recommended for long
	helm upgrade --install $(HELM_NAME) $(HELM_DIR) -n $(HELM_NS) \
	  -f $(HELM_DIR)/values.yaml -f $(HELM_DIR)/values-dev.yaml \
	  --set api.ingress.host=api.$(shell minikube ip).nip.io \
	  --set networkPolicy.defaultDeny=false \
	  --atomic --timeout 5m


# ---- Redis backup / restore -------
REDIS_NS ?= october
BACKUPS_DIR ?= ./backups
BACKUP ?= $(shell ls -t ./backups/redis-backup-*.rdb 2>/dev/null | head -n1)


redis-backup: ## Backup Redis to ./backups/
	@NS=$(REDIS_NS) OUT_DIR=$(BACKUPS_DIR) bash scripts/redis-backup.sh

redis-list-backups: ## List local backups
	@ls -lht $(BACKUPS_DIR)/redis-backup-*.rdb 2>/dev/null || echo "No backups found in $(BACKUPS_DIR)/"

redis-restore: ## Restore Redis (BACKUP=./backups/redis-backup-*.rdb)
	@if [ -z "$(BACKUP)" ]; then echo "Usage: make redis-restore BACKUP=./backups/file.rdb"; exit 2; fi
	@NS=$(REDIS_NS) BACKUP=$(BACKUP) bash scripts/redis-restore.sh
