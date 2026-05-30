#!/usr/bin/env bash
# Mail gate aggregator. Usage: mail-gates.sh [--check]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/load-skylight-env.sh" 2>/dev/null || true

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
FAIL=0
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

pass() { echo "Gate $1: PASS — $2"; }
fail() { echo "Gate $1: FAIL — $2"; FAIL=1; }
warn() { echo "Gate $1: WARN — $2"; }

bash "${SCRIPT_DIR}/validate-mail-secrets.sh" && pass SEC "validate-mail-secrets" || FAIL=1
bash "${SCRIPT_DIR}/validate-mail-accounts.sh" || FAIL=1

SYNC_MODE="--check"
[[ "$CHECK_ONLY" -eq 0 ]] && SYNC_MODE="--apply"
if bash "${SCRIPT_DIR}/nc-mail-sync-accounts.sh" $SYNC_MODE >/tmp/mail-sync.out 2>&1; then
  grep -E 'Gate E1-|Gate MAIL-STATE|Gate E1-SYNC' /tmp/mail-sync.out | while read -r line; do echo "$line"; done
else
  cat /tmp/mail-sync.out >&2
  fail E1 "nc-mail-sync-accounts failed"
fi

# MAIL-CSRF probe
AUTH=(-u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS")
HDRS=(-H "Accept: application/json" -H "OCS-APIREQUEST: true")
if curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" | grep -qE '^[45]'; then
  if curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" -H "OCS-APIREQUEST: true" "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts" | grep -qE '^2'; then
    pass MAIL-CSRF "OCS-APIREQUEST header required"
  else
    fail MAIL-CSRF "API unreachable with header"
  fi
else
  pass MAIL-CSRF "accounts API ok"
fi

# MAIL-ROUTE: env vs state
STATE="${OPENCLAW_DIR}/state/mail-account-ids.json"
if [[ -f "$STATE" ]]; then
  python3 - "$STATE" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1]))
env_map = {
    "family": os.environ.get("FAMILY_MAIL_ACCOUNT_ID", ""),
    "ops": os.environ.get("OPS_MAIL_ACCOUNT_ID", ""),
    "work": os.environ.get("WORK_MAIL_ACCOUNT_ID", ""),
}
ok = True
for role, info in state.get("accounts", {}).items():
    sid = str(info.get("id", ""))
    eid = str(env_map.get(role, ""))
    if eid and sid and eid != sid:
        print(f"Gate MAIL-ROUTE: FAIL — {role} env={eid} state={sid}", file=sys.stderr)
        ok = False
    elif sid:
        print(f"Gate MAIL-ROUTE: PASS — {role} id={sid}")
if not state.get("accounts"):
    print("Gate MAIL-ROUTE: FAIL — empty state", file=sys.stderr)
    ok = False
sys.exit(0 if ok else 1)
PY
  [[ $? -eq 0 ]] || FAIL=1
else
  fail MAIL-ROUTE "missing state/mail-account-ids.json"
fi

# MAIL-SMTP-OPS / MAIL-SMTP-WORK: account detail includes smtpHost
for role_env in "ops:OPS_MAIL_ACCOUNT_ID" "work:WORK_MAIL_ACCOUNT_ID"; do
  role="${role_env%%:*}"
  env_key="${role_env#*:}"
  aid="${!env_key:-}"
  gate="MAIL-SMTP-${role^^}"
  [[ -n "$aid" ]] || { fail "$gate" "missing $env_key"; continue; }
  smtp=$(curl -sS "${AUTH[@]}" "${HDRS[@]}" -H "Accept: application/json" \
    "$NEXTCLOUD_URL/index.php/apps/mail/api/accounts/$aid" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('smtpHost') or d.get('data',{}).get('smtpHost') or ''))" 2>/dev/null || echo "")
  if [[ -n "$smtp" ]]; then
    pass "$gate" "smtpHost=$smtp id=$aid"
  else
    fail "$gate" "no SMTP config on account $aid"
  fi
done

# E2 family enrich (if audit exists)
LOG_DIR="${OPENCLAW_DIR}/logs"
if ls "${LOG_DIR}"/skylight-household-audit-*.json >/dev/null 2>&1; then
  E2_START=$(date +%s)
  if timeout 60 bash "${SCRIPT_DIR}/skylight-email-enrich-scan.sh" >/tmp/mail-e2.out 2>&1; then
    pass E2 "$(grep 'Gate E2' /tmp/mail-e2.out | tail -1)"
    ACCT=$(grep 'Gate E2' /tmp/mail-e2.out | grep -oE 'account=[0-9]+' | cut -d= -f2)
    [[ "${FAMILY_MAIL_ACCOUNT_ID:-}" == "$ACCT" || -z "${FAMILY_MAIL_ACCOUNT_ID:-}" ]] && pass E2-ISOLATE "family account $ACCT" || fail E2-ISOLATE "used account $ACCT not family ${FAMILY_MAIL_ACCOUNT_ID}"
  else
    warn E2 "$(tail -1 /tmp/mail-e2.out)"
  fi
  E2_EL=$(( $(date +%s) - E2_START ))
  [[ "$E2_EL" -lt 60 ]] && pass E2-S "${E2_EL}s" || fail E2-S "${E2_EL}s"
fi

# DIGEST-OPS dry-run
if bash "${SCRIPT_DIR}/email-daily-digest-post.sh" --dry-run >/tmp/mail-digest.out 2>&1; then
  pass DIGEST-OPS "$(grep DIGEST /tmp/mail-digest.out | tail -1 || echo ok)"
else
  fail DIGEST-OPS "$(tail -1 /tmp/mail-digest.out)"
fi

# URGENT-SCAN
if bash "${SCRIPT_DIR}/email-urgent-scan.sh" >/tmp/mail-urgent.out 2>&1; then
  python3 -c "import json; json.load(open('/tmp/mail-urgent.out'))" 2>/dev/null && pass URGENT-SCAN "$(head -1 /tmp/mail-urgent.out | cut -c1-80)" || fail URGENT-SCAN "invalid JSON"
else
  fail URGENT-SCAN "$(tail -1 /tmp/mail-urgent.out)"
fi

echo ""
echo "=== Mail gate summary (hard_fail=$FAIL) ==="
exit $FAIL
