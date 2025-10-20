# API Reference

## Table of Contents
- [Overview](#overview)
- [Base URL](#base-url)
- [Endpoints](#endpoints)
  - [Health Check](#health-check)
  - [Readiness Check](#readiness-check)
  - [Metrics](#metrics)
- [Response Formats](#response-formats)
- [Error Handling](#error-handling)
- [Code Examples](#code-examples)

## Overview

The October DevOps API is a FastAPI-based REST service designed to demonstrate production-grade health checks, readiness probes, and Prometheus metrics exposition.

**Service Information**:
- **Name**: DevOps October API
- **Version**: 0.1.0
- **Framework**: FastAPI
- **Port**: 8000 (container), 80 (service)

## Base URL

### Local Development (Docker)
```
http://localhost:8000
```

### Kubernetes (Port Forward)
```
http://localhost:8080
```

### Kubernetes (Ingress)
```
http://api.<minikube-ip>.nip.io
```

## Endpoints

### Health Check

**Endpoint**: `GET /healthz`

**Purpose**: Liveness probe endpoint to verify the application process is alive and responsive.

**Use Case**:
- Kubernetes liveness probe
- Monitoring systems
- Load balancer health checks

**Request**:
```http
GET /healthz HTTP/1.1
Host: api.example.com
```

**Response**:
```json
{
  "status": "ok"
}
```

**Status Codes**:
- `200 OK`: Service is healthy
- `500 Internal Server Error`: Service is unhealthy (rare)

**Example**:
```bash
curl -s http://localhost:8000/healthz
# Output: {"status":"ok"}
```

**Kubernetes Probe Configuration**:
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

---

### Readiness Check

**Endpoint**: `GET /ready`

**Purpose**: Readiness probe endpoint to verify the application is ready to accept traffic.

**Use Case**:
- Kubernetes readiness probe
- Pre-deployment health verification
- Load balancer ready check

**Request**:
```http
GET /ready HTTP/1.1
Host: api.example.com
```

**Response**:
```json
{
  "ready": true
}
```

**Status Codes**:
- `200 OK`: Service is ready to accept traffic
- `503 Service Unavailable`: Service is not ready (e.g., dependencies unavailable)

**Example**:
```bash
curl -s http://localhost:8000/ready
# Output: {"ready":true}
```

**Kubernetes Probe Configuration**:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Readiness vs Liveness**:
| Aspect | Liveness (`/healthz`) | Readiness (`/ready`) |
|--------|----------------------|---------------------|
| Purpose | Detect deadlocks/crashes | Detect temporary unavailability |
| Action on Failure | Restart pod | Remove from service endpoints |
| Checks | Process is alive | Dependencies available |

---

### Metrics

**Endpoint**: `GET /metrics`

**Purpose**: Expose Prometheus-compatible metrics for monitoring and observability.

**Use Case**:
- Prometheus scraping
- Metrics collection
- Performance monitoring

**Request**:
```http
GET /metrics HTTP/1.1
Host: api.example.com
```

**Response**:
```text
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 123.0
python_gc_objects_collected_total{generation="1"} 45.0
python_gc_objects_collected_total{generation="2"} 6.0

# HELP python_info Python platform information
# TYPE python_info gauge
python_info{implementation="CPython",major="3",minor="11",patchlevel="9",version="3.11.9"} 1.0

# HELP process_virtual_memory_bytes Virtual memory size in bytes.
# TYPE process_virtual_memory_bytes gauge
process_virtual_memory_bytes 234567890.0

# HELP process_resident_memory_bytes Resident memory size in bytes.
# TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 45678901.0

# HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.
# TYPE process_cpu_seconds_total counter
process_cpu_seconds_total 12.34
```

**Status Codes**:
- `200 OK`: Metrics successfully generated

**Content Type**: `text/plain; version=0.0.4; charset=utf-8`

**Example**:
```bash
curl -s http://localhost:8000/metrics | head -20
```

**Prometheus Scrape Configuration**:
```yaml
scrape_configs:
  - job_name: 'october-api'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - october
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: api
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        replacement: $1:8000
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
    scrape_interval: 15s
    metrics_path: /metrics
```

**Available Metrics** (default Prometheus client):
| Metric | Type | Description |
|--------|------|-------------|
| `python_gc_objects_collected_total` | Counter | Objects collected during garbage collection |
| `python_info` | Gauge | Python version information |
| `process_virtual_memory_bytes` | Gauge | Virtual memory size |
| `process_resident_memory_bytes` | Gauge | Resident memory size (RSS) |
| `process_cpu_seconds_total` | Counter | Total CPU time |
| `process_open_fds` | Gauge | Number of open file descriptors |
| `process_max_fds` | Gauge | Maximum number of open file descriptors |
| `process_start_time_seconds` | Gauge | Process start time (Unix timestamp) |

**Custom Metrics** (planned for M4):
```python
from prometheus_client import Counter, Histogram

http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)
```

---

## Response Formats

### JSON Responses

All JSON responses follow this structure:

**Success Response**:
```json
{
  "status": "ok",
  "data": { ... },
  "timestamp": "2025-10-19T12:34:56Z"
}
```

**Error Response**:
```json
{
  "status": "error",
  "message": "Error description",
  "code": "ERROR_CODE",
  "timestamp": "2025-10-19T12:34:56Z"
}
```

### Content Types

- JSON endpoints: `application/json`
- Metrics endpoint: `text/plain; version=0.0.4`

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | Use Case |
|------|---------|----------|
| `200 OK` | Success | Request processed successfully |
| `400 Bad Request` | Client error | Invalid request parameters |
| `404 Not Found` | Resource not found | Endpoint does not exist |
| `500 Internal Server Error` | Server error | Unexpected server error |
| `503 Service Unavailable` | Temporarily unavailable | Dependency failure, not ready |

### Error Response Example

```json
{
  "detail": "Not Found"
}
```

**FastAPI Automatic Errors**:
- `404`: Route not found
- `405`: Method not allowed
- `422`: Validation error (Pydantic)
- `500`: Unhandled exception

---

## Code Examples

### Python (requests)

```python
import requests

# Base URL
BASE_URL = "http://localhost:8000"

# Health check
response = requests.get(f"{BASE_URL}/healthz")
print(response.json())
# Output: {'status': 'ok'}

# Readiness check
response = requests.get(f"{BASE_URL}/ready")
print(response.json())
# Output: {'ready': True}

# Metrics
response = requests.get(f"{BASE_URL}/metrics")
print(response.text[:200])
# Output: # HELP python_gc_objects_collected_total...
```

### cURL

```bash
# Health check
curl -s http://localhost:8000/healthz | jq .

# Readiness check
curl -s http://localhost:8000/ready | jq .

# Metrics (first 20 lines)
curl -s http://localhost:8000/metrics | head -20

# With Ingress
MINIKUBE_IP=$(minikube ip)
curl -s http://api.$MINIKUBE_IP.nip.io/healthz
```

### JavaScript (fetch)

```javascript
const BASE_URL = 'http://localhost:8000';

// Health check
fetch(`${BASE_URL}/healthz`)
  .then(response => response.json())
  .then(data => console.log(data));
// Output: {status: 'ok'}

// Readiness check
fetch(`${BASE_URL}/ready`)
  .then(response => response.json())
  .then(data => console.log(data));
// Output: {ready: true}

// Metrics
fetch(`${BASE_URL}/metrics`)
  .then(response => response.text())
  .then(text => console.log(text.substring(0, 200)));
```

### Go

```go
package main

import (
    "fmt"
    "io"
    "net/http"
)

func main() {
    baseURL := "http://localhost:8000"

    // Health check
    resp, _ := http.Get(baseURL + "/healthz")
    body, _ := io.ReadAll(resp.Body)
    fmt.Println(string(body))
    // Output: {"status":"ok"}

    // Readiness check
    resp, _ = http.Get(baseURL + "/ready")
    body, _ = io.ReadAll(resp.Body)
    fmt.Println(string(body))
    // Output: {"ready":true}
}
```

### Shell Script (Monitoring)

```bash
#!/bin/bash
# healthcheck-monitor.sh

API_URL="${1:-http://localhost:8000}"
INTERVAL="${2:-10}"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Health check
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/healthz")

    # Readiness check
    READY=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/ready")

    if [ "$HEALTH" = "200" ] && [ "$READY" = "200" ]; then
        echo "[$TIMESTAMP] ✓ Healthy and Ready"
    else
        echo "[$TIMESTAMP] ✗ Health: $HEALTH, Ready: $READY"
    fi

    sleep "$INTERVAL"
done
```

Usage:
```bash
chmod +x healthcheck-monitor.sh
./healthcheck-monitor.sh http://api.192.168.49.2.nip.io 5
```

---

## OpenAPI Specification

FastAPI automatically generates OpenAPI documentation:

### Interactive Documentation

**Swagger UI**: `http://localhost:8000/docs`

Features:
- Interactive API explorer
- Try out endpoints
- View request/response schemas
- Download OpenAPI spec

**ReDoc**: `http://localhost:8000/redoc`

Features:
- Clean, readable documentation
- Three-panel layout
- Code samples
- Search functionality

### OpenAPI JSON

**Endpoint**: `http://localhost:8000/openapi.json`

```json
{
  "openapi": "3.1.0",
  "info": {
    "title": "DevOps October API",
    "version": "0.1.0"
  },
  "paths": {
    "/healthz": {
      "get": {
        "summary": "Healthz",
        "operationId": "healthz_healthz_get",
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {}
              }
            }
          }
        }
      }
    }
  }
}
```

---

## Testing

### Unit Tests

Location: `api/tests/test_main.py`

```python
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_ready():
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"ready": True}

def test_metrics():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert "python_info" in response.text
```

### Integration Tests

```bash
# Start service
make run-api-docker

# Test endpoints
curl -f http://localhost:8000/healthz || echo "Health check failed"
curl -f http://localhost:8000/ready || echo "Ready check failed"
curl -f http://localhost:8000/metrics | grep -q "python_info" || echo "Metrics failed"

# Cleanup
make stop-api
```

### Load Testing

```bash
# Using custom load tester
make load-test URL=http://localhost:8000/healthz CONC=100 DUR=60

# Using Apache Bench
ab -n 10000 -c 100 http://localhost:8000/healthz

# Using wrk
wrk -t4 -c100 -d60s http://localhost:8000/healthz
```

---

## Rate Limiting (Future)

Planned implementation for production:

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.get("/healthz")
@limiter.limit("100/minute")
def healthz():
    return {"status": "ok"}
```

---

## Authentication (Future)

Planned for protected endpoints:

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.credentials != "valid-token":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials"
        )
    return credentials.credentials
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-19
**API Version**: 0.1.0
