# Book indexers for Shelfmark. Shelfmark calls Prowlarr's search API directly
# and only queries indexers whose capabilities include Books (7000-7999) or
# Audio/Audiobook (3030), so these never need to sync to an *arr app.

# Prowlarr pushes every indexer whose categories overlap an app's sync
# categories. Internet Archive maps "movies" to Movies and TV, so on the
# Standard profile it would land in Sonarr and Radarr. With every search
# flag off it syncs there disabled. Prowlarr's own /api/v1/search ignores
# app profiles, so Shelfmark still searches it.
resource "prowlarr_sync_profile" "books" {
  name                      = "Books"
  enable_rss                = false
  enable_automatic_search   = false
  enable_interactive_search = false
  minimum_seeders           = 1
}

# The only public ebook-specific tracker in Prowlarr's catalogue (sister site
# of AudioBook Bay). Its TLS chain doesn't verify against the system CAs; the
# definition pins the certificate, so no proxy is needed. The home IP reaches
# it directly; it isn't on the ISP's SNI blocklist (checked 2026-11-08).
resource "prowlarr_indexer" "ebookbay" {
  enable          = true
  name            = "EBookBay"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.books.id
  priority        = 20
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "ebookbay" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
  ]
}

# Public-domain and out-of-copyright texts plus LibriVox audiobooks (IA's
# "audio" maps to category 3000, which Shelfmark treats as audiobook). The
# torrents carry archive.org web seeds, so they download with zero peers.
# Its results are noisy, so it gets the lowest priority.
resource "prowlarr_indexer" "internet_archive" {
  enable          = true
  name            = "Internet Archive"
  implementation  = "Cardigann"
  config_contract = "CardigannSettings"
  protocol        = "torrent"
  app_profile_id  = prowlarr_sync_profile.books.id
  priority        = 40
  redirect        = false
  tags            = []

  fields = [
    { name = "definitionFile", text_value = "internetarchive" },
    { name = "baseSettings.limitsUnit", number_value = 0 },
    { name = "torrentBaseSettings.preferMagnetUrl", bool_value = false },
    { name = "titleOnly", bool_value = true },
    { name = "noMagnet", bool_value = false },
    { name = "sort", number_value = 2 },
    { name = "type", number_value = 1 },
  ]
}
