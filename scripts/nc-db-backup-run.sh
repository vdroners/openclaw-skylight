#!/usr/bin/env bash
# Nextcloud MariaDB dump to /media/4TB/backups/nextcloud-db (docker PATH safe).
# Replaces broken root cron when docker is not on cron PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${OPENCLAW_DIR}/.env"
  set +a
fi

BACKUP_DIR="${NEXTCLOUD_DB_BACKUP_DIR:-/media/4TB/backups/nextcloud-db}"
LOG="${NEXTCLOUD_BACKUP_RUN_LOG:-/media/4TB/backups/nextcloud-backup.log}"
DB_CONTAINER="${NC_DB_CONTAINER:-cloud_db}"
DB_USER="${NC_DB_USER:-ncadmin}"
DB_NAME="${NC_DB_NAME:-nextcloud}"
DB_PASS="${MYSQL_PASSWORD:-${NC_DB_PASSWORD:-}}"
if [[ -z "$DB_PASS" ]]; then
  DB_PASS="$(docker exec "$DB_CONTAINER" env 2>/dev/null | awk -F= '/^MYSQL_PASSWORD=/{print $2; exit}' || true)"
fi
[[ -n "$DB_PASS" ]] || { echo "[$(date -Is)] ERROR: MYSQL_PASSWORD not set (add to ~/.openclaw/.env or cloud_db env)" >&2; exit 1; }
RETENTION_DAYS="${NC_DB_BACKUP_RETENTION_D:-14}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/nextcloud_db_${TIMESTAMP}.sql.gz"

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
mkdir -p "$BACKUP_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  echo "[$(date -Is)] ERROR: container ${DB_CONTAINER} not running" | tee -a "$LOG" >&2
  exit 1
fi

if docker exec "$DB_CONTAINER" mariadb-dump \
  -u "$DB_USER" -p"$DB_PASS" \
  --single-transaction --routines --triggers \
  "$DB_NAME" 2>/dev/null | gzip > "$BACKUP_FILE"; then
  if [[ -s "$BACKUP_FILE" ]]; then
    echo "[$(date -Is)] DB backup OK: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | awk '{print $1}'))" | tee -a "$LOG"
    find "$BACKUP_DIR" -name 'nextcloud_db_*.sql.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
    exit 0
  fi
fi

rm -f "$BACKUP_FILE"
echo "[$(date -Is)] ERROR: DB backup failed" | tee -a "$LOG" >&2
exit 1
