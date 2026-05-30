#!/usr/bin/env bash
# Add family Gmail to Nextcloud Mail (read-only IMAP). Password in secret file only.
# Usage: nc-mail-add-gmail.sh
# Env: FAMILY_GMAIL_ADDRESS, FAMILY_MAIL_ACCOUNT_ID, FAMILY_GMAIL_SECRET_FILE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
EMAIL="${FAMILY_GMAIL_ADDRESS:-}"
SECRET_FILE="${FAMILY_GMAIL_SECRET_FILE:-${OPENCLAW_DIR}/.env.d/family-gmail-mail.secret}"
ACCOUNT_NAME="${FAMILY_MAIL_ACCOUNT_NAME:-Family Gmail}"

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true" -H "Content-Type: application/json")

find_existing() {
  curl -sS "${AUTH[@]}" "${HDRS[@]}" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" \
    | python3 -c 'import sys,json,os
d=json.load(sys.stdin)
a=d if isinstance(d,list) else d.get("accounts",[]) or []
aid=os.environ.get("ACCOUNT_ID","").strip()
needle=os.environ.get("EMAIL","").lower()
if aid:
    for x in a:
        if str(x.get("id")) == aid:
            print(aid); raise SystemExit(0)
if needle:
    for x in a:
        if needle in (x.get("emailAddress") or "").lower():
            print(x["id"]); raise SystemExit(0)
for x in a:
    em=(x.get("emailAddress") or "").lower()
    if em.endswith("@gmail.com"):
        print(x["id"]); break' ACCOUNT_ID="${FAMILY_MAIL_ACCOUNT_ID:-}" EMAIL="$EMAIL"
}

EXISTING="$(find_existing || true)"
if [[ -n "$EXISTING" ]]; then
  echo "Gate E1: PASS — family account id=$EXISTING"
  exit 0
fi

[[ -n "$EMAIL" ]] || { echo "Gate E1: FAIL — set FAMILY_GMAIL_ADDRESS to add account" >&2; exit 1; }
[[ -f "$SECRET_FILE" ]] || { echo "Gate E1: FAIL — missing $SECRET_FILE" >&2; exit 1; }
APP_PASS="$(tr -d ' \n' < "$SECRET_FILE")"

PAYLOAD=$(python3 - "$EMAIL" "$APP_PASS" "$ACCOUNT_NAME" <<'PY'
import json, sys
email, pw, name = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "accountName": name,
    "emailAddress": email,
    "imapHost": "imap.gmail.com",
    "imapPort": 993,
    "imapSslMode": "ssl",
    "imapUser": email,
    "imapPassword": pw,
    "smtpHost": "smtp.gmail.com",
    "smtpPort": 587,
    "smtpSslMode": "starttls",
    "smtpUser": email,
    "smtpPassword": pw,
    "authMethod": "password",
}))
PY
)

HTTP=$(curl -sS -o /tmp/nc-mail-add.json -w '%{http_code}' "${AUTH[@]}" "${HDRS[@]}" \
  -X POST "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" -d "$PAYLOAD")

if [[ "$HTTP" =~ ^2 ]]; then
  ID=$(python3 -c 'import json; print(json.load(open("/tmp/nc-mail-add.json")).get("id",""))' 2>/dev/null || echo "?")
  echo "Gate E1: PASS — created id=$ID"
  exit 0
fi
echo "Gate E1: FAIL HTTP $HTTP" >&2
cat /tmp/nc-mail-add.json >&2
exit 1
