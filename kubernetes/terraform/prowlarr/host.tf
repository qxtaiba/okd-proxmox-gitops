# --- Host settings, including the UI login ---
# Adopted from the live config on 2026-10-10; only the username changed, to
# the svc-grappleberry-<app> convention. The password lives in 1Password
# (prowlarr / password) and reaches Terraform through devopsarr-secrets.
import {
  to = prowlarr_host.host
  id = 1
}
resource "prowlarr_host" "host" {
  launch_browser  = true
  port            = 9696
  url_base        = ""
  bind_address    = "*"
  application_url = ""
  instance_name   = "Prowlarr"
  proxy = {
    enabled                = false
    type                   = "http"
    hostname               = ""
    port                   = 8080
    username               = ""
    password               = ""
    bypass_filter          = ""
    bypass_local_addresses = true
  }
  ssl = {
    enabled                = false
    certificate_validation = "enabled"
    port                   = 6969
    cert_path              = ""
    cert_password          = ""
  }
  logging = {
    log_level         = "debug"
    log_size_limit    = 1
    analytics_enabled = true
    console_log_level = ""
  }
  backup = {
    folder    = "Backups"
    interval  = 7
    retention = 28
  }
  authentication = {
    method   = "forms"
    required = "enabled"
    username = "svc-grappleberry-prowlarr"
    password = var.prowlarr_password
  }
  update = {
    mechanism            = "docker"
    branch               = "develop"
    script_path          = ""
    update_automatically = false
  }
}
