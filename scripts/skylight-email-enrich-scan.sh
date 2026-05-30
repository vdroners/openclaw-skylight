#!/usr/bin/env bash
# Match family Gmail (Inbox + Sent) to calendar enrich candidates (subject-first, fast path).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/nc-http-retry.sh"

LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
AUDIT=$(ls -1t "${LOG_DIR}"/skylight-household-audit-*.json 2>/dev/null | head -1)
[[ -n "$AUDIT" ]] || { echo "No audit JSON found" >&2; exit 1; }

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true")

FAMILY_EMAIL="${FAMILY_GMAIL_ADDRESS:-}"
MAIL_ACCOUNT="${FAMILY_MAIL_ACCOUNT_ID:-}"

nc_wait_mail_api || { echo "Gate E2: FAIL — mail API not ready" >&2; exit 1; }

if [[ -z "$MAIL_ACCOUNT" && -n "$FAMILY_EMAIL" ]]; then
  MAIL_ACCOUNT=$(nc_curl_retry "${AUTH[@]}" "${HDRS[@]}" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" \
    | FAMILY_GMAIL_ADDRESS="$FAMILY_EMAIL" python3 -c 'import sys,json,os
d=json.load(sys.stdin)
a=d if isinstance(d,list) else d.get("accounts",[]) or []
needle=os.environ.get("FAMILY_GMAIL_ADDRESS","").lower()
for x in a:
    if needle in (x.get("emailAddress") or "").lower():
        print(x["id"]); break')
fi

if [[ -z "$MAIL_ACCOUNT" ]]; then
  echo "Gate E2: FAIL — set FAMILY_MAIL_ACCOUNT_ID and FAMILY_GMAIL_ADDRESS for family enrich" >&2
  exit 1
fi

MAILBOXES_FILE=$(mktemp)
INBOX_PROBE=$(mktemp)
trap 'rm -f "$MAILBOXES_FILE" "$INBOX_PROBE"' EXIT

nc_curl_retry "${AUTH[@]}" "${HDRS[@]}" \
  "$NEXTCLOUD_URL/index.php/apps/mail/api/mailboxes?accountId=$MAIL_ACCOUNT" \
  > "$MAILBOXES_FILE"

# Probe inbox — skip background sync when messages already present
INBOX_MB=$(python3 - "$MAILBOXES_FILE" <<'PY'
import json, sys
from pathlib import Path
mailboxes = json.loads(Path(sys.argv[1]).read_text())
for mb in mailboxes.get("mailboxes", mailboxes if isinstance(mailboxes, list) else []):
    role = (mb.get("specialRole") or mb.get("name") or "").lower()
    name = (mb.get("name") or "").upper()
    if role == "inbox" or name == "INBOX":
        print(mb.get("databaseId") or mb.get("id") or "")
        break
PY
)

NEED_SYNC=1
if [[ -n "$INBOX_MB" ]]; then
  nc_curl_retry "${AUTH[@]}" "${HDRS[@]}" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/messages?mailboxId=$INBOX_MB&limit=5" \
    > "$INBOX_PROBE"
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); m=d if isinstance(d,list) else d.get("messages") or d.get("data") or []; sys.exit(0 if m else 1)' "$INBOX_PROBE" 2>/dev/null; then
    NEED_SYNC=0
  fi
fi

