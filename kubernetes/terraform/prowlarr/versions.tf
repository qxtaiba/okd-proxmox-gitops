terraform {
  required_providers {
    prowlarr = {
      source  = "devopsarr/prowlarr"
      version = "~> 3.0"
    }
  }
}

provider "prowlarr" {
  url     = "http://prowlarr.default.svc.cluster.local:9696"
  api_key = var.prowlarr_api_key
}
