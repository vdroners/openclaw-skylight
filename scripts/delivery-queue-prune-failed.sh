#!/usr/bin/env bash
# Archive stale failed delivery-queue entries (default: older than 7 days).
# Usage: delivery-queue-prune-failed.sh [--dry-run] [--days N]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
FAILED_DIR="${OPENCLAW}/delivery-queue/failed"
ARCHIVE_DIR="${OPENCLAW}/delivery-queue/failed-archive"
DAYS="${DELIVERY_QUEUE_FAILED_MAX_AGE_DAYS:-7}"
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --days) DAYS="$2"; shift 2 ;;
    *) echo "usage: $0 [--dry-run] [--days N]" >&2; exit 2 ;;
  esac
done

[[ -d "$FAILED_DIR" ]] || { echo "DELIVERY_QUEUE_PRUNE skip (no failed dir)"; exit 0; }

mkdir -p "$ARCHIVE_DIR"
mapfile -t stale < <(find "$FAILED_DIR" -maxdepth 1 -name '*.json' -mtime "+${DAYS}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
  echo "DELIVERY_QUEUE_PRUNE ok moved=0 days=${DAYS}"
  exit 0
fi

MOVED=0
for f in "${stale[@]}"; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  if [[ "$DRY" -eq 1 ]]; then
    echo "would archive $base"
  else
    mv "$f" "${ARCHIVE_DIR}/${base}"
  fi
  MOVED=$((MOVED + 1))
done

echo "DELIVERY_QUEUE_PRUNE ok moved=${MOVED} days=${DAYS}$([[ $DRY -eq 1 ]] && echo ' (dry-run)')"
