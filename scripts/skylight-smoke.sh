#!/usr/bin/env bash
# Skylight API smoke test — exit 0 when family hub endpoints respond.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

FID="$SKYLIGHT_FRAME_ID"
TODAY=$(date +%F)
TOMORROW=$(date -d tomorrow +%F 2>/dev/null || python3 -c "from datetime import date,timedelta; print((date.today()+timedelta(days=1)).isoformat())")

fail() { echo "FAIL skylight-smoke: $*" >&2; exit 1; }
ok() { echo "OK  $*"; }

command -v skylight >/dev/null 2>&1 || fail "skylight CLI not in PATH (install: go install github.com/aarons22/skylight-tools/skylight@latest)"

AUTH="${SKYLIGHT_AUTHORIZATION:-}"
if [[ -z "$AUTH" && -n "${SKYLIGHT_RAW_TOKEN:-}" ]]; then
  AUTH="Bearer ${SKYLIGHT_RAW_TOKEN}"
fi
if [[ -z "$AUTH" ]]; then
  fail "SKYLIGHT_AUTHORIZATION not set (run skylight-login.sh)"
fi

API="${SKYLIGHT_API_URL:-https://app.ourskylight.com/api}"

code=$(curl -sS -o /tmp/skylight-smoke-cal.json -w '%{http_code}' \
  "${API}/frames/${FID}/calendar_events?date_min=${TODAY}&date_max=${TODAY}&timezone=${SKYLIGHT_TIMEZONE}" \
  -H "Authorization: ${AUTH}" -H "Accept: application/json" || echo 000)
[[ "$code" == "200" ]] && ok "calendar_events -> $code" || fail "calendar_events -> $code"

code=$(curl -sS -o /tmp/skylight-smoke-src.json -w '%{http_code}' \
  "${API}/frames/${FID}/source_calendars" \
  -H "Authorization: ${AUTH}" -H "Accept: application/json" || echo 000)
[[ "$code" == "200" ]] && ok "source_calendars -> $code" || fail "source_calendars -> $code"

skylight chores listChores --frame-id "$FID" --after "$TODAY" --before "$TOMORROW" --json >/dev/null \
  && ok "chores" || fail "chores"

skylight lists listLists --frame-id "$FID" --json >/dev/null \
  && ok "lists" || fail "lists"

skylight reward-points get --frame-id "$FID" --json >/dev/null \
  && ok "reward_points" || fail "reward_points"

skylight meals listCategories --frame-id "$FID" --json >/dev/null \
  && ok "meal_categories (Plus)" || fail "meal_categories"

skylight categories listCategories --frame-id "$FID" --json >/dev/null \
  && ok "categories" || fail "categories"

echo "skylight-smoke: all checks passed (frame=$FID)"
