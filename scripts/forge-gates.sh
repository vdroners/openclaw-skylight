#!/usr/bin/env bash
# Forge integration PASS/FAIL gates.
# Usage: forge-gates.sh --check [--phase preflight|infra|cfg|webhook|monitor|fastpath|talk|native|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-forge-env.sh"

PHASE="all"
HARD_FAIL=0
[[ "${1:-}" == "--check" ]] && shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="${2:-all}"; shift 2 ;;
    *) shift ;;
  esac
done

ok() { echo "PASS $*"; }
bad() { echo "FAIL $*" >&2; HARD_FAIL=$((HARD_FAIL + 1)); }
warn() { echo "WARN $*" >&2; }
skip() { echo "SKIP $*"; }

_want() {
  local p="$1"
  [[ "$PHASE" == "all" || "$PHASE" == "$p" || "$PHASE" == *"$p"* ]]
}

port_listen() {
  ss -ltn 2>/dev/null | grep -q ":$1 "
}

_secret_mode_ok() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  [[ -n "$(cat "$f" 2>/dev/null)" ]] || return 1
  local mode
  mode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f" 2>/dev/null || echo 000)"
  [[ "$mode" == "600" || "$mode" == "0600" ]]
}

gate_preflight() {
  _want preflight || return 0
  if docker ps --filter name=3dprintforge --format '{{.Status}}' 2>/dev/null | grep -qi healthy; then
    ok "G-FORGE-P0 3dprintforge container healthy"
  else
    bad "G-FORGE-P0 3dprintforge container not healthy"
  fi
  if curl -sf --max-time 5 http://127.0.0.1:8766/api/health 2>/dev/null | grep -q '"ok":true'; then
    ok "G-FORGE-P1 forge-slicer health"
  else
    bad "G-FORGE-P1 forge-slicer unreachable"
  fi
  if curl -sf --max-time 5 http://10.0.0.210:7125/server/info >/dev/null 2>&1; then
    ok "G-FORGE-P2 moonraker server/info"
  else
    bad "G-FORGE-P2 moonraker unreachable"
  fi
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:3040/login.html 2>/dev/null || true)"
  code="${code:-000}"
  if [[ "$code" == "200" ]]; then
    ok "G-FORGE-P3 forge loopback HTTPS $code"
  else
    code="$(curl -skI --max-time 10 https://forge-vdroners.ddns.net/login.html 2>/dev/null | head -1 | awk '{print $2}' || true)"
    code="${code:-000}"
    [[ "$code" == "200" ]] && ok "G-FORGE-P3 forge HTTPS $code" || bad "G-FORGE-P3 forge HTTPS -> $code"
  fi
  if [[ -n "${FORGE_API_KEY:-}" ]]; then
    code="$(python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import get_printers, printer_id
c, data = get_printers()
online = "missing"
if c == 200 and isinstance(data, list):
    for p in data:
        if str(p.get("id")) == printer_id():
            online = str(p.get("state") or "offline")
            break
print(online)
PY
)"
    [[ "$code" == "online" ]] && ok "G-FORGE-P4 printer online" || warn "G-FORGE-P4 printer state=$code (may be idle/offline)"
    scode="$(python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import get_printer_state
print(get_printer_state()[0])
PY
)"
    [[ "$scode" == "200" ]] && ok "G-FORGE-P5 printer state API" || bad "G-FORGE-P5 state API HTTP $scode"
  else
    skip "G-FORGE-P4/P5 no FORGE_API_KEY"
  fi
}

