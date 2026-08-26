variable "docker_host" {
  description = "Daemon Docker destino. Terraform le habla por SSH desde VM-CI."
  type        = string
  default     = "ssh://deploy@192.168.56.20:22"
}

variable "environment" {
  description = "Entorno logico. Sufija todos los recursos para que dev y prod convivan."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment tiene que ser 'dev' o 'prod'."
  }
}

variable "backend_image" {
  description = "Imagen del backend, con tag inmutable."
  type        = string
}

variable "frontend_image" {
  description = "Imagen del frontend."
  type        = string
}

variable "frontend_port" {
  description = "Puerto publicado en VM-APP. Es la unica puerta de entrada."
  type        = number
}

variable "git_sha" {
  description = "Commit desplegado. Se muestra en la UI y se expone como metrica."
  type        = string
  default     = "manual"
}

variable "app_version" {
  description = "Version de la aplicacion."
  type        = string
  default     = "0.1.0"
}
