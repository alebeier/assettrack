# ---------------------------------------------------------------
# Convenciones de nombres
# ---------------------------------------------------------------
locals {
  suffix = var.environment

  labels = {
    proyecto    = "assettrack"
    environment = var.environment
    gestionado  = "terraform"
    git_sha     = var.git_sha
  }
}

# ---------------------------------------------------------------
# Red privada: el backend solo se alcanza desde aca adentro
# ---------------------------------------------------------------
resource "docker_network" "app" {
  name   = "assettrack-net-${local.suffix}"
  driver = "bridge"
}

# ---------------------------------------------------------------
# Volumen: la base sobrevive a la recreacion del contenedor
# ---------------------------------------------------------------
resource "docker_volume" "data" {
  name = "assettrack-data-${local.suffix}"

  lifecycle {
    prevent_destroy = false # ponelo en true para prod cuando termines de probar
  }
}

# ---------------------------------------------------------------
# Imagenes
# ---------------------------------------------------------------
resource "docker_image" "backend" {
  name         = var.backend_image
  keep_locally = true
}

resource "docker_image" "frontend" {
  name         = var.frontend_image
  keep_locally = true
}

# ---------------------------------------------------------------
# Backend: sin puerto publicado al host
# ---------------------------------------------------------------
resource "docker_container" "backend" {
  name     = "assettrack-backend-${local.suffix}"
  image    = docker_image.backend.image_id
  hostname = "backend"

  restart = "unless-stopped"

  env = [
    "ENVIRONMENT=${var.environment}",
    "GIT_SHA=${var.git_sha}",
    "APP_VERSION=${var.app_version}",
    "DB_PATH=/data/assettrack.db",
  ]

  # Solo 127.0.0.1: Prometheus (network_mode host) llega,
  # pero desde fuera de la VM sigue inaccesible.
  ports {
    internal = 8000
    external = var.backend_metrics_port
    ip       = "127.0.0.1"
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  networks_advanced {
    name    = docker_network.app.name
    aliases = ["backend"]
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# ---------------------------------------------------------------
# Frontend: nginx, unico expuesto
# ---------------------------------------------------------------
resource "docker_container" "frontend" {
  name  = "assettrack-frontend-${local.suffix}"
  image = docker_image.frontend.image_id

  restart = "unless-stopped"

  ports {
    internal = 8080
    external = var.frontend_port
  }

  networks_advanced {
    name = docker_network.app.name
  }

  depends_on = [docker_container.backend]

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
