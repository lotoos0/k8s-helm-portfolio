from .celery_app import app


@app.task
def add(x: int, y: int) -> int:
    return x + y


@app.task
def ping() -> str:
    return "pong"
