#!/usr/bin/env bash
# Pre-push PII/secret grep gate. Exit non-zero on blocklist hit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

FAIL=0
# Literal patterns only — do not sanitize this file's BLOCKLIST array
BLOCKLIST=(
  'daniel\.sautter56'
  'mrssautter@'
  'veterandroners'
  'daniel@19labs'
  'daniel-gmail'
  '9x4f25n3'
  'jf7zijqp'
  '5136415'
  '6440477'
  '6427910'
  '/home/vdroners'
  '/media/4TB/'
  'cloud-vdroners\.ddns\.net'
  '10\.0\.0\.84'
  'Bearer ey'
  '@alfred'
  'Rose City Futsal'
  'Sam Jackson Park'
  '75543198'
  '19116222'
  '19116283'
  '19255362'
  '19177556'
  '84072913'
  'Phoebe'
  'Wesley'
)

echo "=== scrub-for-publish.sh ==="
for pat in "${BLOCKLIST[@]}"; do
  hit=0
  rm -f /tmp/scrub-hit.txt
  if grep -rEn "$pat" . \
    --exclude-dir=.git \
    --exclude-dir=__pycache__ \
    --exclude=scrub-for-publish.sh \
    --exclude=CHANGELOG.md \
    --exclude=talk-help-ops.txt \
    --exclude=.env.example \
    >/tmp/scrub-hit.txt 2>/dev/null; then
    hit=1
  fi
  if [[ "$hit" -eq 1 ]]; then
    cat /tmp/scrub-hit.txt >&2
    echo "S1 FAIL: blocklist hit: $pat" >&2
    FAIL=1
  fi
done
rm -f /tmp/scrub-hit.txt

# Legacy agent branding should not appear in publishable tree
if grep -rEi '\balfred\b' . \
  --exclude-dir=.git \
  --exclude-dir=__pycache__ \
  --exclude=scrub-for-publish.sh \
  --exclude=CHANGELOG.md \
  --exclude=talk-help-ops.txt \
  --exclude=.env.example \
  --exclude-dir=skills/forge-print \
  >/tmp/scrub-alfred.txt 2>/dev/null; then
  cat /tmp/scrub-alfred.txt >&2
  echo "S1 FAIL: legacy agent branding — use OpenClaw / @openclaw" >&2
  FAIL=1
fi
rm -f /tmp/scrub-alfred.txt

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo "S3 FAIL: .env must not be tracked in git" >&2
  FAIL=1
fi

if git ls-files '*.secret' 2>/dev/null | grep -q .; then
  echo "S3 FAIL: *.secret must not be tracked in git" >&2
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "Gate S1: PASS — no blocklist hits"
fi
exit $FAIL
