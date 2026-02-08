terraform {
  required_providers {
    sonarr = {
      source  = "devopsarr/sonarr"
      version = "~> 3.0"
    }
  }
}

provider "sonarr" {
  url     = "http://sonarr.default.svc.cluster.local:8989"
  api_key = var.sonarr_api_key
}
