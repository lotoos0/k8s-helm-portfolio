import hashlib
import os
import time
from typing import Optional

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

    @app.get("/compute/prime")
    def compute_prime(n: int = 1000):
        """
        Find the nth prime number (CPU-intensive).
        Default finds 1000th prime. Try n=5000 or n=10000 for heavier load.
        """
        if n < 1 or n > 50000:
            raise HTTPException(status_code=400, detail="n must be between 1 and 50000")

        start = time.perf_counter()

        def is_prime(num):
            if num < 2:
                return False
            if num == 2:
                return True
            if num % 2 == 0:
                return False
            for i in range(3, int(num**0.5) + 1, 2):
                if num % i == 0:
                    return False
            return True

        count = 0
        candidate = 2
        result = 0

        while count < n:
            if is_prime(candidate):
                count += 1
                result = candidate
            candidate += 1

        duration = time.perf_counter() - start
        return {
            "nth_prime": n,
            "prime_number": result,
            "duration_seconds": round(duration, 4),
        }

    @app.get("/compute/fibonacci")
    def compute_fibonacci(n: int = 35):
        """
        Calculate fibonacci number recursively (CPU-intensive).
        Default n=35. Try n=38-40 for heavier load (exponential complexity).
        Warning: n>42 will be very slow!
        """
        if n < 0 or n > 42:
            raise HTTPException(status_code=400, detail="n must be between 0 and 42")

        start = time.perf_counter()

        def fib(num):
            if num <= 1:
                return num
            return fib(num - 1) + fib(num - 2)

        result = fib(n)
        duration = time.perf_counter() - start

        return {
            "fibonacci_n": n,
            "fibonacci_result": result,
            "duration_seconds": round(duration, 4),
        }

    @app.get("/compute/hash")
    def compute_hash(
        iterations: int = 100000,
        data_size_kb: int = 100,
    ):
        """
        Hash large data multiple times (CPU + memory intensive).
        Default: 100k iterations on 100KB data.
        Try iterations=500000 or data_size_kb=1000 for heavier load.
        """
        if iterations < 1 or iterations > 1_000_000:
            raise HTTPException(
                status_code=400, detail="iterations must be between 1 and 1000000"
            )
        if data_size_kb < 1 or data_size_kb > 10000:
            raise HTTPException(
                status_code=400, detail="data_size_kb must be between 1 and 10000"
            )

        start = time.perf_counter()

        # Generate data
        data = b"x" * (data_size_kb * 1024)

        # Hash it multiple times
        result_hash = hashlib.sha256(data).hexdigest()
        for _ in range(iterations - 1):
            result_hash = hashlib.sha256(result_hash.encode()).hexdigest()

        duration = time.perf_counter() - start

        return {
            "iterations": iterations,
            "data_size_kb": data_size_kb,
            "final_hash": result_hash[:16] + "...",
            "duration_seconds": round(duration, 4),
        }

    @app.get("/memory/allocate")
    def memory_allocate(size_mb: int = 100, duration_seconds: float = 5.0):
        """
        Allocate memory for testing memory limits and OOMKill.
        Default: 100MB for 5 seconds.
        Try size_mb=500 or size_mb=1000 to test memory limits.
        """
        if size_mb < 1 or size_mb > 2000:
            raise HTTPException(
                status_code=400, detail="size_mb must be between 1 and 2000"
            )
        if duration_seconds < 0.1 or duration_seconds > 60:
            raise HTTPException(
                status_code=400, detail="duration_seconds must be between 0.1 and 60"
            )

        start = time.perf_counter()

        # Allocate memory (list of 1MB chunks)
        chunks = []
        chunk_size = 1024 * 1024  # 1MB
        for _ in range(size_mb):
            chunks.append(bytearray(chunk_size))

        # Hold memory for specified duration
        time.sleep(duration_seconds)

        allocated_mb = len(chunks)
        elapsed = time.perf_counter() - start

        # Clear memory
        chunks.clear()

        return {
            "allocated_mb": allocated_mb,
            "duration_seconds": round(elapsed, 4),
            "status": "memory_released",
        }

    @app.get("/slow")
    def slow(delay: float = 3.0):
        """
        Simulate slow I/O-bound operation (sleep).
        Default: 3 second delay.
        Useful for testing timeouts, readiness probes, and request queueing.
        """
        if delay < 0.1 or delay > 30:
            raise HTTPException(
                status_code=400, detail="delay must be between 0.1 and 30"
            )

        start = time.perf_counter()
        time.sleep(delay)
        elapsed = time.perf_counter() - start

        return {
            "requested_delay": delay,
            "actual_delay": round(elapsed, 4),
            "status": "completed",
        }

    @app.get("/metrics")
    def metrics():
        data = generate_latest()  # default global registry
        return Response(content=data, media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
