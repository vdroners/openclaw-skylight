#!/usr/bin/env bash
# SEC-1/SEC-2: secret file permissions and leak checks.
set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ENV_D="${OPENCLAW_DIR}/.env.d"
FAIL=0

pass() { echo "Gate $1: PASS — $2"; }
fail() { echo "Gate $1: FAIL — $2"; FAIL=1; }

for f in "${ENV_D}"/*.secret; do
  [[ -f "$f" ]] || continue
  mode=$(stat -c '%a' "$f")
  [[ "$mode" == "600" ]] && pass SEC-1 "$(basename "$f") mode 600" || fail SEC-1 "$(basename "$f") mode $mode (expected 600)"
done

# SEC-2: blocklist grep in openclaw scripts/docs (not .env.d, not this script)
BLOCKED=0
while IFS= read -r f; do
  base=$(basename "$f")
  [[ "$base" == "validate-mail-secrets.sh" ]] && continue
  if grep -qE 'mnic|acoe|Wesley23' "$f" 2>/dev/null; then
    fail SEC-2 "possible secret leak in $f"
    BLOCKED=1
  fi
done < <(find "${OPENCLAW_DIR}/scripts" "${OPENCLAW_DIR}/docs" /media/4TB/openclaw-skylight -type f \( -name '*.sh' -o -name '*.md' -o -name '*.json' \) 2>/dev/null | grep -v mail-accounts.example | head -200)

[[ "$BLOCKED" -eq 0 ]] && pass SEC-2 "no secret substrings in scripts/docs"

exit $FAIL
