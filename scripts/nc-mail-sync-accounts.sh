#!/usr/bin/env bash
# Sync Nextcloud Mail accounts from config/mail-accounts.json
# Usage: nc-mail-sync-accounts.sh [--check|--apply]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG="${MAIL_ACCOUNTS_JSON:-${OPENCLAW_DIR}/config/mail-accounts.json}"
STATE="${OPENCLAW_DIR}/state/mail-account-ids.json"
MODE="apply"
[[ "${1:-}" == "--check" ]] && MODE="check"
[[ "${1:-}" == "--apply" ]] && MODE="apply"

[[ -f "$CONFIG" ]] || { echo "Gate X2: FAIL — missing $CONFIG" >&2; exit 1; }

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true" -H "Content-Type: application/json")

export CONFIG STATE OPENCLAW_DIR MODE NEXTCLOUD_URL

python3 <<'PY'
import json, os, subprocess, sys, urllib.request
from pathlib import Path

config = json.loads(Path(os.environ["CONFIG"]).read_text())
openclaw = Path(os.environ["OPENCLAW_DIR"])
state_path = Path(os.environ["STATE"])
mode = os.environ["MODE"]
nc = os.environ["NEXTCLOUD_URL"]
auth_user = os.environ.get("NEXTCLOUD_USER", "")
auth_pass = os.environ.get("NEXTCLOUD_PASS", "")

import base64
auth_hdr = base64.b64encode(f"{auth_user}:{auth_pass}".encode()).decode()

def nc_request(method, path, body=None, headers_extra=None, retries=12):
    import time
    import urllib.error
    hdrs = {
        "Authorization": f"Basic {auth_hdr}",
        "Accept": "application/json",
        "OCS-APIREQUEST": "true",
    }
    if body is not None:
        hdrs["Content-Type"] = "application/json"
    if headers_extra:
        hdrs.update(headers_extra)
    data = json.dumps(body).encode() if body is not None else None
    delay = 1
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(f"{nc}{path}", data=data, headers=hdrs, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.status, json.loads(resp.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (503, 502, 409) and attempt + 1 < retries:
                time.sleep(min(delay, 6))
                delay += 1
                continue
            raise
    if last_err:
        raise last_err
    raise RuntimeError("nc_request failed")

def list_accounts():
    st, data = nc_request("GET", "/index.php/apps/mail/api/accounts")
    if isinstance(data, list):
        return data
    return data.get("accounts") or []

def find_by_email(accounts, email):
    em = email.lower()
    matches = [a for a in accounts if em in (a.get("emailAddress") or "").lower()]
    return matches

def read_secret(rel):
    p = openclaw / ".env.d" / rel
    if not p.is_file():
        raise FileNotFoundError(p)
    return p.read_text().replace(" ", "").strip()

def build_payload(acct, app_pass):
    email = acct["email"]
    payload = {
        "accountName": acct["account_name"],
        "emailAddress": email,
        "imapHost": "imap.gmail.com",
        "imapPort": 993,
        "imapSslMode": "ssl",
        "imapUser": email,
        "imapPassword": app_pass,
        "authMethod": "password",
    }
    if acct.get("smtp", True):
        payload.update({
            "smtpHost": "smtp.gmail.com",
            "smtpPort": 587,
            "smtpSslMode": "starttls",
            "smtpUser": email,
            "smtpPassword": app_pass,
        })
    return payload

accounts_api = list_accounts()
out = {"accounts": {}, "updated_at": __import__("datetime").datetime.utcnow().isoformat() + "Z"}
fail = False

for acct in config.get("accounts", []):
    role = acct["role"]
    email = acct["email"]
    matches = find_by_email(accounts_api, email)
    if len(matches) > 1:
        print(f"Gate E1-DEDUP: FAIL — duplicate accounts for {email}", file=sys.stderr)
        fail = True
        continue
    if matches:
        aid = str(matches[0]["id"])
        print(f"Gate E1-{role.upper()}: PASS — {email} id={aid}")
        out["accounts"][role] = {"id": aid, "email": email}
        continue
    if mode == "check":
        print(f"Gate E1-{role.upper()}: FAIL — missing {email}", file=sys.stderr)
        fail = True
        continue
    try:
        app_pass = read_secret(acct["secret_file"])
    except FileNotFoundError as e:
        print(f"Gate E1-{role.upper()}: FAIL — secret {e}", file=sys.stderr)
        fail = True
        continue
    payload = build_payload(acct, app_pass)
    st, created = nc_request("POST", "/index.php/apps/mail/api/accounts", payload)
    if st not in (200, 201):
        print(f"Gate E1-{role.upper()}: FAIL create HTTP {st} {created}", file=sys.stderr)
        fail = True
        continue
    aid = str(created.get("id") or created.get("data", {}).get("id") or "?")
    print(f"Gate E1-{role.upper()}: PASS — created id={aid}")
    out["accounts"][role] = {"id": aid, "email": email}
    accounts_api = list_accounts()

state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(out, indent=2))
print(f"Gate MAIL-STATE: PASS — wrote {state_path}")

if mode == "apply" and not fail:
    for role, info in out["accounts"].items():
        aid = info["id"]
        if aid.isdigit() and subprocess.run(["docker", "ps", "--format", "{{.Names}}"], capture_output=True, text=True).stdout.find("cloud_app") >= 0:
            try:
                r = subprocess.run(
                    ["docker", "exec", "cloud_app", "php", "occ", "mail:account:sync", aid],
                    capture_output=True, text=True, timeout=180,
                )
            except subprocess.TimeoutExpired:
                print(f"Gate E1-SYNC: WARN — sync id={aid} timed out after 180s", file=sys.stderr)
            else:
                if r.returncode == 0:
                    print(f"Gate E1-SYNC: PASS — synced id={aid} ({role})")
                else:
                    print(f"Gate E1-SYNC: WARN — sync id={aid} rc={r.returncode}", file=sys.stderr)

env_lines = []
for role, info in out["accounts"].items():
    key = {"family": "FAMILY", "ops": "OPS", "work": "WORK"}[role]
    env_lines.append(f"{key}_GMAIL_ADDRESS={info['email']}")
    env_lines.append(f"{key}_MAIL_ACCOUNT_ID={info['id']}")
print("\n# Add to ~/.openclaw/.env:")
for line in env_lines:
    print(line)

sys.exit(1 if fail else 0)
PY
