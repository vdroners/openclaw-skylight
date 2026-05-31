#!/usr/bin/env bash
# Restore cron jobs.json from pre-test-week backup.
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
BACKUP="${OPENCLAW}/cron/jobs.json.pre-test-week"
JOBS="${OPENCLAW}/cron/jobs.json"

[[ -f "$BACKUP" ]] || { echo "no backup at $BACKUP" >&2; exit 1; }
cp "$BACKUP" "$JOBS"
echo "restored $JOBS from $BACKUP"
