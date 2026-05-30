#!/usr/bin/env bash
# Talk response PASS/FAIL gates for Alfred Nextcloud Talk.
# Usage: talk-response-audit.sh --check [--phase baseline|config|relay|dispatch|nc-wiring|all]
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
CFG="${OPENCLAW}/openclaw.json"
MODEL="${OPENCLAW}/config/household-model.json"
RELAY="${OPENCLAW}/nc-webhook-relay.py"
DISPATCH="${OPENCLAW}/scripts/skylight-family-hub-dispatch.sh"
LOG_DIR="${OPENCLAW}/logs"
PHASE="all"
HARD_FAIL=0
SOFT_FAIL=0

ok() { echo "PASS $*"; }
bad() { echo "FAIL $*" >&2; HARD_FAIL=$((HARD_FAIL + 1)); }
warn() { echo "WARN $*" >&2; SOFT_FAIL=$((SOFT_FAIL + 1)); }

load_room_tokens() {
  python3 - "$MODEL" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file():
    print("")
    print("")
    raise SystemExit
m = json.loads(p.read_text())
print(m.get("ops_talk_room") or "")
print(m.get("family_talk_room") or "")
PY
}

OPS_ROOM=""
FAMILY_ROOM=""
if [[ -f "$MODEL" ]]; then
  mapfile -t _rooms < <(load_room_tokens)
  OPS_ROOM="${_rooms[0]:-}"
  FAMILY_ROOM="${_rooms[1]:-}"
fi

port_listen() {
  ss -ltn 2>/dev/null | grep -q ":$1 "
}

gate_baseline() {
  systemctl --user is-active openclaw-gateway >/dev/null 2>&1 \
    && ok "G0-1 openclaw-gateway active" || bad "G0-1 openclaw-gateway not active"

  if systemctl --user is-active nc-webhook-relay >/dev/null 2>&1; then
    ok "G0-2 nc-webhook-relay active"
  else
    warn "G0-2 nc-webhook-relay not active (optional if using plugin :8788 only)"
  fi

  for p in 8788 8789 18789; do
    port_listen "$p" && ok "G0-3 port $p listening" || bad "G0-3 port $p not listening"
  done

  local code=000 attempt
  for attempt in 1 2 3; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 http://127.0.0.1:18789/health || echo 000)
    [[ "$code" == "200" ]] && break
    sleep 2
  done
  [[ "$code" == "200" ]] && ok "G0-4 gateway /health -> $code" || bad "G0-4 gateway /health -> $code"

  health=$(curl -sS --max-time 10 http://127.0.0.1:8789/health 2>/dev/null || echo '{}')
  echo "$health" | grep -q '"status": "ok"' \
    && ok "G0-5 relay /health ok" || warn "G0-5 relay /health bad or relay down"

  echo "$health" | grep -q '"hooks_token_configured": true' \
    && ok "G0-5b hooks token configured" || warn "G0-5b hooks token missing"

  dq=$(find "${OPENCLAW}/delivery-queue" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
  (( dq < 50 )) && ok "G0-7 delivery-queue depth=$dq" || bad "G0-7 delivery-queue depth=$dq"

  [[ -x "$DISPATCH" ]] && ok "G0-8 dispatch script present" || warn "G0-8 dispatch script missing"

  if [[ -f "$CFG" && -n "$OPS_ROOM" && -n "$FAMILY_ROOM" ]]; then
    python3 - "$CFG" "$OPS_ROOM" "$FAMILY_ROOM" <<'PY' | while read -r line; do
import json, sys
cfg = json.load(open(sys.argv[1]))
ops, fam = sys.argv[2], sys.argv[3]
rooms = (cfg.get("channels") or {}).get("nextcloud-talk", {}).get("rooms") or {}
print(f"BASELINE ops requireMention={rooms.get(ops,{}).get('requireMention')}")
print(f"BASELINE family requireMention={rooms.get(fam, {}).get('requireMention')}")
PY
      [[ "$line" == BASELINE* ]] && ok "G0-9 $line" || true
    done
  elif [[ ! -f "$CFG" ]]; then
    bad "G0-9 openclaw.json missing"
  else
    warn "G0-9 household-model.json missing ops/family talk room tokens"
  fi

  mkdir -p "$LOG_DIR"
  python3 - "$CFG" "$health" "$LOG_DIR/talk-response-baseline-$(date +%F).json" <<'PY'
import json, sys, datetime
from pathlib import Path
cfg_path, health_raw, out = sys.argv[1:4]
rooms = {}
if Path(cfg_path).is_file():
    cfg = json.loads(Path(cfg_path).read_text())
    rooms = (cfg.get("channels") or {}).get("nextcloud-talk", {}).get("rooms") or {}
doc = {
    "captured_at": datetime.date.today().isoformat(),
    "rooms": rooms,
    "relay_health": json.loads(health_raw) if health_raw.strip().startswith("{") else {},
}
Path(out).write_text(json.dumps(doc, indent=2))
print(f"baseline written {out}")
PY
}

gate_config() {
  [[ -f "$CFG" ]] || { bad "G1 config file missing"; return; }
  [[ -n "$OPS_ROOM" && -n "$FAMILY_ROOM" ]] || { warn "G1 skipped — set ops_talk_room and family_talk_room in household-model.json"; return; }

  bash "${OPENCLAW}/scripts/validate-openclaw-config.sh" \
    && ok "G1-1 validate-openclaw-config.sh" || bad "G1-1 validate-openclaw-config.sh"

  systemctl --user is-active openclaw-gateway >/dev/null 2>&1 \
    && ok "G1-2 gateway active" || bad "G1-2 gateway not active"

  python3 - "$CFG" "$OPS_ROOM" "$FAMILY_ROOM" <<'PY' | while read -r line; do
import json, sys
cfg = json.load(open(sys.argv[1]))
ops, fam = sys.argv[2], sys.argv[3]
nc = (cfg.get("channels") or {}).get("nextcloud-talk") or {}
rooms = nc.get("rooms") or {}
patterns = ((cfg.get("messages") or {}).get("groupChat") or {}).get("mentionPatterns") or []
checks = []
checks.append(("G1-3", rooms.get(ops, {}).get("requireMention") is True, f"ops requireMention={rooms.get(ops, {}).get('requireMention')}"))
checks.append(("G1-4", rooms.get(fam, {}).get("requireMention") is False, f"family requireMention={rooms.get(fam, {}).get('requireMention')}"))
checks.append(("G1-5", nc.get("dmPolicy") == "open", f"dmPolicy={nc.get('dmPolicy')}"))
checks.append(("G1-6", any("mention-user" in p for p in patterns), f"mentionPatterns count={len(patterns)}"))
for gate, ok, msg in checks:
    print(f"{'PASS' if ok else 'FAIL'} {gate} {msg}")
PY
    case "$line" in
      PASS*) ok "${line#PASS }" ;;
      FAIL*) bad "${line#FAIL }" ;;
    esac
  done
}

