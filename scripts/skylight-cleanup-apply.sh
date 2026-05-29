#!/usr/bin/env bash
# Apply approved Skylight household cleanup proposals (B2/B3/B5).
# Usage: skylight-cleanup-apply.sh --dry-run [B2.6 B2.4 B2.5 B3 B5.1 ...]
#        skylight-cleanup-apply.sh --apply B2.6
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

FID="$SKYLIGHT_FRAME_ID"
API="$SKYLIGHT_API_URL"
AUTH="$SKYLIGHT_AUTHORIZATION"
GROCERY_ID="${SKYLIGHT_DEFAULT_GROCERY_LIST_ID:-5948982}"

# Chore-chart kid profile IDs
PHOEBE=19116283
WESLEY=19255362
DAN=19177556

# B2.6 — Phoebe weekly Clean room (TU/SU), keep evening Clean Room routine
PHOEBE_WEEKLY_CLEAN_ROOM=84072913

DRY_RUN=1
SECTIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --apply) DRY_RUN=0; shift ;;
    B*|b*) SECTIONS+=("$1"); shift ;;
    -h|--help)
      echo "Usage: $0 --dry-run|--apply [B2.6 B2.4 B2.5 B3 B5.1 ...]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#SECTIONS[@]} -eq 0 ]]; then
  SECTIONS=(B2.6 B2.4 B2.5 B3 B5.1)
fi

log() { echo "[$1] $2"; }
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log DRY "$*"
  else
    log APPLY "$*"
    eval "$@"
  fi
}

apply_b26() {
  log INFO "B2.6: delete Phoebe weekly Clean room series $PHOEBE_WEEKLY_CLEAN_ROOM"
  run "skylight chores deleteChore --frame-id '$FID' --chore-id '$PHOEBE_WEEKLY_CLEAN_ROOM' --apply-to all"
}

apply_b24() {
  log INFO "B2.4: set reward_points>=1 on chore series with None"
  python3 <<PY
import json, os, subprocess, sys

fid = os.environ["SKYLIGHT_FRAME_ID"]
dry = $DRY_RUN
today = __import__("datetime").date.today().isoformat()
week = (__import__("datetime").date.today() + __import__("datetime").timedelta(days=14)).isoformat()
chores = json.loads(subprocess.check_output(
    ["skylight", "chores", "listChores", "--frame-id", fid, "--after", today, "--before", week, "--json"],
    text=True,
))
groups = {}
for c in chores.get("data") or []:
    a = c.get("attributes") or {}
    gid = str(a.get("group") or a.get("series") or c["id"].split("-")[0])
    if gid not in groups:
        groups[gid] = c
updated = 0
for gid, c in groups.items():
    pts = (c.get("attributes") or {}).get("reward_points")
    if pts is not None and pts >= 1:
        continue
    summary = (c.get("attributes") or {}).get("summary")
    print(f"  series {gid} ({summary}): reward_points {pts} -> 1")
    if not dry:
        subprocess.check_call([
            "skylight", "chores", "updateChore", "--frame-id", fid,
            "--chore-id", gid, "--reward-points", "1", "--json",
        ], stdout=subprocess.DEVNULL)
    updated += 1
print(f"B2.4: {updated} series to update")
PY
}

apply_b25() {
  log INFO "B2.5: delete all task box items (legacy duplicate of scheduled chores)"
  ids=$(skylight task-box listItems --frame-id "$FID" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(x['id'] for x in d.get('data',[])))")
  if [[ -z "$ids" ]]; then
    log INFO "task box already empty"
    return
  fi
  IFS=',' read -ra ID_ARR <<< "$ids"
  for id in "${ID_ARR[@]}"; do
    run "skylight task-box deleteItem --frame-id '$FID' --item-id '$id'"
  done
}

apply_b3() {
  log INFO "B3.1: bulk delete completed grocery items (keep pending)"
  ids=$(skylight lists listItems --frame-id "$FID" --list-id "$GROCERY_ID" --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
ids=[x['id'] for x in d.get('data',[]) if (x.get('attributes') or {}).get('status')=='completed']
print(','.join(ids))
")
  if [[ -z "$ids" ]]; then
    log INFO "no completed grocery items"
    return
  fi
  run "skylight lists deleteItems --frame-id '$FID' --list-id '$GROCERY_ID' --ids '$ids'"
}

apply_b51() {
  log INFO "B5.1: create kid rewards for Phoebe + Wesley"
  rewards=(
    "Extra 15 min screen time|10"
    "Pick tonight's dessert|15"
    "Choose family movie|20"
    "Small prize from prize box|25"
  )
  existing=$(curl -s "$API/frames/$FID/rewards" -H "Authorization: $AUTH" | python3 -c "import json,sys; d=json.load(sys.stdin); print('|'.join((x.get('attributes') or {}).get('name','') for x in d.get('data',[])))")
  for row in "${rewards[@]}"; do
    name="${row%%|*}"
    pts="${row##*|}"
    if echo "$existing" | grep -Fq "$name"; then
      log SKIP "reward exists: $name"
      continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log DRY "POST reward name=$name pts=$pts categories=Phoebe,Wesley"
    else
      curl -sS -X POST "$API/frames/$FID/rewards" \
        -H "Authorization: $AUTH" -H "Content-Type: application/json" \
        -H "User-Agent: SkylightMobile (web)" \
        -d "{\"name\":\"$name\",\"point_value\":$pts,\"category_ids\":[$PHOEBE,$WESLEY],\"respawn_on_redemption\":true}" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print('  created', len(d.get('data',[])), 'entries for', sys.argv[1])" "$name"
    fi
  done
}

apply_b23() {
  log INFO "B2.3: fix typo Deep Clen Cat Box -> Deep Clean Cat Box"
  run "skylight chores updateChore --frame-id '$FID' --chore-id 77952388 --summary 'Deep Clean Cat Box'"
}

for sec in "${SECTIONS[@]}"; do
  case "${sec^^}" in
    B2.6) apply_b26 ;;
    B2.4) apply_b24 ;;
    B2.5) apply_b25 ;;
    B2.3) apply_b23 ;;
    B2) apply_b26; apply_b24; apply_b25; apply_b23 ;;
    B3|B3.1) apply_b3 ;;
    B5|B5.1) apply_b51 ;;
    *) echo "Unknown section: $sec" >&2; exit 1 ;;
  esac
done

echo "cleanup-apply: done (dry_run=$DRY_RUN sections=${SECTIONS[*]})"
