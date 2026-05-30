#!/usr/bin/env bash
# Scan ops+work inboxes for urgent unread emails. Emits one JSON line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

: "${NEXTCLOUD_URL:?missing}"
: "${NEXTCLOUD_USER:?missing}"
: "${NEXTCLOUD_PASS:?missing}"

WINDOW_SEC="${URGENT_WINDOW_SEC:-900}"
ROLES="${URGENT_SCAN_ACCOUNTS:-ops,work}"

AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true")

export NEXTCLOUD_URL WINDOW_SEC ROLES OPS_MAIL_ACCOUNT_ID WORK_MAIL_ACCOUNT_ID OPS_GMAIL_ADDRESS WORK_GMAIL_ADDRESS

python3 <<'PY'
import json, os, re, sys, time, urllib.request

nc = os.environ["NEXTCLOUD_URL"]
window = int(os.environ.get("URGENT_WINDOW_SEC") or os.environ.get("WINDOW_SEC") or 900)
roles = [r.strip() for r in os.environ.get("URGENT_SCAN_ACCOUNTS", "ops,work").split(",") if r.strip()]
auth_user = os.environ["NEXTCLOUD_USER"]
auth_pass = os.environ["NEXTCLOUD_PASS"]
import base64
auth_hdr = base64.b64encode(f"{auth_user}:{auth_pass}".encode()).decode()

def nc_get(path, retries=12):
    import urllib.error
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(
            f"{nc}{path}",
            headers={"Authorization": f"Basic {auth_hdr}", "Accept": "application/json", "OCS-APIREQUEST": "true"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 409 and attempt + 1 < retries:
                time.sleep(min(3.0, 0.5 * (attempt + 1)))
                continue
            if e.code == 409:
                return {"status": "fail", "data": {"message": "mailbox locked after retries", "type": "MailboxLockedException"}}
            raise
    if last_err:
        raise last_err
    raise RuntimeError("nc_get failed")

accounts = nc_get("/index.php/apps/mail/api/accounts")
accounts = accounts if isinstance(accounts, list) else accounts.get("accounts") or []

def account_id(role):
    env_key = {"ops": "OPS_MAIL_ACCOUNT_ID", "work": "WORK_MAIL_ACCOUNT_ID"}[role]
    eid = os.environ.get(env_key, "")
    if eid:
        return str(eid)
    email = os.environ.get({"ops": "OPS_GMAIL_ADDRESS", "work": "WORK_GMAIL_ADDRESS"}[role], "").lower()
    for a in accounts:
        if email and email in (a.get("emailAddress") or "").lower():
            return str(a["id"])
    return ""

URG = re.compile(r"incident|emergency|deadline|overdue|urgent|asap|critical|action required", re.I)
cut = int(time.time()) - window
picks = []
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

for role in roles:
    aid = account_id(role)
    if not aid:
        continue
    mbs = nc_get(f"/index.php/apps/mail/api/mailboxes?accountId={aid}")
    mbs = mbs.get("mailboxes", mbs if isinstance(mbs, list) else []) or []
    inbox = next((b.get("databaseId") for b in mbs if (b.get("specialRole") or "").lower() == "inbox" or (b.get("name") or "").upper() == "INBOX"), None)
    if not inbox:
        continue
    msgs = nc_get(f"/index.php/apps/mail/api/messages?mailboxId={inbox}&filter=unread&limit=50")
    if isinstance(msgs, list):
        pass
    elif isinstance(msgs, dict):
        picked = msgs.get("messages")
        msgs = picked if isinstance(picked, list) else (
            msgs.get("data") if isinstance(msgs.get("data"), list) else []
        )
    else:
        msgs = []
    for m in msgs:
        if not isinstance(m, dict):
            continue
        if int(m.get("dateInt") or 0) < cut:
            continue
        subj = m.get("subject") or ""
        if not URG.search(subj):
            continue
        picks.append({
            "account": role,
            "databaseId": m.get("databaseId"),
            "from": sender_from(m.get("from")),
            "subject": subj,
        })
print(json.dumps({"count": len(picks), "picks": picks, "roles": roles}))
PY