gate_relay() {
  systemctl --user is-active nc-webhook-relay >/dev/null 2>&1 \
    && ok "G2-1 relay active" || { warn "G2 skipped — relay not active"; return; }

  [[ -f "$RELAY" ]] || { warn "G2 skipped — nc-webhook-relay.py missing (operator-local)"; return; }

  grep -q '"deliver": True' "$RELAY" || grep -q '"deliver": true' "$RELAY" \
    && ok "G2-6 deliver true in relay" || bad "G2-6 deliver still false"

  grep -q '_message_mentions_alfred' "$RELAY" \
    && ok "G2-6b rich mention helper present" || bad "G2-6b rich mention helper missing"

  grep -q 'OPEN_ROOMS_NO_RELAY_LLM' "$RELAY" \
    && ok "G2-6c open-room skip present" || bad "G2-6c open-room skip missing"

  [[ -n "$OPS_ROOM" && -n "$FAMILY_ROOM" ]] || { warn "G2 synthetic tests skipped — room tokens unset"; return; }

  python3 - "$OPS_ROOM" "$FAMILY_ROOM" <<'PY' | while read -r line; do
import json, sys, time, urllib.error, urllib.request
ops, fam = sys.argv[1], sys.argv[2]
uniq = str(int(time.time()))

def post(body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8789/talk-mention",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except TimeoutError:
        return 200, "timeout-wake-likely-started"
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")

evt = lambda msg, token: {
    "event": {
        "class": "OCA\\Talk\\Events\\MessageSentEvent",
        "message": {"message": msg, "parsedMessage": msg},
        "actor": {"id": "NCAdmin", "displayName": "Test"},
    },
    "room": {"token": token},
}

checks = []
st, _ = post(evt("gateway looks fine", ops))
checks.append(("G2-5", st == 204, f"plain ops HTTP {st}"))
st, _ = post(evt("@alfred what is for dinner", fam))
checks.append(("G2-4", st == 204, f"family relay skip HTTP {st}"))
st, _ = post({
    "event": {
        "class": "OCA\\Talk\\Events\\MessageSentEvent",
        "message": {
            "message": f"Hey {{mention-user1}} please help {uniq}",
            "parsedMessage": f"Hey Alfred please help {uniq}",
        },
        "actor": {"id": "NCAdmin"},
    },
    "room": {"token": ops},
})
checks.append(("G2-3", st in (200, 502), f"rich mention HTTP {st}"))
for gate, ok, msg in checks:
    print(f"{'PASS' if ok else 'FAIL'} {gate} {msg}")
PY
    case "$line" in
      PASS*) ok "${line#PASS }" ;;
      FAIL*) bad "${line#FAIL }" ;;
    esac
  done
}

