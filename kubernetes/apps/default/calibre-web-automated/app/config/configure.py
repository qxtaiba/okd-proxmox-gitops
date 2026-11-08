"""Declarative CWA settings, applied before each start. Idempotent.

- Login: CWA seeds admin/admin123 and has no setting for it, so the admin
  row in app.db is rewritten to the 1Password svc-grappleberry credentials.
- Ingest (cwa.db): convert to PDF for Notability keeping the EPUB, fetch
  metadata on import (Hardcover first) so files aren't named after the
  release, and rank PDF first when duplicates are compared.
"""
import json
import os
import sqlite3
import sys

from werkzeug.security import check_password_hash, generate_password_hash

DB = "/config/app.db"
CWA_DB = "/config/cwa.db"
ROLE_ADMIN = 1

FORMAT_PRIORITY = {"PDF": 100, "EPUB": 90, "KEPUB": 85, "AZW3": 80, "MOBI": 75, "AZW": 70,
                   "DJVU": 50, "TXT": 40, "CBZ": 35, "CBR": 35, "FB2": 30, "HTML": 20,
                   "RTF": 15, "DOC": 10, "DOCX": 10}
CWA_SETTINGS = {
    "auto_convert": 1,
    "auto_convert_target_format": "pdf",
    "auto_convert_retained_formats": "epub",
    "auto_metadata_fetch_enabled": 1,
    "metadata_provider_hierarchy": json.dumps(["hardcover", "kobo", "amazon", "google", "ibdb", "dnb"]),
    "hardcover_auto_fetch_enabled": 1,
    "duplicate_format_priority": json.dumps(FORMAT_PRIORITY),
}


def apply_cwa_settings():
    if not os.path.exists(CWA_DB):
        print("no cwa.db yet; settings are applied on the next start")
        return
    con = sqlite3.connect(CWA_DB)
    cols = ", ".join(CWA_SETTINGS)
    have = con.execute("SELECT %s FROM cwa_settings" % cols).fetchone()
    want = tuple(CWA_SETTINGS.values())
    if have == want:
        print("cwa settings already applied")
        return
    con.execute("UPDATE cwa_settings SET " + ", ".join(k + " = ?" for k in CWA_SETTINGS), want)
    con.commit()
    print("cwa settings applied")


apply_cwa_settings()

if not os.path.exists(DB):
    print("no app.db yet; CWA creates it on first start, login is set on the next")
    sys.exit(0)

want = os.environ["CWA_USERNAME"]
pw = os.environ["CWA_PASSWORD"]
con = sqlite3.connect(DB)
row = con.execute(
    "SELECT id, name, password FROM user WHERE name IN (?, 'admin') AND role & ? "
    "ORDER BY name = ? DESC LIMIT 1",
    (want, ROLE_ADMIN, want),
).fetchone()
if row is None:
    print("no admin user to manage")
    sys.exit(0)

uid, name, pw_hash = row
if name == want and check_password_hash(pw_hash, pw):
    print("login already " + want)
    sys.exit(0)

con.execute("UPDATE user SET name = ?, password = ? WHERE id = ?", (want, generate_password_hash(pw), uid))
con.commit()
print("login set to " + want)
