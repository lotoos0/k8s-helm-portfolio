# ---------- Builder --------------
FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK_1 \
  PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt

RUN python -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip \
      && /opt/venv/bin/pip install -r /app/requirements.txt


# ------------ Runtime ----------------
FROM python:3.11-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Security: non-root user
RUN useradd -u 10002 -m worker

WORKDIR /app

# Copy venv and source
COPY --from=builder /opt/venv /opt/venv
COPY app/ /app/worker/app/

USER worker

#opt
CMD ["celery", "-A", "worker.app.celery_app.app", "worker", "-l", "info", "--concurrency=1"]
