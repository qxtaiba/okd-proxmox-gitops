# --- Root Folders ---
resource "sonarr_root_folder" "main_tv" {
  path = "/media/main/tv"
}

resource "sonarr_root_folder" "kids_tv" {
  path = "/media/kids/tv"
}

# --- Download Clients ---
resource "sonarr_download_client_sabnzbd" "sabnzbd" {
  enable   = true
  priority = 1
  name     = "SABnzbd"
  host     = "sabnzbd.default.svc.cluster.local"
  port     = 8080
  api_key  = var.sabnzbd_api_key
  use_ssl  = false

  tv_category                = "sonarr"
  remove_completed_downloads = true
  remove_failed_downloads    = true
}

resource "sonarr_download_client_qbittorrent" "qbittorrent" {
  enable   = true
  priority = 2
  name     = "qBittorrent"
  host     = "qbittorrent.default.svc.cluster.local"
  port     = 8080
  username = var.qbittorrent_username
  password = var.qbittorrent_password
  use_ssl  = false

  tv_category                = "sonarr"
  recent_tv_priority         = 0
  older_tv_priority          = 0
  remove_completed_downloads = true
  remove_failed_downloads    = true
  first_and_last             = false
}

# --- Plex Notification ---
resource "sonarr_notification_plex" "plex" {
  name       = "Plex"
  host       = "plex.default.svc.cluster.local"
  port       = 32400
  auth_token = var.plex_token
  use_ssl    = false

  on_download                        = true
  on_upgrade                         = true
  on_rename                          = true
  on_series_add                      = false
  on_series_delete                   = true
  on_episode_file_delete             = true
  on_episode_file_delete_for_upgrade = false

  update_library = true
}

# --- TRaSH Naming ---
resource "sonarr_naming" "naming" {
  rename_episodes            = true
  replace_illegal_characters = true
  multi_episode_style        = 5
  colon_replacement_format   = 4
  standard_episode_format    = "{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Custom Formats }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  daily_episode_format       = "{Series TitleYear} - {Air-Date} - {Episode CleanTitle} [{Custom Formats }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  anime_episode_format       = "{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} [{Custom Formats }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}"
  series_folder_format       = "{Series TitleYear} [tvdbid-{TvdbId}]"
  season_folder_format       = "Season {season:00}"
  specials_folder_format     = "Specials"
}

# --- Media Management ---
resource "sonarr_media_management" "media_management" {
  unmonitor_previous_episodes = true
  hardlinks_copy              = false
  create_empty_folders        = false
  delete_empty_folders        = true
  enable_media_info           = true
  import_extra_files          = true
  set_permissions             = false
  skip_free_space_check       = false
  minimum_free_space          = 100
  recycle_bin_days            = 7
  chmod_folder                = "755"
  chown_group                 = ""
  download_propers_repacks    = "doNotPrefer"
  episode_title_required      = "always"
  extra_file_extensions       = "srt,nfo"
  file_date                   = "none"
  recycle_bin_path            = ""
  rescan_after_refresh        = "always"
}
