#!/usr/bin/env bash
# Deterministic Nextcloud DB backup verification (shell-direct cron + Lobster).
# Env: NEXTCLOUD_DB_BACKUP_DIR, NEXTCLOUD_BACKUP_LOG (optional)
set -euo pipefail

BACKUP_DIR="${NEXTCLOUD_DB_BACKUP_DIR:?set NEXTCLOUD_DB_BACKUP_DIR in .env}"
LOG="${NEXTCLOUD_BACKUP_LOG:-}"

latest=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1 || true)
if [[ -z "$latest" ]]; then
  echo "BACKUP_FAIL no .sql.gz files in $BACKUP_DIR"
  exit 1
fi

size=$(stat -c%s "$latest")
age_h=$(( ($(date +%s) - $(stat -c%Y "$latest")) / 3600 ))
if (( age_h > 25 )); then
  echo "BACKUP_FAIL stale: $latest (${age_h}h old)"
  exit 1
fi
if (( size < 1000000 )); then
  echo "BACKUP_FAIL too small: $latest ($size bytes)"
  exit 1
fi
if [[ -n "$LOG" && -f "$LOG" ]] && tail -5 "$LOG" | grep -qi error; then
  echo "BACKUP_WARN errors in log (check $LOG)"
fi

echo "BACKUP_OK file=$(basename "$latest") size=$size age_h=${age_h}"
exit 0
