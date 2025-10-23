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
# (Dev deps like pytest/ruff are installed locally or in CI, not in the image)
COPY requirements.txt .
RUN /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


# --------------- Runtime stage ----------------
FROM python:3.11-alpine3.20 AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PIP_NO_CACHE_DIR=1 \
  PORT=8000

# Security: create non-root user
RUN addgroup -S app && adduser -S -D -H -u 10001 -G app appuser

WORKDIR /app

# Copy venv from builder
COPY --from=builder /opt/venv /opt/venv

# Copy app source
COPY app/ /app/api/app/

# Drop privileges
USER appuser

# Expose app port
EXPOSE 8000

# Healthcheck – check endpoint liveness
HEALTHCHECK --interval=20s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request, sys; \
    sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"

LABEL org.opencontainers.image.source="https://github.com/lotoos0/k8s-helm-portfolio" \
  org.opencontainers.image.description="DevOps October demo service" \
  org.opencontainers.image.licenses="MIT"

# Command: uvicorn (explicit single worker for prometheus_client compatibility)
CMD ["uvicorn", "api.app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
