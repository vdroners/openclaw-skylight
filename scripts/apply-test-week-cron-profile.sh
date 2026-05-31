#!/usr/bin/env bash
# Apply test-week cron profile (disable listed agentTurn jobs).
# Usage: apply-test-week-cron-profile.sh [--dry-run]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
PROFILE="${OPENCLAW}/workspace/references/test-week-cron-profile.yaml"
JOBS="${OPENCLAW}/cron/jobs.json"
BACKUP="${OPENCLAW}/cron/jobs.json.pre-test-week"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -f "$PROFILE" ]] || { echo "missing $PROFILE" >&2; exit 1; }

python3 - "$PROFILE" "$JOBS" "$BACKUP" "$DRY" <<'PY'
import json, shutil, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML required")

profile_path, jobs_path, backup_path, dry = map(Path, sys.argv[1:5])
dry_run = dry == "1"
profile = yaml.safe_load(profile_path.read_text()) or {}
disable = set(profile.get("disable") or [])
data = json.loads(jobs_path.read_text())
if not backup_path.exists() and not dry_run:
    shutil.copy2(jobs_path, backup_path)
    print(f"backup: {backup_path}")

changed = []
for j in data.get("jobs", []):
    name = j.get("name")
    if name in disable and j.get("enabled", True):
        changed.append(name)
        if not dry_run:
            j["enabled"] = False
            note = " [test-week profile disabled]"
            desc = j.get("description") or ""
            if "test-week profile" not in desc:
                j["description"] = (desc + note).strip()

if dry_run:
    print(f"would disable {len(changed)} jobs: {', '.join(changed)}")
else:
    jobs_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"disabled {len(changed)} jobs: {', '.join(changed)}")
    from datetime import datetime, timezone
    applied = Path(profile_path).parent.parent.parent / "state" / "test-week-profile-applied.txt"
    applied.parent.mkdir(parents=True, exist_ok=True)
    applied.write_text(datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds") + "\n")

enabled_agent = sum(1 for j in data.get("jobs", []) if j.get("enabled") and (j.get("payload") or {}).get("kind") == "agentTurn")
print(f"enabled agentTurn count: {enabled_agent}")
if enabled_agent > 25:
    print(f"WARN CAP-P1: enabled agentTurn={enabled_agent} > 25")
    raise SystemExit(1)
print("PASS CAP-P1 test-week profile applied")
PY
