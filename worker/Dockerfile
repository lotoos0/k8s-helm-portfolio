# --------------- Builder stage --------------
FROM python:3.11-alpine3.20 AS builder

# Deterministic builds (no pip cache, no version check)
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Build deps for compiling packages (Alpine = musl)
RUN apk add --no-cache \
      gcc \
      musl-dev \
      libffi-dev \
      openssl-dev \
      && rm -rf /var/cache/apk/*

# Create runtime venv
RUN python -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip

# Install ONLY runtime deps into venv
COPY requirements.txt .
RUN /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


# --------------- Runtime stage ----------------
FROM python:3.11-alpine3.20 AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PIP_NO_CACHE_DIR=1

# Security: create non-root user (Alpine syntax)
RUN addgroup -S worker && adduser -S -D -H -u 10002 -G worker worker

WORKDIR /app

# Copy venv from builder
COPY --from=builder /opt/venv /opt/venv

# Copy app source
COPY app/ /app/worker/app/

# Drop privileges
USER worker

LABEL org.opencontainers.image.source="https://github.com/lotoos0/k8s-helm-portfolio" \
  org.opencontainers.image.description="DevOps October demo worker" \
  org.opencontainers.image.licenses="MIT"

# Command: Celery worker (single concurrency for simplicity)
CMD ["celery", "-A", "worker.app.celery_app.app", "worker", "--loglevel=info", "--concurrency=1"]

