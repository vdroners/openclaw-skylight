#!/usr/bin/env bash
# Defer unanswered ask_operator proposals after 7 days (hide_not_delete).
# Usage: defer-stale.sh [--dry-run]
set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

STATE_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/state/household-proposals"
BATCH="${STATE_DIR}/batch-latest.json"
LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
AUDIT=$(ls -1t "${LOG_DIR}"/skylight-household-audit-*.json 2>/dev/null | head -1)

export BATCH AUDIT DRY

python3 <<'PY'
import json, os, sys
from datetime import datetime, timedelta
from pathlib import Path

batch_path = Path(os.environ["BATCH"])
audit_path = Path(os.environ["AUDIT"]) if os.environ.get("AUDIT") else None
dry = int(os.environ.get("DRY", "0"))
cutoff = datetime.utcnow() - timedelta(days=7)
deferred = 0
would = []

if batch_path.is_file():
    batch = json.loads(batch_path.read_text())
    for p in batch.get("proposals", []):
        if not p["id"].startswith("ask-"):
            continue
        if p.get("status") not in ("pending", "approved"):
            continue
        posted = p.get("posted_at") or batch.get("generated_at")
        if not posted:
            continue
        try:
            ts = datetime.fromisoformat(posted.replace("Z", "+00:00").replace("+00:00", ""))
        except ValueError:
            continue
        if ts.replace(tzinfo=None) > cutoff:
            continue
        would.append(p["id"])
        if not dry:
            p["status"] = "deferred"
            p["deferred_at"] = datetime.utcnow().isoformat() + "Z"
            p["deferred_reason"] = "hide_not_delete_after_7d"
            deferred += 1
    if not dry:
        batch_path.write_text(json.dumps(batch, indent=2))

if not dry and audit_path and audit_path.is_file():
    audit = json.loads(audit_path.read_text())
    audit.setdefault("deferred", [])
    batch = json.loads(batch_path.read_text()) if batch_path.is_file() else {"proposals": []}
    for p in audit.get("ask_operator", []):
        if p.get("status") == "deferred":
            continue
        if any(d.get("id") == p["id"] for d in audit["deferred"]):
            continue
        match = next((x for x in batch.get("proposals", []) if x["id"] == p["id"]), None)
        if match and match.get("status") == "deferred":
            p["status"] = "deferred"
            audit["deferred"].append({"id": p["id"], "reason": "hide_not_delete_after_7d", "hidden_at": match.get("deferred_at")})
            deferred += 1
    audit_path.write_text(json.dumps(audit, indent=2))

if dry:
    print(f"P5 defer-stale dry-run: would defer {len(would)} — {would[:5]}")
else:
    print(f"P5 defer-stale: {deferred} proposals deferred")
sys.exit(0)
PY
