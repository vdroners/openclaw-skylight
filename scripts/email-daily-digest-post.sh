#!/usr/bin/env bash
# Email daily digest — ops+work unread summary posted to Talk (excludes family account).
# Usage: email-daily-digest-post.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

: "${NEXTCLOUD_URL:?missing}"
: "${NEXTCLOUD_USER:?missing}"
: "${NEXTCLOUD_PASS:?missing}"
ROOM="${EMAIL_DIGEST_OPS_ROOM:-${EMAIL_DIGEST_WORK_ROOM:-${EMAIL_DIGEST_TALK_ROOM:-}}}"
WINDOW_SEC="${EMAIL_DIGEST_WINDOW_SEC:-86400}"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true")

resolve_account() {
  local role="$1"
  local env_id=""
  case "$role" in
    ops) env_id="${OPS_MAIL_ACCOUNT_ID:-}" ;;
    work) env_id="${WORK_MAIL_ACCOUNT_ID:-}" ;;
  esac
  if [[ -n "$env_id" ]]; then
    echo "$env_id"
    return
  fi
  local email=""
  case "$role" in
    ops) email="${OPS_GMAIL_ADDRESS:-}" ;;
    work) email="${WORK_GMAIL_ADDRESS:-}" ;;
  esac
  curl -sS "${AUTH[@]}" "${HDRS[@]}" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" \
    | EMAIL="$email" python3 -c 'import sys,json,os
d=json.load(sys.stdin)
a=d if isinstance(d,list) else d.get("accounts",[]) or []
needle=os.environ.get("EMAIL","").lower()
for x in a:
    if needle and needle in (x.get("emailAddress") or "").lower():
        print(x["id"]); break'
}

fetch_inbox() {
  local account_id="$1"
  curl -sS "${AUTH[@]}" "${HDRS[@]}" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/mailboxes?accountId=$account_id" \
    | python3 -c 'import sys,json
d=json.load(sys.stdin)
mbs=d.get("mailboxes",[]) if isinstance(d,dict) else (d if isinstance(d,list) else [])
ids=[b.get("databaseId") for b in mbs if (b.get("specialRole")=="inbox" or b.get("name","").upper()=="INBOX")]
print(ids[0] if ids else "")'
}

SECTIONS=""
for role in ops work; do
  ACCT=$(resolve_account "$role" || true)
  [[ -n "$ACCT" ]] || continue
  INBOX=$(fetch_inbox "$ACCT" || true)
  [[ -n "$INBOX" ]] || continue
  MSGS_FILE=$(mktemp)
  MSG_HTTP=409
  for _attempt in $(seq 1 12); do
    MSG_HTTP=$(curl -sS "${AUTH[@]}" "${HDRS[@]}" \
      "$NEXTCLOUD_URL/index.php/apps/mail/api/messages?mailboxId=${INBOX}&filter=unread&limit=50" \
      -o "$MSGS_FILE" -w '%{http_code}' || echo 000)
    [[ "$MSG_HTTP" != "409" ]] && break
    sleep "$_attempt"
  done
  SECTION=$(python3 - "$MSGS_FILE" "$WINDOW_SEC" "$role" <<'PY'
import json, sys, time
from datetime import datetime
msgs_path, window, role = sys.argv[1], int(sys.argv[2]), sys.argv[3]
cutoff = time.time() - window
try:
    data = json.load(open(msgs_path))
except Exception:
    data = []
def normalize_messages(data):
    if isinstance(data, list):
        return data
    if not isinstance(data, dict):
        return []
    for key in ("messages", "data"):
        val = data.get(key)
        if isinstance(val, list):
            return val
    return []

msgs = normalize_messages(data)
def sender_from(frm):
    if frm is None:
        return "?"
    if isinstance(frm, str):
        return frm or "?"
    if isinstance(frm, dict):
        return frm.get("label") or frm.get("email") or "?"
    if isinstance(frm, list):
        if not frm:
            return "?"
        first = frm[0]
        if isinstance(first, str):
            return first
        if isinstance(first, dict):
            return first.get("label") or first.get("email") or "?"
    return "?"

picks = []
for m in msgs:
    if not isinstance(m, dict):
        continue
    ts = m.get("dateInt") or 0
    if ts and ts < cutoff:
        continue
    sender = sender_from(m.get("from"))
    picks.append(f"- {sender}: {(m.get('subject') or '(no subject)')[:80]}")
lines = [f"## {role.upper()} ({len(picks)} unread)"]
lines.extend(picks[:8] if picks else ["(none)"])
print("\n".join(lines))
PY
)
  rm -f "$MSGS_FILE"
  SECTIONS+="${SECTION}"$'\n\n'
done

if [[ -z "$SECTIONS" ]]; then
  BODY="Email digest: no ops/work mail accounts configured."
else
  BODY="Email digest (ops+work, last $((WINDOW_SEC / 3600))h)"$'\n\n'"${SECTIONS}"
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "DIGEST_DRY_RUN accounts=ops,work"
  printf '%s\n' "$BODY"
  exit 0
fi

[[ -n "$ROOM" ]] || { echo "EMAIL_DIGEST_OPS_ROOM (or EMAIL_DIGEST_TALK_ROOM) not set" >&2; exit 1; }
bash "${SCRIPT_DIR}/talk-post.sh" "$BODY" "$ROOM"
echo "DIGEST_POSTED room=${ROOM} accounts=ops,work"
