variable "sonarr_api_key" {
  type      = string
  sensitive = true
}

variable "sabnzbd_api_key" {
  type      = string
  sensitive = true
}

variable "qbittorrent_username" {
  type      = string
  sensitive = true
}

variable "qbittorrent_password" {
  type      = string
  sensitive = true
}

variable "plex_token" {
  type      = string
  sensitive = true
}
