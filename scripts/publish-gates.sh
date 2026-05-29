#!/usr/bin/env bash
# Repo structure + scrub gates (S1-S8, X1). Run before push.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"
FAIL=0

pass() { echo "Gate $1: PASS — $2"; }
fail() { echo "Gate $1: FAIL — $2"; FAIL=1; }

bash "${SCRIPT_DIR}/scrub-for-publish.sh" && pass S1 "scrub clean" || fail S1 "scrub failed"

# S2: large files
while IFS= read -r f; do
  sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if [[ "$sz" -gt 512000 ]] && [[ "$f" != *LICENSE* ]] && [[ "$f" != *examples* ]]; then
    fail S2 "large file $f ($sz bytes)"
  fi
done < <(find . -type f ! -path './.git/*' 2>/dev/null)
[[ "$FAIL" -eq 0 ]] && pass S2 "no oversized tracked files"

# S3: .env.example
for v in SKYLIGHT_FRAME_ID SKYLIGHT_EMAIL SKYLIGHT_PASSWORD NEXTCLOUD_URL NEXTCLOUD_USER NEXTCLOUD_PASS SKYLIGHT_FAMILY_TALK_ROOM FAMILY_GMAIL_ADDRESS; do
  grep -q "^${v}=" .env.example 2>/dev/null || fail S3 "missing $v in .env.example"
done
[[ -f .env ]] && fail S3 ".env tracked" || pass S3 ".env.example complete"

# S4: bash syntax
for f in scripts/*.sh; do
  bash -n "$f" || fail S4 "$f syntax error"
done
pass S4 "all scripts pass bash -n"

# S5-S6 covered by scrub

# S7: community files
for f in LICENSE SECURITY.md CONTRIBUTING.md README.md; do
  [[ -f "$f" ]] || fail S7 "missing $f"
done
pass S7 "community files present"

# S8: cron templates
for f in config/cron/*.template; do
  if grep -qE 'password|Bearer|@[a-z]+\.(gmail|ourskylight)' "$f" 2>/dev/null; then
    fail S8 "secret in $f"
  fi
done
pass S8 "cron templates clean"

bash "${SCRIPT_DIR}/validate-household-model.sh" "${ROOT}/config/household-model.example.json" && pass X1 "schema ok" || fail X1 "schema failed"

echo ""
echo "=== publish-gates summary (hard_fail=$FAIL) ==="
exit $FAIL
