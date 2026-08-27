output "urls" {
  description = "Accesos del stack de observabilidad"
  value = {
    grafana    = "http://192.168.56.20:3000"
    prometheus = "http://192.168.56.20:9090"
    cadvisor   = "http://192.168.56.20:8081"
    portainer  = "http://192.168.56.20:9500"
  }
}
