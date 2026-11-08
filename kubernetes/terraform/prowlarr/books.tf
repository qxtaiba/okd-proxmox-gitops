resource "prowlarr_sync_profile" "books" {
  name                      = "Books"
  enable_rss                = false
  enable_automatic_search   = false
  enable_interactive_search = false
  minimum_seeders           = 1
}

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
