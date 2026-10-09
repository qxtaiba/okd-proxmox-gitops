# --- Tags: route an indexer through a proxy by tagging it ---
import {
  to = prowlarr_tag.byparr
  id = 1
}
resource "prowlarr_tag" "byparr" {
  label = "byparr"
}

import {
  to = prowlarr_tag.vpn
  id = 2
}
resource "prowlarr_tag" "vpn" {
  label = "vpn"
}

# --- Indexer proxies ---
# Byparr: FlareSolverr-compatible Cloudflare challenge solver
# (kubernetes/apps/default/byparr). Its browser egresses through gluetun, so
# challenges are solved from the Proton exit IP.
import {
  to = prowlarr_indexer_proxy_flaresolverr.byparr
  id = 1
}
resource "prowlarr_indexer_proxy_flaresolverr" "byparr" {
  name            = "Byparr"
  host            = "http://byparr.default.svc.cluster.local:8191/"
  request_timeout = 90
  tags            = [prowlarr_tag.byparr.id]
}

# Proton VPN: gluetun's HTTP proxy in the qbittorrent pod. Gets indexer
# traffic past the ISP's SNI blocks, and keeps Prowlarr on the same exit IP
# that Byparr's cf_clearance cookies are bound to.
import {
  to = prowlarr_indexer_proxy_http.proton_vpn
  id = 2
}
resource "prowlarr_indexer_proxy_http" "proton_vpn" {
  name     = "Proton VPN"
  host     = "qbittorrent-proxy.default.svc.cluster.local"
  port     = 8888
  username = ""
  password = ""
  tags     = [prowlarr_tag.vpn.id]
}

# --- Sync profile pushed to Sonarr/Radarr with every indexer ---
# minimum_seeders 5: public trackers list plenty of dead torrents; below five
# seeders a grab usually stalls.
import {
  to = prowlarr_sync_profile.standard
  id = 1
}
resource "prowlarr_sync_profile" "standard" {
  name                      = "Standard"
  enable_rss                = true
  enable_automatic_search   = true
  enable_interactive_search = true
  minimum_seeders           = 5
}