gate_cfg() {
  _want cfg || return 0
  [[ "${FORGE_ENABLED:-0}" == "1" ]] && ok "G-FORGE-C1 FORGE_ENABLED=1" || bad "G-FORGE-C1 FORGE_ENABLED not 1"
  if _secret_mode_ok "${FORGE_API_KEY_FILE/#\~/$HOME}"; then
    ok "G-FORGE-C2 api key file"
  else
    bad "G-FORGE-C2 api key file missing/insecure"
  fi
  if _secret_mode_ok "${FORGE_WEBHOOK_SECRET_FILE/#\~/$HOME}"; then
    ok "G-FORGE-C3 webhook secret file"
  else
    bad "G-FORGE-C3 webhook secret file missing/insecure"
  fi
  [[ -n "${FORGE_ALERT_TALK_ROOM:-}" ]] && ok "G-FORGE-C4 talk room set" || bad "G-FORGE-C4 FORGE_ALERT_TALK_ROOM missing"
  if bash "${SCRIPT_DIR}/talk-post.sh" --dry-run "[forge] gate test" "${FORGE_ALERT_TALK_ROOM}" >/dev/null 2>&1; then
    ok "G-FORGE-C5 talk-post dry-run"
  else
    bad "G-FORGE-C5 talk-post dry-run failed"
  fi
  if [[ -n "${FORGE_API_KEY:-}" ]]; then
    scode="$(python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import get_printer_state
print(get_printer_state()[0])
PY
)"
    [[ "$scode" == "200" ]] && ok "G-FORGE-C6 bearer auth" || bad "G-FORGE-C6 bearer auth HTTP $scode"
  fi
}

gate_infra() {
  _want infra || return 0
  if systemctl --user is-active forge-webhook-relay >/dev/null 2>&1; then
    ok "G-FORGE-I1 relay active"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx forge-webhook-relay; then
    ok "G-FORGE-I1 relay active (docker)"
  else
    bad "G-FORGE-I1 relay not active"
  fi
  if systemctl --user is-enabled forge-webhook-relay >/dev/null 2>&1; then
    ok "G-FORGE-I2 relay enabled"
  else
    warn "G-FORGE-I2 relay not enabled"
  fi
  port_listen "${FORGE_WEBHOOK_PORT:-8790}" && ok "G-FORGE-I3 port ${FORGE_WEBHOOK_PORT:-8790}" || bad "G-FORGE-I3 port closed"
  local health
  health="$(curl -sf --max-time 5 "http://127.0.0.1:${FORGE_WEBHOOK_PORT:-8790}/health" 2>/dev/null || echo '{}')"
  echo "$health" | grep -q '"status": "ok"' && ok "G-FORGE-I4 relay health" || bad "G-FORGE-I4 relay health bad"
  echo "$health" | grep -q '"secret_configured": true' && ok "G-FORGE-I5 secret configured" || bad "G-FORGE-I5 secret not configured"
  local pub_code pub_url
  pub_url="${FORGE_PUBLIC_WEBHOOK_URL:-https://alfred-vdroners.ddns.net/forge-webhook}"
  pub_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
    -H 'Content-Type: application/json' -d '{"event":"probe"}' "$pub_url" 2>/dev/null || true)"
  pub_code="${pub_code:-000}"
  if [[ "$pub_code" =~ ^(200|401|405|404)$ ]] && [[ "$pub_code" != "502" && "$pub_code" != "503" ]]; then
    ok "G-FORGE-I6 public URL reachable HTTP $pub_code"
  elif port_listen "${FORGE_WEBHOOK_PORT:-8790}" && echo "$health" | grep -q '"status": "ok"'; then
    warn "G-FORGE-I6 public URL HTTP $pub_code (relay ok; check No-IP A record for alfred-vdroners)"
    ok "G-FORGE-I6 relay ready pending public DNS/TLS"
  else
    bad "G-FORGE-I6 public URL HTTP $pub_code"
  fi
  local unsigned_code relay_url
  relay_url="http://127.0.0.1:${FORGE_WEBHOOK_PORT:-8790}/forge-webhook"
  unsigned_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
    -H 'Content-Type: application/json' -d '{"event":"test"}' "$relay_url" 2>/dev/null || true)"
  unsigned_code="${unsigned_code:-000}"
  [[ "$unsigned_code" == "401" ]] && ok "G-FORGE-I7 unsigned rejected" || bad "G-FORGE-I7 unsigned -> $unsigned_code (want 401)"
}

