#!/usr/bin/env bash
# Audit OpenClaw cron jobs: delivery config, model, workload profile, last run status.
# Usage: cron-audit.sh [--check]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
JOBS="$OPENCLAW/cron/jobs.json"
RUNS="$OPENCLAW/cron/runs"
MAP="$OPENCLAW/workspace/references/cron-model-map.yaml"
SHELL_MANIFEST="$OPENCLAW/workspace/references/cron-shell-direct.yaml"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

[[ -f "${OPENCLAW}/.env" ]] && set -a && source "${OPENCLAW}/.env" && set +a
export SKYLIGHT_FAMILY_TALK_ROOM SKYLIGHT_OPS_TALK_ROOM

export PATH="${HOME}/.nvm/versions/node/v24.14.1/bin:${PATH:-/usr/bin:/bin}"

python3 - "$JOBS" "$RUNS" "$MAP" "$SHELL_MANIFEST" "$CHECK" <<'PY'
import json, os, sys
from pathlib import Path

jobs_path, runs_dir, map_path, shell_path, check_raw = sys.argv[1:6]
check = check_raw == "1"

try:
    import yaml
    job_profiles = (yaml.safe_load(Path(map_path).read_text()) or {}).get("jobs") or {}
except Exception:
    job_profiles = {}

shell_ids = set()
if Path(shell_path).is_file():
    try:
        import yaml
        shell_ids = {r["id"] for r in (yaml.safe_load(Path(shell_path).read_text()) or {}).get("jobs", [])}
    except Exception:
        pass

critical_ids = set(shell_ids) | {
    "eeb9dfa1-a825-4e7f-ad3a-f94c8ab03889",  # email-urgent-flag
}
# Infra defer: stale DB backup is tracked separately (CAP-F3), not week-2 automation.
critical_ids.discard("8145b68e-7559-4b82-a81e-034b364b9afd")

allowed_rooms = {
    r for r in (
        os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM", ""),
        os.environ.get("SKYLIGHT_OPS_TALK_ROOM", ""),
    ) if r
}

SILENT_SUFFIXES = (
    "nightly-prune", "self-watchdog", "weekly-perf-digest",
    "phase4-routing-check", "notes-end-of-day", "tables-fleet-analytics",
    "ssl-cert-check",
)


def is_silent_job(job_name: str) -> bool:
    return any(job_name.endswith(s) or s in job_name for s in SILENT_SUFFIXES)


data = json.loads(Path(jobs_path).read_text())


def last_run(job_id: str):
    p = Path(runs_dir) / f"{job_id}.jsonl"
    if not p.is_file():
        return None
    try:
        line = p.read_text().strip().splitlines()[-1]
        return json.loads(line)
    except Exception:
        return None


print("| name | enabled | profile | model | last_status | delivery_ok | fix_needed |")
print("| --- | --- | --- | --- | --- | --- | --- |")

fix_count = 0
missing_model = 0
critical_errors = 0
for j in data.get("jobs", []):
    name = j.get("name", "?")
    jid = j.get("id", "")
    enabled = j.get("enabled", True)
    payload = j.get("payload") or {}
    model = payload.get("model") or "(missing)"
    profile = job_profiles.get(name, "—")
    d = j.get("delivery") or {}
    mode = d.get("mode", "")
    ch = d.get("channel", "")
    to = d.get("to", "")

    if is_silent_job(name) and mode == "none":
        delivery_ok = True
        fix = "no (silent)"
    elif not enabled:
        delivery_ok = True
        fix = "n/a"
    elif not allowed_rooms:
        delivery_ok = mode == "announce" and ch == "nextcloud-talk" and bool(to)
        fix = "no" if delivery_ok else "yes: delivery (set SKYLIGHT_*_TALK_ROOM in .env for strict check)"
    else:
        delivery_ok = mode == "announce" and ch == "nextcloud-talk" and to in allowed_rooms
        fix = "no" if delivery_ok else "yes: delivery"

    if enabled and model == "(missing)":
        missing_model += 1
        fix = "yes: no model"

    lr = last_run(jid)
    last_status = lr.get("status", "-") if lr else "-"
    if check and jid in critical_ids and last_status == "error":
        critical_errors += 1
        fix = "CR-AUDIT: last_status=error"

    if lr and lr.get("delivery", {}).get("resolved", {}).get("error"):
        if fix == "no":
            fix = "maybe: last delivery error"

    if enabled and not delivery_ok:
        fix_count += 1

    print(f"| {name} | {enabled} | {profile} | {model} | {last_status} | {delivery_ok} | {fix} |")

if missing_model:
    print(f"\nEnabled jobs missing model: {missing_model}", file=sys.stderr)
print(f"\nEnabled jobs with delivery issues: {fix_count}", file=sys.stderr)
if check and critical_errors:
    print(f"CR-AUDIT FAIL: {critical_errors} critical job(s) last_status=error", file=sys.stderr)
    sys.exit(1)
sys.exit(1 if fix_count or missing_model else 0)
PY
