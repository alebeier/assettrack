# syntax=docker/dockerfile:1.7
# ---------- etapa 1: dependencias ----------
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- etapa 2: runtime ----------
FROM python:3.12-slim

ARG GIT_SHA=local
ARG APP_VERSION=dev

LABEL org.opencontainers.image.title="assettrack-backend" \
      org.opencontainers.image.description="API de inventario de activos" \
      org.opencontainers.image.source="https://github.com/alebeier/assettrack" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    GIT_SHA=${GIT_SHA} \
    APP_VERSION=${APP_VERSION} \
    DB_PATH=/data/assettrack.db

COPY --from=builder /install /usr/local

WORKDIR /srv
COPY app/ ./app/

# Usuario sin privilegios: control de seguridad exigible en la defensa
RUN useradd --system --uid 10001 --create-home appuser \
    && mkdir -p /data \
    && chown -R appuser:appuser /data /srv
USER appuser

VOLUME ["/data"]
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
