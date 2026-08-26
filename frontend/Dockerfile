# syntax=docker/dockerfile:1.7
FROM nginx:1.27-alpine

ARG GIT_SHA=local

LABEL org.opencontainers.image.title="assettrack-frontend" \
      org.opencontainers.image.source="https://github.com/alebeier/assettrack" \
      org.opencontainers.image.revision="${GIT_SHA}"

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/ || exit 1
