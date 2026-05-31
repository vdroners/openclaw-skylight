#!/usr/bin/env bash
# Shell-direct NC-GCS flight/fleet/gateway monitor (no LLM).
# Usage: flight-event-monitor.sh
# Exit 0 + FLIGHT_MONITOR_OK when quiet; FLIGHT_ALERT_POSTED when alert sent.
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

flights="$(curl -sS --max-time 20 "${AUTH[@]}" "${HDRS[@]}" "${NC_GCS_BASE}/flights" 2>/dev/null || echo '{}')"
fleet="$(curl -sS --max-time 20 "${AUTH[@]}" "${HDRS[@]}" "${NC_GCS_BASE}/fleet/status" 2>/dev/null || echo '{}')"
gw_resp="$(curl -sS -w $'\n__HTTP_CODE__%{http_code}' --max-time 15 "$GATEWAY_HEALTH_URL" 2>/dev/null || echo $'\n__HTTP_CODE__000')"
gw_code="${gw_resp##*$'\n__HTTP_CODE__'}"
gw="${gw_resp%$'\n__HTTP_CODE__'*}"
mavlink_code="000"
if [[ -n "$MAVLINK_GATEWAY_HEALTH_URL" ]]; then
  mavlink_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$MAVLINK_GATEWAY_HEALTH_URL" 2>/dev/null || echo 000)"
fi

read -r active_count online_count gw_down summary <<<"$(python3 - "$flights" "$fleet" "$gw" "$gw_code" "$mavlink_code" <<'PY'
import json, sys
flights = json.loads(sys.argv[1] or "{}")
fleet = json.loads(sys.argv[2] or "{}")
gw_raw = sys.argv[3]
gw_code = sys.argv[4]
mavlink_code = sys.argv[5]
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
# Mavlink gateway is optional from homelab; only note when fleet activity exists.
if (active or online) and str(mavlink_code) not in ("200", "000") and not str(mavlink_code).startswith("2"):
    parts.append("mavlink gateway unreachable")
summary = "; ".join(parts) if parts else ""
print(len(active), online, gw_down, summary)
PY
)"

if [[ -z "$summary" ]]; then
  echo "FLIGHT_MONITOR_OK active=0 online=${online_count} gateway=up"
  exit 0
fi

MSG="FLIGHT EVENT: ${summary}."
bash "${SCRIPT_DIR}/talk-post.sh" "$MSG" "$OPS_ROOM"
echo "FLIGHT_ALERT_POSTED summary=${summary}"
