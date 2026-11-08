"""Set CWA's admin login to the 1Password svc-grappleberry credentials.

CWA seeds admin/admin123 on first start and has no setting for it, so this
runs before each start and rewrites the admin row in app.db. Idempotent.
"""
import os
import sqlite3
import sys

from werkzeug.security import check_password_hash, generate_password_hash

DB = "/config/app.db"
ROLE_ADMIN = 1

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