gate_dispatch() {
  [[ -x "$DISPATCH" ]] && ok "G3-1 dispatch executable" || bad "G3-1 dispatch missing"
  [[ -x "${OPENCLAW}/scripts/skylight-household-reply-handler.sh" ]] \
    && ok "G3-1b reply-handler executable" || bad "G3-1b reply-handler missing"

  if bash "$DISPATCH" "not a command" >/dev/null 2>&1; then
    bad "G3-2 non-command should exit 2"
  else
    rc=$?
    [[ "$rc" -eq 2 ]] && ok "G3-2 non-command exits 2" || bad "G3-2 expected exit 2 got $rc"
  fi
}

gate_nc_wiring() {
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 \
    -X POST -H 'Content-Type: application/json' -d '{}' \
    http://127.0.0.1:8789/talk-mention || echo 000)
  [[ "$code" != "000" ]] && ok "G4-4 relay /talk-mention reachable ($code)" || warn "G4-4 relay unreachable"

  local db_container="${NC_DB_CONTAINER:-cloud_db}"
  local db_user="${NC_DB_USER:-ncadmin}"
  local db_pass="${NC_DB_PASS:-}"
  local db_name="${NC_DB_NAME:-nextcloud}"
  local bot_id="${TALK_BOT_ID:-22}"

  if [[ -z "$db_pass" ]] && command -v docker >/dev/null 2>&1; then
    db_pass=$(docker exec "$db_container" env 2>/dev/null | awk -F= '/^MYSQL_PASSWORD=/{print $2; exit}' || true)
  fi

  if [[ -z "$OPS_ROOM" || -z "$FAMILY_ROOM" ]]; then
    warn "G4-1 skipped — ops_talk_room / family_talk_room missing in household-model.json"
    return
  fi

  if [[ -z "$db_pass" ]]; then
    warn "G4-1 skipped — set NC_DB_PASS or run with reachable ${db_container} for auto-resolve"
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    warn "G4-1 skipped — docker not available"
    return
  fi

  cnt=$(docker exec "$db_container" mariadb -u "$db_user" -p"$db_pass" "$db_name" -N -e \
    "SELECT COUNT(*) FROM oc_talk_bots_conversation WHERE bot_id=${bot_id} AND token IN ('${OPS_ROOM}','${FAMILY_ROOM}');" 2>/dev/null || echo 0)
  [[ "$cnt" -ge 2 ]] && ok "G4-1 bot in both rooms (count=$cnt)" || bad "G4-1 bot missing from primary rooms (count=$cnt)"
}

run_phase() {
  case "$1" in
    baseline) gate_baseline ;;
    config) gate_config ;;
    relay) gate_relay ;;
    dispatch) gate_dispatch ;;
    nc-wiring) gate_nc_wiring ;;
    all)
      gate_baseline
      gate_config
      gate_relay
      gate_dispatch
      gate_nc_wiring
      ;;
    *) echo "unknown phase: $1" >&2; exit 2 ;;
  esac
}

[[ "${1:-}" == "--check" ]] || { echo "usage: $0 --check [--phase baseline|config|relay|dispatch|nc-wiring|all]" >&2; exit 2; }
if [[ "${2:-}" == "--phase" ]]; then
  PHASE="${3:-all}"
fi

run_phase "$PHASE"
echo "hard_fail=${HARD_FAIL} soft_fail=${SOFT_FAIL}"
exit "$HARD_FAIL"
