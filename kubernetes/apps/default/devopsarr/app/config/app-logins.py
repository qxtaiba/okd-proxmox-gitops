"""Reconcile web-UI logins to the svc-grappleberry-<app> convention.

The devopsarr providers can't manage *arr host settings yet (current apps
require AllowedHosts, which their model lacks), so this job reads each app's
own settings, changes only the login, and sends everything else back as the
app reported it. Idempotent: an app already in the desired state is left
untouched. Passwords come from the apps' 1Password items.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

failed = False


def call(url, method="GET", headers=None, body=None, form=None):
    data = None
    h = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form, doseq=True).encode()
    with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=h), timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw.strip().startswith((b"{", b"[")) else raw.decode()


def step(name, fn):
    global failed
    try:
        print(name + ": " + fn(), flush=True)
    except Exception as e:  # keep going so one app can't block the others
        failed = True
        print(name + ": FAILED " + str(e)[:300], flush=True)


def arr(app, port, api):
    def run():
        base = "http://%s.default.svc.cluster.local:%d/api/%s" % (app, port, api)
        h = {"X-Api-Key": os.environ[app.upper() + "_API_KEY"]}
        want = "svc-grappleberry-" + app
        cfg = call(base + "/config/host", headers=h)
        if cfg.get("username") == want and cfg.get("authenticationMethod") == "forms":
            return "login already " + want
        pw = os.environ[app.upper() + "_PASSWORD"]
        cfg.update({"username": want, "password": pw, "passwordConfirmation": pw,
                    "authenticationMethod": "forms", "authenticationRequired": "enabled"})
        call(base + "/config/host/%d" % cfg["id"], method="PUT", headers=h, body=cfg)
        got = call(base + "/config/host", headers=h).get("username")
        if got != want:
            raise RuntimeError("username is %r after update" % got)
        return "login renamed to " + want
    return run


def sabnzbd():
    base = "http://sabnzbd.default.svc.cluster.local:8080/api"
    key = os.environ["SABNZBD_API_KEY"]
    want = "svc-grappleberry-sabnzbd"
    q = lambda **p: call(base + "?" + urllib.parse.urlencode(dict(p, apikey=key, output="json")))
    have = q(mode="get_config", section="misc", keyword="username")["config"]["misc"]["username"]
    if have == want:
        return "login already " + want
    got = q(mode="set_config", section="misc", keyword="username", value=want)["config"]["misc"]["username"]
    if got != want:
        raise RuntimeError("username is %r after update" % got)
    return "login renamed to " + want + " (password unchanged)"


def bazarr():
    base = "http://bazarr.default.svc.cluster.local:6767/api"
    h = {"X-API-KEY": os.environ["BAZARR_API_KEY"]}
    want = "svc-grappleberry-bazarr"
    auth = call(base + "/system/settings", headers=h).get("auth", {})
    if auth.get("type") == "form" and auth.get("username") == want:
        return "login already " + want
    # Bazarr hashes the password itself when it is posted in plain text.
    call(base + "/system/settings", method="POST", headers=h, form={
        "settings-auth-type": "form",
        "settings-auth-username": want,
        "settings-auth-password": os.environ["BAZARR_PASSWORD"],
    })
    auth = call(base + "/system/settings", headers=h).get("auth", {})
    if auth.get("type") != "form" or auth.get("username") != want:
        raise RuntimeError("auth is %r after update" % {k: auth.get(k) for k in ("type", "username")})
    return "form login enabled as " + want


step("sonarr", arr("sonarr", 8989, "v3"))
step("radarr", arr("radarr", 7878, "v3"))
step("prowlarr", arr("prowlarr", 9696, "v1"))
step("sabnzbd", sabnzbd)
step("bazarr", bazarr)
sys.exit(1 if failed else 0)
