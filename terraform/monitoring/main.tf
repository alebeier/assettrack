# ---------------------------------------------------------------
# Stack de observabilidad. Ciclo de vida independiente de la app:
# se aplica a mano, no lo toca el pipeline.
# ---------------------------------------------------------------
locals {
  labels = {
    proyecto   = "assettrack"
    stack      = "monitoreo"
    gestionado = "terraform"
  }
}

# ---------------------------------------------------------------
# Imagenes
# ---------------------------------------------------------------
resource "docker_image" "prometheus" {
  name         = "prom/prometheus:v3.1.0"
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:11.5.1"
  keep_locally = true
}

resource "docker_image" "node_exporter" {
  name         = "prom/node-exporter:v1.8.2"
  keep_locally = true
}

resource "docker_image" "cadvisor" {
  name         = "gcr.io/cadvisor/cadvisor:v0.49.1"
  keep_locally = true
}

resource "docker_image" "portainer" {
  name         = "portainer/portainer-ce:2.21.5"
  keep_locally = true
}

# ---------------------------------------------------------------
# Volumenes
# ---------------------------------------------------------------
resource "docker_volume" "prometheus" { name = "monitoring-prometheus-data" }
resource "docker_volume" "grafana"    { name = "monitoring-grafana-data" }
resource "docker_volume" "portainer"  { name = "monitoring-portainer-data" }

# ---------------------------------------------------------------
# node-exporter: metricas del host (CPU, RAM, disco)
# ---------------------------------------------------------------
resource "docker_container" "node_exporter" {
  name         = "monitoring-node-exporter"
  image        = docker_image.node_exporter.image_id
  restart      = "unless-stopped"
  network_mode = "host"
  pid_mode     = "host"

  command = [
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--path.rootfs=/host/root",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
  ]

  volumes { host_path = "/proc" container_path = "/host/proc" read_only = true }
  volumes { host_path = "/sys"  container_path = "/host/sys"  read_only = true }
  volumes { host_path = "/"     container_path = "/host/root" read_only = true }

  dynamic "labels" {
    for_each = local.labels
    content { label = labels.key  value = labels.value }
  }
}

# ---------------------------------------------------------------
# cAdvisor: metricas por contenedor
# ---------------------------------------------------------------
resource "docker_container" "cadvisor" {
  name         = "monitoring-cadvisor"
  image        = docker_image.cadvisor.image_id
  restart      = "unless-stopped"
  network_mode = "host"
  privileged   = true

  command = ["--port=8081", "--housekeeping_interval=15s", "--docker_only=true"]

  volumes { host_path = "/"                container_path = "/rootfs"    read_only = true }
  volumes { host_path = "/var/run"         container_path = "/var/run"   read_only = true }
  volumes { host_path = "/sys"             container_path = "/sys"       read_only = true }
  volumes { host_path = "/var/lib/docker"  container_path = "/var/lib/docker" read_only = true }
  volumes { host_path = "/dev/disk"        container_path = "/dev/disk"  read_only = true }

  dynamic "labels" {
    for_each = local.labels
    content { label = labels.key  value = labels.value }
  }
}

# ---------------------------------------------------------------
# Prometheus
# ---------------------------------------------------------------
resource "docker_container" "prometheus" {
  name         = "monitoring-prometheus"
  image        = docker_image.prometheus.image_id
  restart      = "unless-stopped"
  network_mode = "host"
  user         = "root"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=15d",
    "--web.listen-address=:9090",
  ]

  upload {
    file    = "/etc/prometheus/prometheus.yml"
    content = file("${path.module}/../../monitoring/prometheus.yml")
  }

  volumes {
    volume_name    = docker_volume.prometheus.name
    container_path = "/prometheus"
  }

  depends_on = [docker_container.node_exporter, docker_container.cadvisor]

  dynamic "labels" {
    for_each = local.labels
    content { label = labels.key  value = labels.value }
  }
}

# ---------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------
resource "docker_container" "grafana" {
  name         = "monitoring-grafana"
  image        = docker_image.grafana.image_id
  restart      = "unless-stopped"
  network_mode = "host"
  user         = "root"

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_SERVER_HTTP_PORT=3000",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
  ]

  upload {
    file    = "/etc/grafana/provisioning/datasources/prometheus.yml"
    content = file("${path.module}/../../monitoring/grafana/datasource.yml")
  }

  upload {
    file    = "/etc/grafana/provisioning/dashboards/provider.yml"
    content = file("${path.module}/../../monitoring/grafana/dashboard-provider.yml")
  }

  upload {
    file    = "/var/lib/grafana/dashboards/assettrack.json"
    content = file("${path.module}/../../monitoring/grafana/assettrack-dashboard.json")
  }

  volumes {
    volume_name    = docker_volume.grafana.name
    container_path = "/var/lib/grafana/data"
  }

  depends_on = [docker_container.prometheus]

  dynamic "labels" {
    for_each = local.labels
    content { label = labels.key  value = labels.value }
  }
}

# ---------------------------------------------------------------
# Portainer: gestion visual de contenedores
# ---------------------------------------------------------------
resource "docker_container" "portainer" {
  name    = "monitoring-portainer"
  image   = docker_image.portainer.image_id
  restart = "unless-stopped"

  ports {
    internal = 9000
    external = 9500
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  volumes {
    volume_name    = docker_volume.portainer.name
    container_path = "/data"
  }

  dynamic "labels" {
    for_each = local.labels
    content { label = labels.key  value = labels.value }
  }
}
