# --------------- Builder stage --------------
FROM python:3.11-slim AS builder

# Faster and deterministic builds
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
  PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps for building wheels if needed (kept minimal) 
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \ 
      && rm -rf /var/lib/apt/lists/* 

# Copy only dependency manifests to leverage layer caching
COPY requirements.txt /app/requirements.txt

# Create a dedicated folder for deps
RUN python -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip \
      && /opt/venv/bin/pip install -r /app/requirements.txt


# --------------- Runtime stage ----------------
FROM python:3.11-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PORT=8000

# Security: create non-root user
RUN useradd -u 10001 -m appuser

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
  CMD sh -c 'python -c "import urllib.request, sys; urllib.request.urlopen(\"http://127.0.0.1:8000/healthz\", timeout=2); sys.exit(0)" || exit 1'

LABEL org.opencontainers.image.source="https://github.com/lotoos0/k8s-helm-portfolio" \
  org.opencontainers.image.description="DevOps October demo service" \
  org.opencontainers.image.licenses="MIT"

# Command: uvicorn
CMD ["uvicorn", "api.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
