#!/usr/bin/env bash
# Shell-direct NC-GCS flight/fleet/gateway monitor (no LLM).
# Usage: flight-event-monitor.sh
# Exit 0 + FLIGHT_MONITOR_OK when quiet; FLIGHT_ALERT_POSTED when alert sent.
# Large /api/flights payloads MUST go via temp files (never argv) — ARG_MAX footgun.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

OPS_ROOM="${SKYLIGHT_OPS_TALK_ROOM:?set SKYLIGHT_OPS_TALK_ROOM}"
GATEWAY_HEALTH_URL="${OPENCLAW_GATEWAY_HEALTH_URL:-http://127.0.0.1:18789/health}"
MAVLINK_GATEWAY_HEALTH_URL="${MAVLINK_GATEWAY_HEALTH_URL:-}"
NC_GCS_BASE="${NEXTCLOUD_URL%/}/apps/nc_gcs/api"

AUTH=(-u "${NEXTCLOUD_USER}:${NEXTCLOUD_PASS}")
HDRS=(-H "OCS-APIRequest: true" -H "Accept: application/json")

TMP=$(mktemp -d /tmp/flight-event-monitor.XXXXXX)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

curl -sS --max-time 20 "${AUTH[@]}" "${HDRS[@]}" "${NC_GCS_BASE}/flights" -o "$TMP/flights.json" 2>/dev/null \
  || echo '{}' >"$TMP/flights.json"
curl -sS --max-time 20 "${AUTH[@]}" "${HDRS[@]}" "${NC_GCS_BASE}/fleet/status" -o "$TMP/fleet.json" 2>/dev/null \
  || echo '{}' >"$TMP/fleet.json"
gw_resp="$(curl -sS -w $'\n__HTTP_CODE__%{http_code}' --max-time 15 "$GATEWAY_HEALTH_URL" 2>/dev/null || echo $'\n__HTTP_CODE__000')"
gw_code="${gw_resp##*$'\n__HTTP_CODE__'}"
printf '%s' "${gw_resp%$'\n__HTTP_CODE__'*}" >"$TMP/gw.json"
mavlink_code="000"
if [[ -n "$MAVLINK_GATEWAY_HEALTH_URL" ]]; then
  mavlink_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$MAVLINK_GATEWAY_HEALTH_URL" 2>/dev/null || echo 000)"
fi
printf '%s' "$gw_code" >"$TMP/gw_code"
printf '%s' "$mavlink_code" >"$TMP/mavlink_code"
export FEM_TMP="$TMP"

set +e
parse_out=$(python3 <<'PY'
import json
from pathlib import Path
base = Path(__import__("os").environ["FEM_TMP"])
try:
    flights = json.loads(base.joinpath("flights.json").read_text() or "{}")
    fleet = json.loads(base.joinpath("fleet.json").read_text() or "{}")
    gw_raw = base.joinpath("gw.json").read_text()
    gw_code = base.joinpath("gw_code").read_text().strip()
    mavlink_code = base.joinpath("mavlink_code").read_text().strip()
except Exception as e:
    print(f"FLIGHT_MONITOR_ERROR parse={e}", flush=True)
    raise SystemExit(2)
active = []
if isinstance(flights, list):
    active = [f for f in flights if str(f.get("status", "")).lower() == "active"]
elif isinstance(flights, dict):
    rows = flights.get("flights") or flights.get("data") or []
    active = [f for f in rows if str(f.get("status", "")).lower() == "active"]
online = 0
if isinstance(fleet, dict):
    vehicles = fleet.get("vehicles") or fleet.get("data") or []
    online = sum(1 for v in vehicles if v.get("online") or str(v.get("status", "")).lower() in ("online", "connected"))
gw_down = 0
healthy_status = {"ok", "healthy", "live", True}
if not str(gw_code).startswith("2"):
    gw_down = 1
elif gw_raw.strip():
    try:
        g = json.loads(gw_raw)
        if isinstance(g, dict):
            if g.get("ok") is True:
                pass
            elif g.get("status") not in healthy_status:
                gw_down = 1
    except json.JSONDecodeError:
        if "ok" not in gw_raw.lower() and "healthy" not in gw_raw.lower() and "live" not in gw_raw.lower():
            gw_down = 1
parts = []
if active:
    parts.append(f"{len(active)} active flight(s)")
if online:
    parts.append(f"{online} vehicle(s) online")
if gw_down:
    parts.append("openclaw gateway down")
if (active or online) and str(mavlink_code) not in ("200", "000") and not str(mavlink_code).startswith("2"):
    parts.append("mavlink gateway unreachable")
summary = "; ".join(parts) if parts else ""
print(f"{len(active)} {online} {gw_down} {summary}")
PY
)
prc=$?
set -e

if [[ $prc -ne 0 ]]; then
  echo "FLIGHT_MONITOR_ERROR python_rc=$prc"
  exit 1
fi

read -r active_count online_count gw_down summary <<<"$parse_out"

if [[ -z "${summary:-}" ]]; then
  echo "FLIGHT_MONITOR_OK active=${active_count:-0} online=${online_count:-0} gateway=up"
  exit 0
fi

MSG="FLIGHT EVENT: ${summary}."
bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$OPS_ROOM"
echo "FLIGHT_ALERT_POSTED summary=${summary}"
