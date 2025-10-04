.PHONY: help venv install run-api run-worker clean

PY ?= python3
VENV ?= .venv
PIP := $(VENV)/bin/pip
PYTHON := $(VENV)/bin/python

help: ## Show help for targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

venv: ## Create virtualenv
	@test -d $(VENV) || $(PY) -m venv $(VENV)

install: venv ## Install all dependencies (API + worker)
	$(PIP) install --upgrade pip
	$(PIP) install -r api/requirements.txt
	$(PIP) install -r worker/requirements.txt

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
