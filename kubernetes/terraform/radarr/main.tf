# --- Imports (one-time state recovery) ---
import {
  to = radarr_root_folder.main_movies
  id = "2"
}

import {
  to = radarr_root_folder.kids_movies
  id = "3"
}

import {
  to = radarr_download_client_sabnzbd.sabnzbd
  id = "2"
}

import {
  to = radarr_download_client_qbittorrent.qbittorrent
  id = "1"
}

import {
  to = radarr_notification_plex.plex
  id = "1"
}

import {
  to = radarr_naming.naming
  id = "1"
}

import {
  to = radarr_media_management.media_management
  id = "1"
}

# --- Root Folders ---
resource "radarr_root_folder" "main_movies" {
  path = "/media/main/movies"
}

resource "radarr_root_folder" "kids_movies" {
  path = "/media/kids/movies"
}

# --- Download Clients ---
resource "radarr_download_client_sabnzbd" "sabnzbd" {
  enable   = true
  priority = 1
  name     = "SABnzbd"
  host     = "sabnzbd.default.svc.cluster.local"
  port     = 8080
  api_key  = var.sabnzbd_api_key
  use_ssl  = false

  movie_category             = "radarr"
  remove_completed_downloads = true
  remove_failed_downloads    = true
}

resource "radarr_download_client_qbittorrent" "qbittorrent" {
  enable   = true
  priority = 2
  name     = "qBittorrent"
  host     = "qbittorrent.default.svc.cluster.local"
  port     = 8080
  username = var.qbittorrent_username
  password = var.qbittorrent_password
  use_ssl  = false

  movie_category             = "radarr"
  recent_movie_priority      = 0
  older_movie_priority       = 0
  remove_completed_downloads = true
  remove_failed_downloads    = true
  first_and_last             = false
}

# --- Plex Notification ---
resource "radarr_notification_plex" "plex" {
  name            = "Plex"
  host            = "plex.default.svc.cluster.local"
  port            = 32400
  auth_token      = var.plex_token
  use_ssl         = false
  on_movie_delete = true

  on_download                      = true
  on_upgrade                       = true
  on_rename                        = true
  on_movie_added                   = false
  on_movie_file_delete             = true
  on_movie_file_delete_for_upgrade = false

  update_library = true
}

# --- TRaSH Naming ---
resource "radarr_naming" "naming" {
  rename_movies              = true
  replace_illegal_characters = true
  colon_replacement_format   = "smart"
  standard_movie_format      = "{Movie CleanTitle} {(Release Year)} {Edition Tags} [{Custom Formats }{Quality Full}]{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  movie_folder_format        = "{Movie CleanTitle} ({Release Year}) [imdbid-{ImdbId}]"
}

# --- Media Management ---
resource "radarr_media_management" "media_management" {
  auto_unmonitor_previously_downloaded_movies = true
  recycle_bin                                 = ""
  recycle_bin_cleanup_days                    = 7
  download_propers_and_repacks                = "doNotPrefer"
  create_empty_movie_folders                  = false
  delete_empty_folders                        = true
  file_date                                   = "none"
  rescan_after_refresh                        = "always"
  auto_rename_folders                         = false
  paths_default_static                        = false
  set_permissions_linux                       = false
  chmod_folder                                = "755"
  chown_group                                 = ""
  skip_free_space_check_when_importing        = false
  minimum_free_space_when_importing           = 100
  copy_using_hardlinks                        = false
  import_extra_files                          = true
  extra_file_extensions                       = "srt,nfo"
  enable_media_info                           = true
}
