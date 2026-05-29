#!/usr/bin/env bash
# Pre-push PII/secret grep gate. Exit non-zero on blocklist hit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

FAIL=0
# Literal patterns only — do not sanitize this file
BLOCKLIST=(
  'daniel\.sautter56'
  'mrssautter@'
  '9x4f25n3'
  'jf7zijqp'
  '5136415'
  '6440477'
  '6427910'
  '/home/vdroners'
  'cloud-vdroners\.ddns\.net'
  '10\.0\.0\.84'
  'Bearer ey'
)

echo "=== scrub-for-publish.sh ==="
for pat in "${BLOCKLIST[@]}"; do
  if rg -n "$pat" --glob '!.git' --glob '!scripts/scrub-for-publish.sh' . 2>/dev/null; then
    echo "S1 FAIL: blocklist hit: $pat" >&2
    FAIL=1
  fi
done

if [[ -f .env ]]; then
  echo "S3 FAIL: .env must not be tracked" >&2
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "Gate S1: PASS — no blocklist hits"
fi
exit $FAIL
