#!/usr/bin/env bash
# Disable broken root 03:00 nextcloud-backup.sh cron (user timer alfred-nc-db-backup handles backups).
# Requires sudo. Idempotent.
set -euo pipefail

ROOT_CRON_MARKER="/media/4TB/cloud/nextcloud-backup.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if ! sudo -n true 2>/dev/null; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 1
fi

sudo crontab -l 2>/dev/null | grep -vF "$ROOT_CRON_MARKER" >"$TMP" || true
if grep -qF "$ROOT_CRON_MARKER" <(sudo crontab -l 2>/dev/null || true); then
  sudo crontab "$TMP"
  echo "[root-cron] Removed entry referencing ${ROOT_CRON_MARKER}"
else
  echo "[root-cron] No matching entry (already disabled)"
fi

echo "[root-cron] User backup timer:"
systemctl --user is-enabled alfred-nc-db-backup.timer 2>/dev/null || echo "  install docs/templates/alfred-nc-db-backup.* first"
