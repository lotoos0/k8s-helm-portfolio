.PHONY: help venv install run-api run-worker clean

PY ?= python3
VENV ?= .venv
PIP := $(VENV)/bin/pip
PYTHON := $(VENV)/bin/python

help: ## Show help for targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

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
