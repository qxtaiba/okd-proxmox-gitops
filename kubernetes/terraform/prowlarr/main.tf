# --- NZBGeek Indexer ---
resource "prowlarr_indexer" "nzbgeek" {
  enable          = true
  name            = "NZBGeek"
  implementation  = "Newznab"
  config_contract = "NewznabSettings"
  protocol        = "usenet"
  app_profile_id  = 1
  priority        = 10
  redirect        = true

  fields = [
    {
      name       = "baseUrl"
      text_value = "https://api.nzbgeek.info"
    },
    {
      name       = "apiPath"
      text_value = "/api"
    },
    {
      name       = "apiKey"
      text_value = var.nzbgeek_api_key
    },
    {
      name       = "additionalParameters"
      text_value = ""
    },
    {
      name       = "vipExpiration"
      text_value = ""
    },
    {
      name         = "baseSettings.queryLimit"
      number_value = 0
    },
    {
      name         = "baseSettings.grabLimit"
      number_value = 0
    },
    {
      name         = "baseSettings.limitsUnit"
      number_value = 0
    },
    {
      name      = "categories"
      set_value = [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 5000, 5010, 5020, 5030, 5040, 5045, 5050, 5070]
    },
  ]
}

# --- SABnzbd Download Client ---
resource "prowlarr_download_client_sabnzbd" "sabnzbd" {
  enable   = true
  priority = 1
  name     = "SABnzbd"
  host     = "sabnzbd.default.svc.cluster.local"
  port     = 8080
  api_key  = var.sabnzbd_api_key
  use_ssl  = false
  category = "prowlarr"
}

# --- App Sync: Sonarr ---
resource "prowlarr_application_sonarr" "sonarr" {
  name                  = "Sonarr"
  sync_level            = "fullSync"
  base_url              = "http://sonarr.default.svc.cluster.local:8989"
  prowlarr_url          = "http://prowlarr.default.svc.cluster.local:9696"
  api_key               = var.sonarr_api_key
  sync_categories       = [5000, 5010, 5020, 5030, 5040, 5045, 5050]
  anime_sync_categories = [5070]
}

# --- App Sync: Radarr ---
resource "prowlarr_application_radarr" "radarr" {
  name            = "Radarr"
  sync_level      = "fullSync"
  base_url        = "http://radarr.default.svc.cluster.local:7878"
  prowlarr_url    = "http://prowlarr.default.svc.cluster.local:9696"
  api_key         = var.radarr_api_key
  sync_categories = [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]
}
