#!/usr/bin/env bash
# Add family Gmail to Nextcloud Mail (read-only IMAP). Password in secret file only.
# Usage: nc-mail-add-gmail.sh
# Env: FAMILY_GMAIL_ADDRESS, FAMILY_GMAIL_SECRET_FILE (default: ~/.openclaw/.env.d/family-gmail-mail.secret)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

EMAIL="${FAMILY_GMAIL_ADDRESS:?FAMILY_GMAIL_ADDRESS not set}"
SECRET_FILE="${FAMILY_GMAIL_SECRET_FILE:-${OPENCLAW_DIR:-$HOME/.openclaw}/.env.d/family-gmail-mail.secret}"
ACCOUNT_NAME="${FAMILY_MAIL_ACCOUNT_NAME:-Family Gmail}"

[[ -f "$SECRET_FILE" ]] || { echo "Missing $SECRET_FILE" >&2; exit 1; }
APP_PASS="$(tr -d ' \n' < "$SECRET_FILE")"

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true" -H "Content-Type: application/json")

EXISTING=$(curl -sS "${AUTH[@]}" "${HDRS[@]}" \
  "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" \
  | python3 -c 'import sys,json,os
d=json.load(sys.stdin)
a=d if isinstance(d,list) else d.get("accounts",[]) or []
needle=os.environ.get("EMAIL","").lower()
print(next((str(x["id"]) for x in a if needle in (x.get("emailAddress") or "").lower()), ""))' EMAIL="$EMAIL")

if [[ -n "$EXISTING" ]]; then
  echo "Gate E1: PASS — family account id=$EXISTING"
  export FAMILY_MAIL_ACCOUNT_ID="$EXISTING"
  exit 0
fi

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
