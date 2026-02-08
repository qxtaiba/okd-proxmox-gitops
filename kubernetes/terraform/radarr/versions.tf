terraform {
  required_providers {
    radarr = {
      source  = "devopsarr/radarr"
      version = "~> 2.0"
    }
  }
}

provider "radarr" {
  url     = "http://radarr.default.svc.cluster.local:7878"
  api_key = var.radarr_api_key
}