if [[ "$NEED_SYNC" -eq 1 ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'cloud_app'; then
  (timeout 15 docker exec cloud_app php occ mail:account:sync "$MAIL_ACCOUNT" 2>/dev/null || true) &
fi

export AUDIT MAILBOXES_FILE MAIL_ACCOUNT NEXTCLOUD_URL NEXTCLOUD_USER NEXTCLOUD_PASS HOUSEHOLD_MODEL_JSON

python3 <<'PY'
import json, os, re, sys, time, urllib.request
from pathlib import Path

audit_path = Path(os.environ["AUDIT"])
audit = json.loads(audit_path.read_text())
nc = os.environ["NEXTCLOUD_URL"]
auth_user = os.environ["NEXTCLOUD_USER"]
auth_pass = os.environ["NEXTCLOUD_PASS"]
account_id = os.environ["MAIL_ACCOUNT"]
mailboxes = json.loads(Path(os.environ["MAILBOXES_FILE"]).read_text())

import base64
auth_hdr = base64.b64encode(f"{auth_user}:{auth_pass}".encode()).decode()

MAX_MSGS = 30
BODY_TIMEOUT = 10
model_path = os.environ.get("HOUSEHOLD_MODEL_JSON", "")
model_keywords = []
if model_path and Path(model_path).is_file():
    model_keywords = json.loads(Path(model_path).read_text()).get("email_keywords") or []
keywords = [k.lower() for k in (model_keywords or [
    "lesson", "practice", "game", "tutor", "conference", "appointment", "birthday"
])]

cal_titles = [(p.get("summary") or "").lower() for p in audit.get("enrich_calendar", [])]
cal_words = set()
for t in cal_titles:
    for w in t.split():
        if len(w) > 3:
            cal_words.add(w)

def nc_get(path, timeout=30, retries=12):
    import urllib.error
    delay = 1
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(
            f"{nc}{path}",
            headers={"Authorization": f"Basic {auth_hdr}", "Accept": "application/json", "OCS-APIREQUEST": "true"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (503, 502, 409) and attempt + 1 < retries:
                time.sleep(min(delay, 6))
                delay += 1
                continue
            raise
    if last_err:
        raise last_err
    raise RuntimeError("nc_get failed")

def parse_messages(raw):
    if isinstance(raw, list):
        return raw
    if raw.get("status") == "fail":
        return []
    return raw.get("messages") or raw.get("data") or []

def subject_matches(subj_l):
    if any(k in subj_l for k in keywords):
        return True
    return any(w in subj_l for w in cal_words)

def strip_html(text):
    text = re.sub(r"<(script|style)[^>]*>.*?</\\1>", " ", text, flags=re.I | re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\\s+", " ", text).strip()

def extract_location(subj, body):
    text = strip_html(subj + " " + body)
    for pat in [
        r"(\d+[^,\n]{5,80}(?:Street|St|Avenue|Ave|Road|Rd|Blvd)[^,\n]{0,40})",
        r"(\d+[^,\n]{5,80},[^,\n]{3,40})",
    ]:
        m2 = re.search(pat, text, re.I)
        if not m2:
            continue
        loc = m2.group(1).strip()
        if any(x in loc for x in ("{", "}", "display:", "text-decoration", "@media")):
            continue
        if len(loc) > 120:
            continue
        return loc
    return None

mb_ids = []
for mb in mailboxes.get("mailboxes", mailboxes if isinstance(mailboxes, list) else []):
    role = (mb.get("specialRole") or mb.get("name") or "").lower()
    name = (mb.get("name") or "").upper()
    if role in ("inbox", "sent", "sent items") or name in ("INBOX", "SENT", "[GMAIL]/SENT"):
        mb_ids.append(mb.get("databaseId") or mb.get("id"))

hints = []
seen_subjects = set()
for mb_id in mb_ids[:2]:
    if not mb_id:
        continue
    try:
        msgs = parse_messages(nc_get(f"/index.php/apps/mail/api/messages?mailboxId={mb_id}&limit={MAX_MSGS}"))
    except Exception:
        msgs = []
    for m in msgs:
        subj = (m.get("subject") or "")
        subj_l = subj.lower()
        if subj_l in seen_subjects:
            continue
        if not subject_matches(subj_l):
            continue
        seen_subjects.add(subj_l)
        mid = m.get("databaseId") or m.get("id")
        body = ""
        if mid:
            try:
                b = nc_get(f"/index.php/apps/mail/api/messages/{mid}/body", timeout=BODY_TIMEOUT)
                body = (b.get("body") or b.get("content") or "")[:4000]
            except Exception:
                pass
        loc = extract_location(subj, body)
        hints.append({
            "message_id": mid,
            "subject": subj,
            "location_hint": loc,
            "body_preview": body[:200],
        })

matches = 0
for prop in audit.get("enrich_calendar", []):
    ps = (prop.get("summary") or "").lower()
    for h in hints:
        hs = (h.get("subject") or "").lower()
        if any(w in hs for w in ps.split() if len(w) > 3):
            if h.get("location_hint") and prop.get("fields", {}).get("location") is None:
                prop.setdefault("fields", {})["location"] = h["location_hint"]
                prop["source"] = "email"
                prop["confidence"] = 0.85
                matches += 1
            break

audit["email_hints"] = hints
audit_path.write_text(json.dumps(audit, indent=2))
print(f"Gate E2: email_hints={len(hints)} calendar_matches={matches} account={account_id}")
print(f"Updated {audit_path}")
sys.exit(0 if hints else 1)
PY
