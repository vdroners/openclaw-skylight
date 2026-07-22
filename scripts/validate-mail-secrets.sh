#!/usr/bin/env bash
# SEC-1/SEC-2: secret file permissions and repo scrub check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${OPENCLAW_SKYLIGHT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
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

if [[ -x "${ROOT}/scripts/scrub-for-publish.sh" ]]; then
  if bash "${ROOT}/scripts/scrub-for-publish.sh" >/dev/null 2>&1; then
    pass SEC-2 "scrub-for-publish clean (repo)"
  else
    fail SEC-2 "scrub-for-publish failed — run bash scripts/scrub-for-publish.sh"
  fi
else
  warn() { echo "Gate SEC-2: WARN — scrub script missing at ${ROOT}/scripts/scrub-for-publish.sh" >&2; }
fi

exit $FAIL
