# Periodic re-search for Sonarr and Radarr.
#
# Both apps only look for a release once when an item is added (or after a
# failed download) and then wait for NEW releases to appear in indexer RSS.
# If every release they found was broken -- e.g. usenet copies taken down
# before they completed -- the item sits "missing" until someone clicks Search.
# This asks each app to search its Wanted lists on a schedule.
#
# MODE=missing  -> aired/released monitored items with no file
# MODE=cutoff   -> monitored items whose file is below the profile's cutoff
import json, os, sys, urllib.request

MODE = os.environ["MODE"]
APPS = {
    "sonarr": ("http://sonarr.default.svc.cluster.local:8989/api/v3", os.environ["SONARR_API_KEY"], {
        "missing": {"name": "MissingEpisodeSearch", "monitored": True},
        "cutoff": {"name": "CutoffUnmetEpisodeSearch", "monitored": True},
    }, "wanted/{}?pageSize=1&monitored=true"),
    "radarr": ("http://radarr.default.svc.cluster.local:7878/api/v3", os.environ["RADARR_API_KEY"], {
        "missing": {"name": "MissingMoviesSearch", "filterKey": "monitored", "filterValue": "true"},
        "cutoff": {"name": "CutoffUnmetMoviesSearch", "filterKey": "monitored", "filterValue": "true"},
    }, "wanted/{}?pageSize=1&monitored=true"),
}


def call(base, key, path, body=None):
    req = urllib.request.Request(f"{base}/{path}", method="POST" if body else "GET",
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"X-Api-Key": key, "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))


failed = False
for app, (base, key, commands, wanted) in APPS.items():
    try:
        count = call(base, key, wanted.format(MODE))["totalRecords"]
        if count == 0:
            print(f"{app}: nothing {MODE}, skipping")
            continue
        cmd = call(base, key, "command", commands[MODE])
        print(f"{app}: {count} {MODE} item(s) -> {cmd['name']} queued (command {cmd['id']})")
    except Exception as e:  # keep going so one app's outage doesn't skip the other
        print(f"{app}: {MODE} search failed: {e}", file=sys.stderr)
        failed = True
sys.exit(1 if failed else 0)
