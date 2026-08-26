terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }

  # El estado NO vive en el workspace del runner (se limpia en cada corrida).
  # La ruta concreta se pasa en el init:
  #   terraform init -backend-config="path=/opt/tfstate/dev/terraform.tfstate"
  backend "local" {}
}

provider "docker" {
  host = var.docker_host

  ssh_opts = [
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "UserKnownHostsFile=/dev/null",
  ]
}
