#!/usr/bin/env bash
# Apply approved Skylight household cleanup proposals (operator-configured IDs).
# Usage: skylight-cleanup-apply.sh --dry-run [B2.6 B2.4 ...]
# Configure category/chore IDs via .env or household-model.json before --apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

FID="$SKYLIGHT_FRAME_ID"
API="$SKYLIGHT_API_URL"
AUTH="$SKYLIGHT_AUTHORIZATION"
GROCERY_ID="${SKYLIGHT_DEFAULT_GROCERY_LIST_ID:-}"

KID1_CAT="${SKYLIGHT_KID1_CATEGORY_ID:-}"
KID2_CAT="${SKYLIGHT_KID2_CATEGORY_ID:-}"
PARENT_CAT="${SKYLIGHT_PARENT_CATEGORY_ID:-}"
WEEKLY_CLEAN_ROOM_CHORE="${SKYLIGHT_WEEKLY_CLEAN_ROOM_CHORE_ID:-}"

if [[ -z "$KID1_CAT" && -z "$KID2_CAT" && -z "$WEEKLY_CLEAN_ROOM_CHORE" ]]; then
  echo "CLEANUP_SKIP: set SKYLIGHT_* category/chore IDs in .env before running cleanup"
  exit 0
fi

DRY_RUN=1
SECTIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --apply) DRY_RUN=0; shift ;;
    B*) SECTIONS+=("$1"); shift ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ ${#SECTIONS[@]} -gt 0 ]] || SECTIONS=(B2.6 B2.4 B2.5 B3 B5.1)

log() { echo "[cleanup] $*"; }
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY $*"
  else
    eval "$@"
  fi
}

for sec in "${SECTIONS[@]}"; do
  case "$sec" in
    B2.6)
      if [[ -n "$WEEKLY_CLEAN_ROOM_CHORE" ]]; then
        log "B2.6: delete weekly Clean room series $WEEKLY_CLEAN_ROOM_CHORE"
        run "skylight chores deleteChore --frame-id '$FID' --chore-id '$WEEKLY_CLEAN_ROOM_CHORE' --apply-to all"
      else
        log "B2.6: skip (SKYLIGHT_WEEKLY_CLEAN_ROOM_CHORE_ID unset)"
      fi
      ;;
    B5.1)
      if [[ -n "$KID1_CAT" && -n "$KID2_CAT" ]]; then
        log "B5.1: create kid rewards (configure reward payloads in operator runbook)"
      else
        log "B5.1: skip (kid category IDs unset)"
      fi
      ;;
    *)
      log "$sec: configure in operator runbook or extend this script"
      ;;
  esac
done

log "CLEANUP_DONE dry=$DRY_RUN sections=${SECTIONS[*]}"