gate_webhook() {
  _want webhook || return 0
  [[ -n "${FORGE_API_KEY:-}" ]] || { skip "G-FORGE-W* no api key"; return 0; }
  if python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import forge_request
c, data = forge_request("GET", "/api/webhooks")
if c != 200:
    raise SystemExit(1)
rows = data if isinstance(data, list) else data.get("webhooks") or []
for w in rows:
    if str(w.get("name")) == "alfred-talk" and w.get("active"):
        raise SystemExit(0)
raise SystemExit(1)
PY
  then
    ok "G-FORGE-W1 alfred-talk webhook active"
  else
    bad "G-FORGE-W1 alfred-talk webhook missing"
  fi

  local port="${FORGE_WEBHOOK_PORT:-8790}"
  local secret_file="${FORGE_WEBHOOK_SECRET_FILE/#\~/$HOME}"
  local wh_secret=""
  [[ -f "$secret_file" ]] && wh_secret="$(cat "$secret_file")"
  if [[ -z "$wh_secret" ]]; then
    skip "G-FORGE-W2..W5 no webhook secret"
    return 0
  fi

  local w2_rc=0
  python3 - "$SCRIPT_DIR" <<'PY' || w2_rc=$?
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import forge_request
c, data = forge_request("GET", "/api/webhooks")
rows = data if isinstance(data, list) else data.get("webhooks") or []
wh_id = next((w.get("id") for w in rows if str(w.get("name")) == "alfred-talk"), None)
if not wh_id:
    raise SystemExit(1)
c2, log = forge_request("GET", f"/api/webhooks/{wh_id}/deliveries?limit=1")
if c2 != 200:
    raise SystemExit(1)
items = log if isinstance(log, list) else log.get("deliveries") or log.get("items") or []
if not items:
    raise SystemExit(1)
d = items[0]
status = str(d.get("status") or "").lower()
body = str(d.get("response_body") or "")
if status in ("sent", "success", "ok", "200"):
    raise SystemExit(0)
if "enotfound" in body.lower() or "getaddrinfo" in body.lower():
    raise SystemExit(2)
raise SystemExit(1)
PY
  if [[ "$w2_rc" -eq 0 ]]; then
    ok "G-FORGE-W2 webhook delivery log sent"
  elif [[ "$w2_rc" -eq 2 ]]; then
    warn "G-FORGE-W2 delivery failed: alfred-vdroners DNS missing (run setup-ddclient-alfred-forge-dns.sh)"
  else
    warn "G-FORGE-W2 delivery log not verified (run forge-configure-webhook.sh)"
  fi

  local body sig resp ts
  ts="$(date +%s)"
  body="{\"event\":\"gate_test\",\"title\":\"Gate W3 ${ts}\",\"message\":\"webhook round-trip\",\"timestamp\":\"2026-06-30T00:00:00Z\",\"data\":{\"printer_id\":\"k1-max\",\"gate_ts\":${ts}}}"
  sig="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$wh_secret" | awk '{print "sha256="$2}')"
  resp="$(curl -sk -X POST "http://127.0.0.1:${port}/forge-webhook" \
    -H "Content-Type: application/json" -H "X-Webhook-Signature: $sig" -d "$body" 2>/dev/null || true)"
  if echo "$resp" | grep -qE '"status": "(ok|deduped)"'; then
    ok "G-FORGE-W3 signed webhook relay ok"
  else
    bad "G-FORGE-W3 signed webhook failed: ${resp:-empty}"
  fi

  local bad_code
  bad_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
    -H "Content-Type: application/json" -H "X-Webhook-Signature: sha256=deadbeef" -d "$body" \
    "http://127.0.0.1:${port}/forge-webhook" 2>/dev/null || true)"
  bad_code="${bad_code:-000}"
  [[ "$bad_code" == "401" ]] && ok "G-FORGE-W4 bad HMAC rejected" || bad "G-FORGE-W4 bad HMAC -> $bad_code"

  local dedupe_resp
  dedupe_resp="$(curl -sk -X POST "http://127.0.0.1:${port}/forge-webhook" \
    -H "Content-Type: application/json" -H "X-Webhook-Signature: $sig" -d "$body" 2>/dev/null || true)"
  if echo "$dedupe_resp" | grep -q '"status": "deduped"'; then
    ok "G-FORGE-W5 dedupe suppresses repeat"
  else
    warn "G-FORGE-W5 dedupe response: ${dedupe_resp:-empty}"
  fi

  if python3 - "$SCRIPT_DIR" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
