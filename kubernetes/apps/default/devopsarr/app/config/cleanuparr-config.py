"""Declarative Cleanuparr config, applied idempotently through its API.

Cleanuparr keeps everything in its own SQLite DB; this file is the source of
truth (UI edits to managed settings are reverted). Policy for public-tracker
torrents:
  - Queue Cleaner (every 5 min): strike torrents stuck fetching metadata (3),
    stalled (3, reset on progress), or below 100 KB/s for ~30 min (6), and
    failed imports (3). Struck downloads are removed via Sonarr/Radarr with
    blocklist, then Cleanuparr re-searches.
  - Malware Blocker (every 5 min): Cleanuparr's maintained blocklist of
    known-malicious file names/extensions.
  - Download Cleaner (hourly): delete torrents of the sonarr/radarr
    categories once imported (qBittorrent stops them at ratio 0; the library
    copy is a hardlink, so deleting the torrent frees nothing but clutter).
SABnzbd is not supported by Cleanuparr. DRY_RUN=true logs actions only.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = "http://cleanuparr.default.svc.cluster.local:11011/api"
USER = "svc-grappleberry-cleanuparr"
PASSWORD = os.environ["CLEANUPARR_PASSWORD"]
DRY_RUN = os.environ.get("DRY_RUN", "true").lower() == "true"
MASK = "•" * 8
headers = {}


def call(path, method="GET", body=None, ok=(200, 201, 204)):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=dict(headers, **({"Content-Type": "application/json"} if body is not None else {})))
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return None
        raise RuntimeError("%s %s -> %d %s" % (method, path, e.code, e.read().decode()[:300]))


def log(m):
    print(m, flush=True)


def norm(v):
    return json.dumps(v, sort_keys=True)


def subset(have, want):
    """True when every key in want matches have (recursing into dicts)."""
    if isinstance(want, dict):
        return isinstance(have, dict) and all(subset(have.get(k), v) for k, v in want.items())
    return norm(have) == norm(want)


def upsert_singleton(path, desired):
    have = call(path) or {}
    want = dict(have)
    want.update(desired)
    if subset(have, desired):
        return log(path + ": unchanged")
    for k, v in desired.items():
        if isinstance(v, dict) and isinstance(have.get(k), dict):
            want[k] = dict(have[k], **v)
    call(path, "PUT", want)
    log(path + ": updated " + ", ".join(k for k in desired if not subset(have.get(k), desired[k])))


def upsert_named(list_path, items, create_path, update_path, desired, secret_keys=()):
    by_name = {x.get("name"): x for x in items}
    have = by_name.get(desired["name"])
    if have is None:
        call(create_path, "POST", desired)
        return log(create_path + " " + desired["name"] + ": created")
    cmp_keys = [k for k in desired if k not in secret_keys]
    if subset(have, {k: desired[k] for k in cmp_keys}):
        return log(list_path + " " + desired["name"] + ": unchanged")
    call(update_path.format(id=have["id"]), "PUT", desired)
    log(list_path + " " + desired["name"] + ": updated")


# --- account: first-run setup, then log in and use the API key -------------
status = call("/auth/status")
if not status.get("setupCompleted"):
    call("/auth/setup/account", "POST", {"username": USER, "password": PASSWORD}, ok=(200, 201, 409))
    call("/auth/setup/complete", "POST", {}, ok=(200, 201, 403, 409))
    log("account: setup completed as " + USER)
tokens = call("/auth/login", "POST", {"username": USER, "password": PASSWORD})["tokens"]
headers["Authorization"] = "Bearer " + tokens["accessToken"]
headers["X-Api-Key"] = call("/account/api-key")["apiKey"]
del headers["Authorization"]

# --- download client ------------------------------------------------------
clients = call("/configuration/download_client")["clients"]
upsert_named("/configuration/download_client", clients, "/configuration/download_client",
             "/configuration/download_client/{id}",
             {"enabled": True, "name": "qbittorrent", "typeName": "qBittorrent", "type": "Torrent",
              "host": "http://qbittorrent.default.svc.cluster.local:8080",
              "username": os.environ["QBITTORRENT_USERNAME"], "password": os.environ["QBITTORRENT_PASSWORD"],
              "urlBase": ""}, secret_keys=("password",))
qbit_id = str([c for c in call("/configuration/download_client")["clients"] if c["name"] == "qbittorrent"][0]["id"])

# --- arrs -------------------------------------------------------------------
for arr, port, version in (("sonarr", 8989, 4), ("radarr", 7878, 6)):
    cfg = call("/configuration/" + arr)
    upsert_named("/configuration/" + arr, cfg.get("instances", []), "/configuration/%s/instances" % arr,
                 "/configuration/%s/instances/{id}" % arr,
                 {"enabled": True, "name": arr, "url": "http://%s.default.svc.cluster.local:%d" % (arr, port),
                  "apiKey": os.environ[arr.upper() + "_API_KEY"], "version": version}, secret_keys=("apiKey",))

# --- queue cleaner and its rules ----------------------------------------------
upsert_singleton("/configuration/queue_cleaner", {
    "enabled": True, "cronExpression": "0 0/5 * * * ?", "useAdvancedScheduling": True,
    "downloadingMetadataMaxStrikes": 3, "processNoContentId": False, "ignoredDownloads": [],
    "failedImport": {"maxStrikes": 3, "ignorePrivate": True, "deletePrivate": False, "skipIfNotFoundInClient": True,
                     "patterns": [], "patternMode": "Exclude", "changeCategory": False,
                     "forceImport": False, "forceImportMaxTries": 3}})
upsert_named("/queue-rules/stall", call("/queue-rules/stall") or [], "/queue-rules/stall", "/queue-rules/stall/{id}",
             {"name": "stalled", "enabled": True, "maxStrikes": 3, "privacyType": "Public",
              "minCompletionPercentage": 0, "maxCompletionPercentage": 100, "resetStrikesOnProgress": True,
              "minimumProgress": None, "deletePrivateTorrentsFromClient": False, "changeCategory": False})
upsert_named("/queue-rules/slow", call("/queue-rules/slow") or [], "/queue-rules/slow", "/queue-rules/slow/{id}",
             {"name": "slow", "enabled": True, "maxStrikes": 6, "privacyType": "Public",
              "minCompletionPercentage": 0, "maxCompletionPercentage": 100, "resetStrikesOnProgress": True,
              "minSpeed": "100KB", "maxTimeHours": 0, "ignoreAboveSize": None, "ignoreWhileAltSpeedActive": True})

# --- malware blocker ----------------------------------------------------------
bl = {"enabled": True, "blocklistType": "Blacklist", "blocklistPath": "https://cleanuparr.pages.dev/static/blacklist"}
upsert_singleton("/configuration/malware_blocker", {
    "enabled": True, "cronExpression": "0 0/5 * * * ?", "useAdvancedScheduling": True, "ignorePrivate": True,
    "deletePrivate": False, "processNoContentId": False, "deleteIfAnyFileBlocked": True, "ignoredDownloads": [],
    "sonarr": bl, "radarr": bl})

# --- download cleaner -----------------------------------------------------------
upsert_singleton("/configuration/download_cleaner", {
    "enabled": True, "cronExpression": "0 0 * * * ?", "useAdvancedScheduling": True, "ignoredDownloads": []})
rules = call("/seeding-rules/" + qbit_id) or []
upsert_named("/seeding-rules", rules, "/seeding-rules/" + qbit_id, "/seeding-rules/{id}",
             {"name": "arr-imported", "categories": ["sonarr", "radarr"], "privacyType": "Public", "maxRatio": 0,
              "minSeedTime": 0, "maxSeedTime": -1, "minSeeders": 0, "maxInactiveDays": -1,
              "deleteSourceFiles": True, "action": "Delete", "trackerPatterns": [], "tagsAny": [], "tagsAll": []})

# --- general (last: dry-run switch) ----------------------------------------------
general = call("/configuration/general")
upsert_singleton("/configuration/general", {
    "dryRun": DRY_RUN, "strikeInactivityWindowHours": 24,
    "auth": dict(general.get("auth") or {}, disableAuthForLocalAddresses=False)})
log("done (dryRun=%s)" % DRY_RUN)
