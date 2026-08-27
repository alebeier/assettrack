variable "docker_host" {
  description = "Daemon Docker de VM-APP."
  type        = string
  default     = "ssh://deploy@192.168.56.20:22"
}

variable "grafana_password" {
  description = "Password del admin de Grafana."
  type        = string
  default     = "assettrack"
  sensitive   = true
}
