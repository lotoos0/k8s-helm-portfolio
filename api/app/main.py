import time
from fastapi import FastAPI, Request, Response, HTTPException
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest, Counter, Histogram

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
        return {"status": "ok"}

    @app.get("/ready")
    def ready():
        return {"ready": True}

    @app.get("/error-test")
    def error_test():
        """Test endpoint for 5xx monitoring"""
        raise HTTPException(status_code=500, detail="Test 500 error for monitoring")

    @app.get("/metrics")
    def metrics():
        data = generate_latest()  # default global registry
        return Response(content=data, media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
