# Torrent indexers. Imported on 2026-10-09 from the config first built in the UI;
# the import blocks adopt the existing objects (no-ops once in state) so their
# IDs, and Sonarr/Radarr's synced copies, stay stable.
#
# Every non-info field with a value must be listed (the provider manages the
# whole field set), including empty strings.
import {
  to = prowlarr_indexer.x1337
  id = 13
}
resource "prowlarr_indexer" "x1337" {
  # Disabled 2026-10-09: 1337x's Cloudflare rules return "Access denied" (403)
  # to both the home IP and the Proton exit, so no proxy combination reaches it.
  # Knaben aggregates 1337x results. Re-enable to retry.
  enable          = false
  name            = "1337x"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 15
  redirect        = false
  tags            = [prowlarr_tag.byparr.id]

  fields = [
    { name = "definitionFile", text_value = "1337x" },
    { name = "baseUrl", text_value = "https://1337x.st/" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "uploader", text_value = "" },
    { name = "primarydownloadlink", number_value = 1 },
    { name = "fallbackdownloadlink", number_value = 0 },
    { name = "disablesort", bool_value = false },
    { name = "sort", number_value = 2 },
    { name = "type", number_value = 1 },
  ]
}

import {
  to = prowlarr_indexer.torrentdownload
  id = 15
}
resource "prowlarr_indexer" "torrentdownload" {
  # VPN only: the ISP SNI-blocks torrentdownload.info; no Cloudflare challenge.
  enable          = true
  name            = "TorrentDownload"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 15
  redirect        = false
  tags            = [prowlarr_tag.vpn.id]

  fields = [
    { name = "definitionFile", text_value = "torrentdownload" },
    { name = "baseUrl", text_value = "https://www.torrentdownload.info/" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "sort", number_value = 1 },
  ]
}

import {
  to = prowlarr_indexer.kickasstorrents_to
  id = 14
}
resource "prowlarr_indexer" "kickasstorrents_to" {
  # Same Byparr + VPN pairing as ExtraTorrent above.
  enable          = true
  name            = "kickasstorrents.to"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 15
  redirect        = false
  tags            = [prowlarr_tag.byparr.id, prowlarr_tag.vpn.id]

  fields = [
    { name = "definitionFile", text_value = "kickasstorrents-to" },
    { name = "baseUrl", text_value = "https://kickass.torrentsbay.org/" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}

import {
  to = prowlarr_indexer.knaben
  id = 7
}
resource "prowlarr_indexer" "knaben" {
  enable          = true
  name            = "Knaben"
  implementation  = "Knaben"
  config_contract = "NoAuthTorrentBaseSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 20
  redirect        = false
  tags            = []

  fields = [
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}

import {
  to = prowlarr_indexer.limetorrents
  id = 8
}
resource "prowlarr_indexer" "limetorrents" {
  enable          = true
  name            = "LimeTorrents"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 20
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "limetorrents" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "primarydownloadlink", number_value = 1 },
    { name = "fallbackdownloadlink", number_value = 0 },
    { name = "sort", number_value = 0 },
  ]
}

import {
  to = prowlarr_indexer.the_pirate_bay
  id = 2
}
resource "prowlarr_indexer" "the_pirate_bay" {
  enable          = true
  name            = "The Pirate Bay"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 25
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "thepiratebay" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "apiurl", text_value = "apibay.org" },
    { name = "top100", number_value = 6 },
    { name = "uploader", text_value = "" },
  ]
}

import {
  to = prowlarr_indexer.kickasstorrents_ws
  id = 5
}
resource "prowlarr_indexer" "kickasstorrents_ws" {
  enable          = true
  name            = "kickasstorrents.ws"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 25
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "kickasstorrents-ws" },
    { name = "baseUrl", text_value = "https://kickasstorrents.bz/" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "sort", number_value = 2 },
    { name = "type", number_value = 1 },
  ]
}

import {
  to = prowlarr_indexer.eztv
  id = 12
}
resource "prowlarr_indexer" "eztv" {
  # Byparr only: EZTV answers from the home IP once the challenge is solved.
  enable          = true
  name            = "EZTV"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 30
  redirect        = false
  tags            = [prowlarr_tag.byparr.id]

  fields = [
    { name = "definitionFile", text_value = "eztv" },
    { name = "baseUrl", text_value = "https://eztv.wf/" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}

import {
  to = prowlarr_indexer.extratorrent_st
  id = 11
}
resource "prowlarr_indexer" "extratorrent_st" {
  # Cloudflare-protected: Byparr solves the challenge through the VPN, and the
  # vpn tag makes Prowlarr's own requests leave from the same Proton IP, which
  # the cf_clearance cookie is bound to. Byparr alone fails (IP mismatch).
  enable          = true
  name            = "ExtraTorrent.st"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 30
  redirect        = false
  tags            = [prowlarr_tag.byparr.id, prowlarr_tag.vpn.id]

  fields = [
    { name = "definitionFile", text_value = "extratorrent-st" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}

import {
  to = prowlarr_indexer.yts
  id = 10
}
resource "prowlarr_indexer" "yts" {
  enable          = true
  name            = "YTS"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 30
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "yts" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "apiurl", text_value = "movies-api.accel.li" },
  ]
}

import {
  to = prowlarr_indexer.showrss
  id = 9
}
resource "prowlarr_indexer" "showrss" {
  enable          = true
  name            = "showRSS"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.standard.id
  priority        = 30
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "showrss" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}
