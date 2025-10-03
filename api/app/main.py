from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest


def create_app() -> FastAPI:
    app = FastAPI(title="DevOps October API", version="0.1.0")

    @app.get("/healthz")
    def healthz():
        return {"status", "ok"}

    @app.get("/metrics")
    def metrics():
        data = generate_latest()  # default global registry
        return Response(content=data, media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
