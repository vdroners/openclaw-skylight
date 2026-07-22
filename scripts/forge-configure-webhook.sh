#!/usr/bin/env bash
# Configure 3DPrintForge outgoing webhook for Alfred Talk relay.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-forge-env.sh"

WH_SECRET="${FORGE_WEBHOOK_SECRET:-}"
if [[ -z "$WH_SECRET" && -f "${FORGE_WEBHOOK_SECRET_FILE/#\~/$HOME}" ]]; then
  WH_SECRET="$(cat "${FORGE_WEBHOOK_SECRET_FILE/#\~/$HOME}")"
fi
[[ -n "$WH_SECRET" ]] || { echo "missing webhook secret" >&2; exit 1; }

PUBLIC_URL="${FORGE_PUBLIC_WEBHOOK_URL:-https://alfred-vdroners.ddns.net/forge-webhook}"
FORGE_URL="${FORGE_API_URL:-https://127.0.0.1:3040}"
ADMIN_PASS_FILE="${FORGE_ADMIN_PASS_FILE:-/media/4TB/3dprintforge/.admin_pass}"
[[ -f "$ADMIN_PASS_FILE" ]] || { echo "missing $ADMIN_PASS_FILE" >&2; exit 1; }
ADMIN_PASS="$(cat "$ADMIN_PASS_FILE")"
COOKIE="$(mktemp)"
trap 'rm -f "$COOKIE"' EXIT

curl -sk -c "$COOKIE" -b "$COOKIE" -X POST "${FORGE_URL}/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}" | grep -q '"ok":true' \
  || { echo "forge login failed" >&2; exit 1; }

python3 - "$SCRIPT_DIR" "$PUBLIC_URL" "$WH_SECRET" "$COOKIE" "$FORGE_URL" <<'PY'
import json, os, ssl, sys, urllib.error, urllib.request

script_dir, public_url, secret, cookie_file, base = sys.argv[1:6]
events = [
    "print_started", "print_finished", "print_failed", "print_cancelled",
    "printer_error", "forge_slicer_disconnected", "protection_alert",
]

ctx = ssl.create_default_context()
if "127.0.0.1" in base or "localhost" in base:
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE


def req(method, path, body=None):
    url = base.rstrip("/") + path
    data = None
    hdrs = {"Accept": "application/json"}
    with open(cookie_file) as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 7 and parts[5]:
                hdrs["Cookie"] = f"{parts[5]}={parts[6]}"
                break
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(r, timeout=20, context=ctx) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"raw": raw}

c, rows = req("GET", "/api/webhooks")
if c != 200:
    print(f"GET webhooks failed HTTP {c}: {rows}", file=sys.stderr)
    sys.exit(1)
webhooks = rows if isinstance(rows, list) else rows.get("webhooks") or []
wh_id = None
for w in webhooks:
    if str(w.get("name")) == "alfred-talk":
        wh_id = w.get("id")
        break

body_create = {"name": "alfred-talk", "url": public_url}
c2, resp = req("POST", "/api/webhooks", body_create)
if c2 not in (200, 201):
    # may already exist from partial run
    c, rows = req("GET", "/api/webhooks")
    webhooks = rows if isinstance(rows, list) else rows.get("webhooks") or []
    wh_id = next((w.get("id") for w in webhooks if str(w.get("name")) == "alfred-talk"), None)
    if not wh_id:
        print(f"webhook create failed HTTP {c2}: {resp}", file=sys.stderr)
        sys.exit(1)
else:
    wh_id = resp.get("id")

body = {
    "name": "alfred-talk",
    "url": public_url,
    "secret": secret,
    "template": "generic",
    "events": events,
    "active": 1,
    "retry_count": 3,
    "retry_delay_s": 30,
}

if wh_id:
    c2, resp = req("PUT", f"/api/webhooks/{wh_id}", body)
else:
    c2, resp = 500, {"error": "no webhook id"}

if c2 not in (200, 201):
    print(f"webhook configure failed HTTP {c2}: {resp}", file=sys.stderr)
    sys.exit(1)
wid = wh_id or resp.get("id")
print(f"configured alfred-talk webhook id={wid} url={public_url}")
if wid:
    c3, tresp = req("POST", f"/api/webhooks/{wid}/test", {})
    print(f"test webhook HTTP {c3}: {tresp}")
PY
