#!/usr/bin/env bash
# Run OpenClaw backlog / daily catch-up without LLM agentTurn.
# Usage: openclaw-catchup.sh [--morning] [--household] [--qa] [--gates] [--all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
MANIFEST="${OPENCLAW}/workspace/references/cron-shell-direct.yaml"

MORNING=0
HOUSEHOLD=0
QA=0
GATES=0

if [[ $# -eq 0 ]]; then
  MORNING=1
  HOUSEHOLD=1
  QA=0
  GATES=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --morning) MORNING=1; shift ;;
    --household) HOUSEHOLD=1; shift ;;
    --qa) QA=1; shift ;;
    --gates) GATES=1; shift ;;
    --all) MORNING=1; HOUSEHOLD=1; QA=1; GATES=1; shift ;;
    -h|--help)
      sed -n '1,5p' "$0"
      echo "  Default: morning + household + gates (no QA)."
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

# shellcheck source=/dev/null
[[ -f "${OPENCLAW}/cron/env.sh" ]] && source "${OPENCLAW}/cron/env.sh"
[[ -f "${OPENCLAW}/.env" ]] && set -a && source "${OPENCLAW}/.env" && set +a

run_cron_job() {
  local id="$1" name="$2" script="$3" grep="${4:-POSTED}"
  echo "== cron: $name"
  bash "${SCRIPT_DIR}/run-openclaw-cron-shell.sh" "$id" "$name" "$script" "$grep"
}

step() {
  echo ""
  echo "### $1"
  shift
  "$@" || { echo "WARN: $* failed (rc=$?)" >&2; return 0; }
}

if [[ "$MORNING" -eq 1 ]]; then
  echo "=== Morning shell-direct catch-up ==="
  PT_HOUR="$(TZ=America/Los_Angeles date +%H)"
  PT_MIN="$(TZ=America/Los_Angeles date +%M)"
  PT_NOW=$((10#$PT_HOUR * 60 + 10#$PT_MIN))

  step "Skylight auth refresh" bash "${SCRIPT_DIR}/skylight-auth-refresh.sh"

  step "Calendar morning brief" run_cron_job \
    f2b3c4d5-calendar-morning-brief calendar-morning-brief \
    "${SCRIPT_DIR}/calendar-morning-brief-post.sh" CALENDAR_BRIEF_POSTED

  step "Tasks morning brief" run_cron_job \
    15faf3dc-295e-47ba-a717-98e4c49e06d8 tasks-morning-brief \
    "${SCRIPT_DIR}/tasks-morning-brief-post.sh" TASKS_BRIEF_POSTED

  if [[ "$PT_NOW" -ge $((7 * 60)) ]]; then
    step "Email daily digest" run_cron_job \
      e1a2b3c4-email-daily-digest email-daily-digest \
      "${SCRIPT_DIR}/email-daily-digest-post.sh" DIGEST_POSTED
  fi

  if [[ "$PT_NOW" -ge $((7 * 60 + 30)) ]]; then
    step "Skylight family morning" run_cron_job \
      b7c8d9e0-skylight-family-morning skylight-family-morning \
      "${SCRIPT_DIR}/skylight-family-morning-post.sh" SKYLIGHT_FAMILY_BRIEF_POSTED
  fi

  if [[ "$PT_NOW" -ge $((8 * 60)) ]]; then
    step "Daily health report" run_cron_job \
      d30111b3-585c-424e-8988-eb901ce6380b daily-health-report \
      "${SCRIPT_DIR}/daily-health-report-post.sh" HEALTH_REPORT_POSTED
  fi

  step "Self watchdog" run_cron_job \
    c924d4ec-a108-475b-9a0e-bd6f8db87b23 openclaw-self-watchdog \
    "${SCRIPT_DIR}/alfred-self-watchdog-post.sh" watchdog
fi

if [[ "$HOUSEHOLD" -eq 1 ]]; then
  echo ""
  echo "=== Household / mail pipeline ==="

  step "Mail account sync" bash "${SCRIPT_DIR}/nc-mail-sync-accounts.sh" --apply
  step "Mail gates" bash "${SCRIPT_DIR}/mail-gates.sh" --check

  step "Deep household audit" bash "${SCRIPT_DIR}/skylight-household-deep-audit.sh"
  step "Defer stale ask cards" bash "${SCRIPT_DIR}/skylight-household-defer-stale.sh"
  step "Email enrich scan (E2)" bash "${SCRIPT_DIR}/skylight-email-enrich-scan.sh"

  PROPOSE_DRY="$(
    bash "${SCRIPT_DIR}/skylight-household-propose.sh" --dry-run --limit 12 2>&1 || true
  )"
  echo "$PROPOSE_DRY"
  if grep -qE 'P0 dry-run: [1-9]|P-EMAIL dry-run:' <<<"$PROPOSE_DRY"; then
    step "Propose + post to Family Hub" bash "${SCRIPT_DIR}/skylight-household-propose.sh" --limit 12
  else
    echo "P-DEDUP: no new proposal cards to post"
  fi

  step "Household gates" bash "${SCRIPT_DIR}/skylight-household-gates.sh"
fi

if [[ "$QA" -eq 1 ]]; then
  echo ""
  echo "=== Optional QA (operator-local skills only) ==="
  QA_DIR="${OPENCLAW}/workspace/skills/nc-gcs-qa"
  if [[ -x "${QA_DIR}/run-qa-smoke.sh" ]]; then
    step "QA smoke" bash "${QA_DIR}/run-qa-smoke.sh"
  fi
fi

if [[ "$GATES" -eq 1 ]]; then
  echo ""
  echo "=== Final gates ==="
  bash "${SCRIPT_DIR}/openclaw-ai-gates.sh" --check
fi

echo ""
echo "CATCHUP_DONE morning=$MORNING household=$HOUSEHOLD qa=$QA gates=$GATES"
