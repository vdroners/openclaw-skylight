#!/usr/bin/env bash
# Apply test-week cron profile (disable listed agentTurn jobs via openclaw cron CLI).
# Usage: apply-test-week-cron-profile.sh [--dry-run]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
PROFILE="${OPENCLAW}/workspace/references/test-week-cron-profile.yaml"
DISABLED_IDS="${OPENCLAW}/cron/test-week-disabled-ids.txt"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -f "$PROFILE" ]] || { echo "missing $PROFILE" >&2; exit 1; }

python3 - "$PROFILE" "$DISABLED_IDS" "$DRY" <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML required")

profile_path, disabled_ids_path, dry = map(Path, sys.argv[1:4])
dry_run = dry == "1"
profile = yaml.safe_load(profile_path.read_text()) or {}
disable = set(profile.get("disable") or [])
disable |= set(profile.get("extra_disable") or ())

raw = subprocess.check_output(["openclaw", "cron", "list", "--json"], text=True)
jobs = json.loads(raw).get("jobs") or []

changed = []
disabled_ids = []
for j in jobs:
    name = j.get("name")
    if name not in disable or not j.get("enabled", True):
        continue
    changed.append(name)
    disabled_ids.append(j["id"])
    if not dry_run:
        subprocess.run(["openclaw", "cron", "disable", j["id"]], check=True)

if dry_run:
    print(f"would disable {len(changed)} jobs: {', '.join(changed)}")
else:
    disabled_ids_path.parent.mkdir(parents=True, exist_ok=True)
    disabled_ids_path.write_text("\n".join(disabled_ids) + ("\n" if disabled_ids else ""))
    print(f"disabled {len(changed)} jobs: {', '.join(changed)}")
    applied = Path(profile_path).parent.parent.parent / "state" / "test-week-profile-applied.txt"
    applied.parent.mkdir(parents=True, exist_ok=True)
    applied.write_text(datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds") + "\n")
    raw = subprocess.check_output(["openclaw", "cron", "list", "--json"], text=True)
    jobs = json.loads(raw).get("jobs") or []

enabled_agent = sum(
    1 for j in jobs
    if j.get("enabled") and (j.get("payload") or {}).get("kind") == "agentTurn"
)
print(f"enabled agentTurn count: {enabled_agent}")
if enabled_agent > 25:
    print(f"WARN CAP-P1: enabled agentTurn={enabled_agent} > 25")
    raise SystemExit(1)
print("PASS CAP-P1 test-week profile applied")
PY
