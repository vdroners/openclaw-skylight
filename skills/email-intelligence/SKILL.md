---
name: email-intelligence
description: "Read, summarize, and triage emails from OpenClaw agent Nextcloud Mail account(s). Detect urgent items, draft replies, and generate daily digests. Account and inbox are discovered at runtime; no hardcoded IDs."
metadata:
  openclaw:
    emoji: "mail"
    requires:
      bins: ["curl", "jq", "python3"]
      env: ["NEXTCLOUD_URL", "NEXTCLOUD_USER", "NEXTCLOUD_PASS"]
---

# Email Intelligence Skill

Manage and analyze email via the Nextcloud Mail internal API.

## IMPORTANT: Tool choice

All HTTP calls in this skill must be issued via the `exec` tool (shell). The `read` / `write` / `message` tools are unrelated; `read` is for the local filesystem and will fail with `path: must have required property 'path'` if misused.

## Auth & required header

The Nextcloud Mail API rejects unauthenticated-looking requests with `{"message":"CSRF check failed"}` even when Basic Auth succeeds. ALWAYS include the `OCS-APIREQUEST: true` header on every call.

```bash
AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true")
NC="$NEXTCLOUD_URL"
```

## Account role routing (3-account OpenClaw setup)

| Role | Gmail (example) | Env ID | Env address | Use |
|------|-----------------|--------|-------------|-----|
| `family` | household parent | `FAMILY_MAIL_ACCOUNT_ID` | `FAMILY_GMAIL_ADDRESS` | Skylight calendar enrich (read-only); **not** in daily digest |
| `ops` | personal ops inbox | `OPS_MAIL_ACCOUNT_ID` | `OPS_GMAIL_ADDRESS` | Daily digest + urgent scan (IMAP+SMTP) |
| `work` | work inbox | `WORK_MAIL_ACCOUNT_ID` | `WORK_GMAIL_ADDRESS` | Daily digest + urgent scan (IMAP+SMTP) |

Discovery order: prefer env `*_MAIL_ACCOUNT_ID`, else match `*_GMAIL_ADDRESS` against `/mail/api/accounts`. Run `bash scripts/nc-mail-sync-accounts.sh --check` to refresh `state/mail-account-ids.json`.

Automations: `email-daily-digest-post.sh` and `email-urgent-scan.sh` default to **ops+work** only (`URGENT_SCAN_ACCOUNTS=ops,work`). Family mail stays on `skylight-email-enrich-scan.sh`.

## Discover account and INBOX (run first every turn)

Optional: set `FAMILY_MAIL_ACCOUNT_ID` to pin the family account for household enrichment.

```bash
# List all accounts (multi-account)
curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/accounts" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); a=d if isinstance(d,list) else d.get("accounts",[]) or []; [print(x["id"], x.get("emailAddress")) for x in a]'

MAIL_ACCOUNT="${FAMILY_MAIL_ACCOUNT_ID:-}"
if [ -z "$MAIL_ACCOUNT" ]; then
  MAIL_ACCOUNT=$(curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/accounts" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); a=d if isinstance(d,list) else d.get("accounts",[]) or []; print(a[0]["id"] if a else "")')
fi

if [ -z "$MAIL_ACCOUNT" ]; then
  echo "No mail account configured for user $NEXTCLOUD_USER. See RUNBOOK 'Gmail / Nextcloud Mail setup'."
  exit 2
fi

INBOX_ID=$(curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/mailboxes?accountId=$MAIL_ACCOUNT" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); mbs=d.get("mailboxes",[]) if isinstance(d,dict) else (d if isinstance(d,list) else []); ids=[b.get("databaseId") for b in mbs if (b.get("specialRole")=="inbox" or b.get("name","").upper()=="INBOX")]; print(ids[0] if ids else "")')
```

## Endpoints (all require `OCS-APIREQUEST: true`)

### List Mailboxes for an Account

```bash
curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/mailboxes?accountId=$MAIL_ACCOUNT"
```

### List Messages in a Mailbox

```bash
# Unread only, newest first, up to 50
curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/messages?mailboxId=$INBOX_ID&filter=unread&limit=50"
```

Each returned message includes: `databaseId`, `subject`, `dateInt` (unix seconds), `from: [{label,email}]`, `to`, `cc`, `flags.seen`, `flags.flagged`, `mailboxId`.

### Read a Specific Message Body

```bash
curl -s "${AUTH[@]}" "${HDRS[@]}" "$NC/index.php/apps/mail/api/messages/<databaseId>/body"
```

### Flag / Unflag a Message

```bash
curl -s "${AUTH[@]}" "${HDRS[@]}" -X PUT "$NC/index.php/apps/mail/api/messages/<databaseId>/flags" \
  -H "Content-Type: application/json" \
  -d '{"flags":{"flagged":true}}'
```

### Send Reply (Draft)

```bash
# Draft a reply — user must confirm before actual send
curl -s "${AUTH[@]}" "${HDRS[@]}" -X POST "$NC/index.php/apps/mail/api/accounts/$MAIL_ACCOUNT/draft" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "<recipient>",
    "subject": "Re: <original subject>",
    "body": "<reply text>",
    "inReplyToMessageId": "<original messageId>"
  }'
```

## Capabilities

### 1. Inbox Summary
List unread messages, show sender, subject, and timestamp. Group by urgency.

### 2. Urgent Item Detection
Flag messages whose subject OR preview contains (case-insensitive): `incident`, `emergency`, `deadline`, `overdue`, `urgent`, `ASAP`, `critical`, `action required`.

### 3. Reply Drafting
Draft a reply to a specific message. Always present the draft to the user for confirmation before sending. Never auto-send.

### 4. Daily Digest
Summarize unread emails received in the last 24 hours:
- Total unread count (in the last 24h)
- URGENT items listed first (sender | subject)
- Remaining messages grouped by sender, one-line summary each
- Post digest to Talk

## Usage Patterns

- "Check my email" → List unread, highlight urgent
- "Summarize overnight emails" → Daily digest
- "Reply to the email from John about the battery order" → Draft reply, present for approval
- "Flag the invoice email as important" → Set flagged flag
