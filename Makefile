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


