import os
from celery import Celery

BROKER_URL = os.getenv("BROKER_URL", "redis://localhost:6379/0")
RESULT_BACKEND = os.getenv("RESULT_BACKEND", "redis://localhost:6379/1")

# Single place to import Celery app from
app = Celery("october_worker", broker=BROKER_URL, backend=RESULT_BACKEND)
app.conf.update(
    task_ignore_result=False,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
)

# Import tasks to register them with Celery
from . import tasks  # noqa: E402, F401
