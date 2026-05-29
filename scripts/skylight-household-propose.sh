#!/usr/bin/env bash
# Post numbered proposal cards to Family Hub from latest household audit.
# Usage: skylight-household-propose.sh [--dry-run] [--limit N] [--email-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"
STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
DRY=0
LIMIT=12
EMAIL_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --email-only) EMAIL_ONLY=1; shift ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

AUDIT=$(ls -1t "${LOG_DIR}"/skylight-household-audit-*.json 2>/dev/null | head -1)
[[ -n "$AUDIT" ]] || { echo "No audit JSON" >&2; exit 1; }

STAMP=$(date +%F)
BATCH="${STATE_DIR}/batch-${STAMP}.json"
LATEST="${STATE_DIR}/batch-latest.json"
mkdir -p "$STATE_DIR"

export AUDIT BATCH LATEST STATE_DIR ROOM SCRIPT_DIR DRY LIMIT EMAIL_ONLY

python3 <<'PY'
import json, os, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path

audit_path = Path(os.environ["AUDIT"])
state_dir = Path(os.environ["STATE_DIR"])
latest_path = Path(os.environ["LATEST"])
batch_path = Path(os.environ["BATCH"])
room = os.environ["ROOM"]
script_dir = os.environ["SCRIPT_DIR"]

audit = json.loads(audit_path.read_text())
terminal = {"applied", "rejected", "deferred"}
skip_ids = set()
if latest_path.is_file():
    prev = json.loads(latest_path.read_text())
    for p in prev.get("proposals", []):
        if p.get("status") in terminal:
            skip_ids.add(p["id"])

proposals = []
email_only = int(os.environ["EMAIL_ONLY"])
limit = int(os.environ["LIMIT"])

if email_only:
    for p in audit.get("enrich_calendar", []):
        if p.get("status") == "deferred":
            continue
        if p["id"] in skip_ids:
            continue
        if p.get("source") != "email":
            continue
        if float(p.get("confidence") or 0) < 0.85:
            continue
        proposals.append(p)
    proposals = proposals[:limit]
else:
    for key in ("enrich_calendar", "enrich_chores", "ask_operator"):
        for p in audit.get(key, []):
            if p.get("status") == "deferred":
                continue
            if p["id"] in skip_ids:
                continue
            proposals.append(p)
    buckets = {"enrich-calendar": [], "enrich-chore": [], "ask-": []}
    for p in proposals:
        pid = p["id"]
        if pid.startswith("enrich-calendar"):
            buckets["enrich-calendar"].append(p)
        elif pid.startswith("enrich-chore"):
            buckets["enrich-chore"].append(p)
        else:
            buckets["ask-"].append(p)
    mixed = []
    while any(buckets.values()) and len(mixed) < limit:
        for k in ("enrich-calendar", "enrich-chore", "ask-"):
            if buckets[k] and len(mixed) < limit:
                mixed.append(buckets[k].pop(0))
    proposals = mixed

total = len(proposals)
skipped = len(skip_ids)
cards = []
for i, p in enumerate(proposals, 1):
    pid = p["id"]
    if pid.startswith("enrich-calendar"):
        fields = p.get("fields") or {}
        fl = ", ".join(f"{k}={v!r}" for k, v in fields.items() if v is not None)
        src = p.get("source") or "rule"
        cards.append(
            f"Proposal {pid} ({i}/{total}) — ENRICH CALENDAR [{src}]\\n"
            f"Event: {p.get('summary')}\\n"
            f"Change: {fl or 'enrich fields'}\\n"
            f"Reply: @alfred YES {pid} | NO {pid}"
        )
    elif pid.startswith("enrich-chore"):
        f = p.get("fields") or {}
        cards.append(
            f"Proposal {pid} ({i}/{total}) — ENRICH CHORE\\n"
            f"Chore: {p.get('summary')} ({p.get('person')})\\n"
            f"Change: start_time={f.get('start_time')} routine={f.get('routine')}\\n"
            f"Reply: @alfred YES {pid} | NO {pid}"
        )
    else:
        cards.append(
            f"Proposal {pid} ({i}/{total}) — NEEDS YOU\\n"
            f"Calendar: {p.get('title')!r}\\n"
            f"Questions: {'; '.join(p.get('questions') or [])}\\n"
            f"Reply: @alfred EDIT {pid} <your answer> | NO {pid}\\n"
            f"(Unanswered 7d → deferred, calendar unchanged)"
        )

dry = int(os.environ["DRY"])
if dry:
    for c in cards:
        print(c)
        print("---")
    print(f"P0 dry-run: {total} cards (skipped {skipped} terminal ids)")
    if email_only:
        non_email = sum(1 for p in proposals if p.get("source") != "email")
        print(f"P-EMAIL dry-run: non_email={non_email} (must be 0)")
    sys.exit(0)

if total == 0:
    print(f"P-DEDUP: no new proposals (skipped {skipped} terminal ids)")
    sys.exit(0)

batch = {
    "generated_at": audit.get("generated_at"),
    "audit_path": str(audit_path),
    "proposals": proposals,
    "total": total,
    "skipped_terminal": skipped,
}
posted_at = datetime.utcnow().isoformat() + "Z"
for p in proposals:
    p.setdefault("status", "pending")
    p.setdefault("posted_at", posted_at)

if latest_path.is_file():
    prev = json.loads(latest_path.read_text())
    merged = {p["id"]: p for p in prev.get("proposals", [])}
    for p in proposals:
        merged[p["id"]] = p
    batch["proposals"] = list(merged.values())
    batch["total"] = len(proposals)

batch_path.write_text(json.dumps(batch, indent=2))
shutil.copy(batch_path, latest_path)

for c in cards:
    subprocess.run(["bash", f"{script_dir}/talk-post.sh", c, room], check=True)
print(f"P1 posted {total} cards to {room} (skipped {skipped} terminal)")
if email_only:
    print(f"P-EMAIL: {total} email-sourced calendar cards")
print(f"Batch: {batch_path}")
PY
