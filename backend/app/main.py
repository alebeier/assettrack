"""
AssetTrack - Inventario de activos de infraestructura.
API REST con FastAPI, persistencia SQLite y metricas Prometheus.
"""
import os
import sqlite3
import time
from contextlib import asynccontextmanager, contextmanager
from enum import Enum
from typing import Optional

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field
from starlette.requests import Request

# ---------------------------------------------------------------
# Configuracion por variables de entorno (las inyecta Terraform)
# ---------------------------------------------------------------
APP_VERSION = os.getenv("APP_VERSION", "dev")
GIT_SHA = os.getenv("GIT_SHA", "local")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
START_TIME = time.time()

# ---------------------------------------------------------------
# Metricas
# ---------------------------------------------------------------
http_requests_total = Counter(
    "assettrack_http_requests_total",
    "Total de requests HTTP procesados",
    ["method", "endpoint", "status"],
)

http_request_duration = Histogram(
    "assettrack_http_request_duration_seconds",
    "Latencia de los requests HTTP",
    ["method", "endpoint"],
)

# Metricas de negocio: esto es lo que diferencia el dashboard
assets_total = Gauge(
    "assettrack_assets_total",
    "Cantidad de activos registrados por criticidad",
    ["criticidad"],
)

assets_sin_responsable = Gauge(
    "assettrack_assets_sin_responsable",
    "Activos que no tienen responsable asignado",
)

app_info = Gauge(
    "assettrack_app_info",
    "Metadatos del despliegue actual",
    ["version", "git_sha", "environment"],
)
app_info.labels(APP_VERSION, GIT_SHA, ENVIRONMENT).set(1)


# ---------------------------------------------------------------
# Modelos
# ---------------------------------------------------------------
class TipoActivo(str, Enum):
    servidor = "servidor"
    servicio = "servicio"
    red = "red"
    almacenamiento = "almacenamiento"
    software = "software"
    consolas = "consolas"
    impresora = "impresora"


class Criticidad(str, Enum):
    alta = "alta"
    media = "media"
    baja = "baja"


class AssetIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)
    tipo: TipoActivo
    criticidad: Criticidad
    responsable: Optional[str] = Field(default=None, max_length=80)


class AssetOut(AssetIn):
    id: int


# ---------------------------------------------------------------
# Base de datos
# ---------------------------------------------------------------
def db_path() -> str:
    """Se resuelve en cada llamada, no al importar: los tests lo sobreescriben."""
    return os.getenv("DB_PATH", "/data/assettrack.db")


@contextmanager
def get_db():
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    destino = os.path.dirname(db_path())
    if destino:
        os.makedirs(destino, exist_ok=True)
    with get_db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS assets (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                nombre      TEXT NOT NULL,
                tipo        TEXT NOT NULL,
                criticidad  TEXT NOT NULL,
                responsable TEXT
            )
            """
        )


def refresh_business_metrics() -> None:
    """Recalcula los gauges de negocio a partir del estado real de la base."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT criticidad, COUNT(*) AS total FROM assets GROUP BY criticidad"
        ).fetchall()
        conteos = {r["criticidad"]: r["total"] for r in rows}

        for nivel in Criticidad:
            assets_total.labels(nivel.value).set(conteos.get(nivel.value, 0))

        huerfanos = conn.execute(
            "SELECT COUNT(*) AS total FROM assets "
            "WHERE responsable IS NULL OR TRIM(responsable) = ''"
        ).fetchone()["total"]
        assets_sin_responsable.set(huerfanos)


# ---------------------------------------------------------------
# Aplicacion
# ---------------------------------------------------------------
@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    refresh_business_metrics()
    yield


app = FastAPI(
    title="AssetTrack",
    description="Inventario de activos de infraestructura",
    version=APP_VERSION,
    lifespan=lifespan,
)


@app.middleware("http")
async def track_requests(request: Request, call_next):
    inicio = time.perf_counter()
    response = await call_next(request)
    duracion = time.perf_counter() - inicio

    endpoint = request.scope.get("route").path if request.scope.get("route") else "unknown"
    http_requests_total.labels(request.method, endpoint, response.status_code).inc()
    http_request_duration.labels(request.method, endpoint).observe(duracion)
    return response


# ---------------------------------------------------------------
# Endpoints operativos
# ---------------------------------------------------------------
@app.get("/health", tags=["operativo"])
def health():
    return {"status": "ok"}


@app.get("/api/version", tags=["operativo"])
def version():
    return {
        "version": APP_VERSION,
        "git_sha": GIT_SHA,
        "environment": ENVIRONMENT,
        "uptime_segundos": round(time.time() - START_TIME, 1),
    }


@app.get("/metrics", tags=["operativo"])
def metrics():
    refresh_business_metrics()
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------
# Endpoints de negocio
# ---------------------------------------------------------------
@app.get("/api/assets", response_model=list[AssetOut], tags=["activos"])
def listar_assets(criticidad: Optional[Criticidad] = None):
    with get_db() as conn:
        if criticidad:
            rows = conn.execute(
                "SELECT * FROM assets WHERE criticidad = ? ORDER BY id DESC",
                (criticidad.value,),
            ).fetchall()
        else:
            rows = conn.execute("SELECT * FROM assets ORDER BY id DESC").fetchall()
    return [dict(r) for r in rows]


@app.post("/api/assets", response_model=AssetOut, status_code=201, tags=["activos"])
def crear_asset(asset: AssetIn):
    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO assets (nombre, tipo, criticidad, responsable) VALUES (?, ?, ?, ?)",
            (asset.nombre, asset.tipo.value, asset.criticidad.value, asset.responsable),
        )
        nuevo_id = cursor.lastrowid
    refresh_business_metrics()
    return {**asset.model_dump(), "id": nuevo_id}


@app.delete("/api/assets/{asset_id}", status_code=204, tags=["activos"])
def borrar_asset(asset_id: int):
    with get_db() as conn:
        cursor = conn.execute("DELETE FROM assets WHERE id = ?", (asset_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Activo no encontrado")
    refresh_business_metrics()
    return Response(status_code=204)


@app.get("/api/stats", tags=["activos"])
def estadisticas():
    with get_db() as conn:
        rows = conn.execute(
            "SELECT criticidad, COUNT(*) AS total FROM assets GROUP BY criticidad"
        ).fetchall()
        total = conn.execute("SELECT COUNT(*) AS total FROM assets").fetchone()["total"]

    por_criticidad = {n.value: 0 for n in Criticidad}
    por_criticidad.update({r["criticidad"]: r["total"] for r in rows})

    return {"total": total, "por_criticidad": por_criticidad}
