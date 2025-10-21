import os
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

FAIL_HEALTHZ = os.getenv("FAIL_HEALTHZ", "false").lower() == "true"

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP request",
    ["method", "path", "status"],
)
REQ_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path", "status"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
)


def create_app() -> FastAPI:
    app = FastAPI(title="DevOps October API", version="0.1.0")

    @app.middleware("http")
    async def metrics_middleware(request: Request, call_next):
        start = time.perf_counter()
        response: Response = await call_next(request)
        status = str(response.status_code)
        path = request.url.path
        method = request.method
        REQUESTS.labels(method, path, status).inc()
        duration = time.perf_counter() - start
        REQ_LATENCY.labels(method, path, status).observe(duration)
        print(f"[METRICS] {method} {path} {status} {duration:.4f}s")  # DEBUG
        return response

    @app.get("/healthz")
    def healthz():
        if FAIL_HEALTHZ:
            return Response(status_code=500)
        return {"status": "ok"}

    @app.get("/ready")
    def ready():
        return {"ready": True}

    @app.get("/error-test")
    def error_test():
        """Test endpoint for 5xx monitoring"""
        raise HTTPException(status_code=500, detail="Test 500 error for monitoring")

    @app.get("/burn")
    def burn(seconds: float = 2.0):
        # simple CPU-bound to test HPA/CPU alert
        end = time.perf_counter() + max(0.1, float(seconds))
        x = 0.0
        while time.perf_counter() < end:
            x += 3.14159 * 2.71828  # π × e
        return {"burned_s": seconds}

    @app.get("/metrics")
    def metrics():
        data = generate_latest()  # default global registry
        return Response(content=data, media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
