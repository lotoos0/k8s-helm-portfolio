from fastapi.testclient import TestClient
from api.app.main import app

client = TestClient(app)


def test_healthz_ok():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_ready_ok():
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json() == {"ready": True}


def test_metrics_exposes_text():
    r = client.get("/metrics")
    assert r.status_code == 200
    # Prometheus exposition format (text/plain)
    assert "python_info" in r.text or "process_start_time_secounds" in r.text
