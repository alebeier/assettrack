"""Tests de AssetTrack. Usan una base SQLite temporal, aislada por test."""
import os
import tempfile

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    tmpdir = tempfile.mkdtemp()
    db_path = os.path.join(tmpdir, "test.db")
    monkeypatch.setenv("DB_PATH", db_path)

    from app.main import app, init_db

    init_db()
    with TestClient(app) as c:
        yield c


def test_health_responde_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_version_expone_metadatos_del_despliegue(client):
    r = client.get("/api/version")
    assert r.status_code == 200
    body = r.json()
    assert "git_sha" in body
    assert "environment" in body
    assert body["uptime_segundos"] >= 0


def test_listado_arranca_vacio(client):
    r = client.get("/api/assets")
    assert r.status_code == 200
    assert r.json() == []


def test_alta_de_activo(client):
    payload = {
        "nombre": "srv-radar-01",
        "tipo": "servidor",
        "criticidad": "alta",
        "responsable": "Alejandro",
    }
    r = client.post("/api/assets", json=payload)
    assert r.status_code == 201
    assert r.json()["id"] > 0
    assert r.json()["nombre"] == "srv-radar-01"


def test_alta_rechaza_criticidad_invalida(client):
    payload = {"nombre": "srv-x", "tipo": "servidor", "criticidad": "urgente"}
    r = client.post("/api/assets", json=payload)
    assert r.status_code == 422


def test_alta_rechaza_nombre_corto(client):
    payload = {"nombre": "x", "tipo": "red", "criticidad": "baja"}
    r = client.post("/api/assets", json=payload)
    assert r.status_code == 422


def test_filtro_por_criticidad(client):
    client.post("/api/assets", json={"nombre": "srv-a", "tipo": "servidor", "criticidad": "alta"})
    client.post("/api/assets", json={"nombre": "srv-b", "tipo": "servidor", "criticidad": "baja"})

    r = client.get("/api/assets?criticidad=alta")
    assert r.status_code == 200
    assert len(r.json()) == 1
    assert r.json()[0]["nombre"] == "srv-a"


def test_borrado_de_activo(client):
    creado = client.post(
        "/api/assets", json={"nombre": "srv-temp", "tipo": "red", "criticidad": "media"}
    ).json()

    r = client.delete(f"/api/assets/{creado['id']}")
    assert r.status_code == 204
    assert client.get("/api/assets").json() == []


def test_borrado_inexistente_da_404(client):
    r = client.delete("/api/assets/9999")
    assert r.status_code == 404


def test_stats_cuenta_por_criticidad(client):
    client.post("/api/assets", json={"nombre": "srv-a", "tipo": "servidor", "criticidad": "alta"})
    client.post("/api/assets", json={"nombre": "srv-b", "tipo": "servidor", "criticidad": "alta"})

    r = client.get("/api/stats")
    assert r.json()["total"] == 2
    assert r.json()["por_criticidad"]["alta"] == 2
    assert r.json()["por_criticidad"]["baja"] == 0


def test_metrics_expone_formato_prometheus(client):
    client.post("/api/assets", json={"nombre": "srv-m", "tipo": "servidor", "criticidad": "alta"})

    r = client.get("/metrics")
    assert r.status_code == 200
    assert "assettrack_assets_total" in r.text
    assert "assettrack_http_requests_total" in r.text
