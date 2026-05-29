#!/usr/bin/env bash
# Weekly Skylight household audit — diff vs prior, post Family Hub (+ ops on FAIL).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}/logs"
FAMILY_ROOM="${SKYLIGHT_FAMILY_TALK_ROOM:-}"
OPS_ROOM="${SKYLIGHT_OPS_TALK_ROOM:-}"
STAMP=$(date +%F)

bash "${SCRIPT_DIR}/skylight-audit.sh" || AUDIT_RC=$?
AUDIT_RC=${AUDIT_RC:-0}
bash "${SCRIPT_DIR}/skylight-household-defer-stale.sh" 2>/dev/null || true
CUR="${LOG_DIR}/skylight-audit-${STAMP}.json"

PRIOR="$(ls -1t "${LOG_DIR}"/skylight-audit-*.json 2>/dev/null | sed -n '2p' || true)"

SUMMARY="$(python3 - "$CUR" "$PRIOR" <<'PY'
import json, sys
from pathlib import Path

cur_path = Path(sys.argv[1])
prior_path = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None

def load(p):
    if not p or not Path(p).is_file():
        return {}
    return json.loads(Path(p).read_text())

cur = load(cur_path)
prior = load(prior_path)
gates = cur.get("gates") or {}
fail_gates = [k for k, v in sorted(gates.items()) if not v.get("pass")]

lines = [f"Weekly Skylight audit — {cur_path.stem.replace('skylight-audit-', '')}", ""]
if fail_gates:
    lines.append(f"FAIL gates: {', '.join(fail_gates)}")
else:
    lines.append("All gates PASS")

def gval(key, sub):
    return (gates.get(key) or {}).get(sub)

lines += [
    f"Chore series: {(gates.get('V-4') or {}).get('series_count', '?')}",
    f"Task box: {(gates.get('V-5') or {}).get('task_box_count', '?')}",
    f"Grocery pending/completed: {gval('V-6','pending')}/{gval('V-6','completed')}",
    f"Recipes: {(gates.get('V-7') or {}).get('recipe_count', '?')}",
    f"V-11 probe: {'PASS' if (gates.get('V-11') or {}).get('pass') else 'FAIL'}",
    f"V-12 pilot breads: {'PASS' if (gates.get('V-12') or {}).get('pass') else 'FAIL'}",
]

if prior_path:
    pg = prior.get("gates") or {}
    deltas = []
    for key in ("V-5", "V-6", "V-7"):
        for sub in ("task_box_count", "pending", "completed", "recipe_count"):
            a = (gates.get(key) or {}).get(sub)
            b = (pg.get(key) or {}).get(sub)
            if a is not None and b is not None and a != b:
                deltas.append(f"{key}.{sub}: {b}→{a}")
    if deltas:
        lines.append("")
        lines.append("Changes vs prior audit:")
        for d in deltas[:8]:
            lines.append(f"- {d}")

dupes = (gates.get("V-7") or {}).get("duplicate_titles") or []
if dupes:
    lines.append(f"Duplicate recipe titles: {', '.join(dupes[:5])}")

print("\n".join(lines))
PY
)"

bash "${SCRIPT_DIR}/talk-post.sh" "$SUMMARY" "$FAMILY_ROOM"

if [[ $AUDIT_RC -ne 0 ]] || echo "$SUMMARY" | grep -q '^FAIL gates:'; then
  bash "${SCRIPT_DIR}/talk-post.sh" "Skylight weekly audit needs attention. See Family Hub summary." "$OPS_ROOM"
fi

# Idempotent grocery completed purge if any completed items linger
if [[ -x "${SCRIPT_DIR}/skylight-cleanup-apply.sh" ]]; then
  COMPLETED="$(python3 -c "import json; d=json.load(open('$CUR')); print((d.get('gates',{}).get('V-6',{}).get('completed',0)))" 2>/dev/null || echo 0)"
  if [[ "${COMPLETED:-0}" -gt 0 ]]; then
    SKYLIGHT_CLEANUP_PHASE=D bash "${SCRIPT_DIR}/skylight-cleanup-apply.sh" 2>/dev/null || true
  fi
fi

echo "SKYLIGHT_AUDIT_WEEKLY_POSTED audit_rc=${AUDIT_RC}"
