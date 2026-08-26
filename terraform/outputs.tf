output "url_app" {
  description = "Donde ver la aplicacion corriendo"
  value       = "http://192.168.56.20:${var.frontend_port}"
}

output "environment" {
  value = var.environment
}

output "git_sha_desplegado" {
  value = var.git_sha
}

output "contenedores" {
  value = {
    backend  = docker_container.backend.name
    frontend = docker_container.frontend.name
  }
}