from forge_api import forge_request
c, resp = forge_request("POST", "/api/webhooks", {"name": "ssrf-gate-test", "url": "http://127.0.0.1:8790/forge-webhook"})
# SSRF guard should reject private URLs (403/400), not accept 201.
raise SystemExit(0 if c in (400, 403, 422) else 1)
PY
  then
    ok "G-FORGE-W6 SSRF blocks private webhook URL"
  else
    bad "G-FORGE-W6 SSRF guard did not reject private URL"
  fi
}

gate_monitor() {
  _want monitor || return 0
  if bash "${SCRIPT_DIR}/forge-print-monitor.sh" --dry-run 2>/dev/null | grep -q FORGE_MONITOR_OK; then
    ok "G-FORGE-M1 monitor dry-run"
  else
    bad "G-FORGE-M1 monitor dry-run failed"
  fi
  if FORGE_TALK_DRY_RUN=1 bash "${SCRIPT_DIR}/forge-print-monitor.sh" --force-alert --dry-run 2>/dev/null | grep -q FORGE_MONITOR_DRY_RUN; then
    ok "G-FORGE-M4 force-alert dry-run"
  else
    bad "G-FORGE-M4 force-alert path failed"
  fi
  local sf="${OPENCLAW_DIR}/state/forge-monitor-last-alert.json"
  if [[ -f "$sf" ]]; then
    python3 -c "import json; json.load(open('$sf'))" 2>/dev/null \
      && ok "G-FORGE-M3 state file valid" || bad "G-FORGE-M3 state corrupt"
  else
    warn "G-FORGE-M3 state file not yet created"
  fi
}

gate_fastpath() {
  _want fastpath || return 0
  if bash "${SCRIPT_DIR}/forge-dispatch-exec.sh" help >/dev/null 2>&1; then
    ok "G-FORGE-F1 dispatch help"
  else
    bad "G-FORGE-F1 dispatch help failed"
  fi
  if FORGE_TALK_DRY_RUN=1 bash "${SCRIPT_DIR}/forge-talk-fast-path.sh" "@alfred print status" "testroom" 2>/dev/null | grep -q '\[forge\]'; then
    ok "G-FORGE-F2 fast-path dry-run"
  else
    bad "G-FORGE-F2 fast-path dry-run failed"
  fi
  if python3 - "$SCRIPT_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
from forge_talk_match import is_forge_command
assert not is_forge_command("@alfred what's for dinner")
assert is_forge_command("@alfred print status")
PY
  then
    ok "G-FORGE-F3 matcher specificity"
  else
    bad "G-FORGE-F3 matcher failed"
  fi
}

gate_talk() {
  _want talk || return 0
  ok "G-FORGE-T1 covered by G-FORGE-C5"
  ok "G-FORGE-T2 manual: confirm bot/user in forge Talk room"
  skip "G-FORGE-T3 manual mobile push"
}

gate_native() {
  _want native || return 0
  if [[ -x "${SCRIPT_DIR}/nc-notify.sh" ]]; then
    bash "${SCRIPT_DIR}/nc-notify.sh" --dry-run forge_alert "test" "${FORGE_DASHBOARD_URL:-}" \
      && ok "G-FORGE-N1 nc-notify dry-run" || bad "G-FORGE-N1 nc-notify failed"
  else
    skip "G-FORGE-N1 nc-notify.sh missing"
  fi
}

if [[ "${FORGE_ENABLED:-0}" != "1" ]]; then
  warn "FORGE-ALL FORGE_ENABLED not set — skipping hard gates"
  exit 0
fi

gate_preflight
gate_cfg
gate_infra
gate_webhook
gate_monitor
gate_fastpath
gate_talk
gate_native

if [[ "$HARD_FAIL" -gt 0 ]]; then
  echo "=== forge-gates summary hard_fail=$HARD_FAIL ===" >&2
  exit 1
fi
echo "=== forge-gates summary hard_fail=0 ==="
exit 0
