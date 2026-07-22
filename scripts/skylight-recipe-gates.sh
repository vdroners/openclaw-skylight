#!/usr/bin/env bash
# Recipe import gates: bb-pdc20 markdown parsing + Skylight presence (P12 / SKY-06).
# Usage: skylight-recipe-gates.sh [--check] [--web-only] [--check-full]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-skylight-env.sh"

CHECK=0
WEB_ONLY=0
CHECK_FULL=0
FAIL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --web-only) WEB_ONLY=1; shift ;;
    --check-full) CHECK=1; CHECK_FULL=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--check] [--web-only] [--check-full]"
      echo "  --check       Verify Skylight has imported recipes (requires API)"
      echo "  --web-only    Gate section 16 web adaptations only"
      echo "  --check-full  All manifest titles present on Skylight (61 recipes)"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

SNAPSHOT="${BB_SNAPSHOT:-${HOME}/.cursor/snapshots/skylight-bb-pdc20-recipes}"
WEB_DIR="${SNAPSHOT}/16-web-adaptations"

pass() { echo "P12 OK  $*"; }
fail() { echo "P12 FAIL $*" >&2; FAIL=1; }

if [[ ! -d "$WEB_DIR" ]]; then
  fail "missing $WEB_DIR (BB_SNAPSHOT web adaptations)"
  exit 1
fi

# Dry-run parse all web markdown files
while IFS= read -r f; do
  [[ "$(basename "$f")" == _section.md ]] && continue
  if bash "${SCRIPT_DIR}/skylight-import-recipes-verify.sh" --dry-run "$f" >/dev/null 2>&1; then
    pass "parse $(basename "$f")"
  else
    fail "parse $(basename "$f")"
    bash "${SCRIPT_DIR}/skylight-import-recipes-verify.sh" --dry-run "$f" || true
  fi
done < <(find "$WEB_DIR" -maxdepth 1 -name '*.md' -type f | sort)

# Manifest count
expected="$(python3 - "$SNAPSHOT" <<'PY'
import json, sys
from pathlib import Path
m = json.loads((Path(sys.argv[1]) / "manifest.json").read_text())
web = sum(1 for r in m.get("recipes", []) if r.get("section") == "16-web-adaptations")
print(web)
PY
)"
found="$(find "$WEB_DIR" -maxdepth 1 -name '*.md' ! -name '_section.md' -type f | wc -l | tr -d ' ')"
if [[ "$found" -eq "$expected" ]]; then
  pass "manifest web count=$expected"
else
  fail "manifest web count=$expected but files=$found"
fi

if (( CHECK )); then
  samples=(
    "Lavender-Thyme Bread"
    "Banana Banana Bread"
    "Copeland Buttermilk Biscuits (Popeyes-style)"
    "Raisin Bread"
  )
  for t in "${samples[@]}"; do
    if bash "${SCRIPT_DIR}/skylight-import-recipes-verify.sh" --check-imported "$t" >/dev/null 2>&1; then
      pass "imported $t"
    else
      fail "imported $t"
    fi
  done
fi

if (( WEB_ONLY == 0 && CHECK )); then
  for t in "Basic White Bread" "Honey Bread"; do
    if bash "${SCRIPT_DIR}/skylight-import-recipes-verify.sh" --check-imported "$t" >/dev/null 2>&1; then
      pass "imported $t"
    else
      fail "imported $t (factory pilot)"
    fi
  done
fi

if (( CHECK_FULL )); then
  if python3 - "$SNAPSHOT" "$SCRIPT_DIR" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

snapshot = Path(sys.argv[1])
manifest = json.loads((snapshot / "manifest.json").read_text())
titles = [r["title"] for r in manifest.get("recipes", [])]
expected = len(titles)
fid = os.environ["SKYLIGHT_FRAME_ID"]
out = subprocess.check_output(
    ["skylight", "meals", "listRecipes", "--frame-id", fid, "--json"],
    text=True,
)
frame_titles = {
    (r.get("attributes") or {}).get("summary") or ""
    for r in json.loads(out).get("data") or []
}
missing = [t for t in titles if t not in frame_titles]
if missing:
    print(f"P12 FAIL check-full: {len(missing)}/{expected} manifest titles missing on frame", file=sys.stderr)
    for t in missing[:10]:
        print(f"  missing: {t}", file=sys.stderr)
    if len(missing) > 10:
        print(f"  …{len(missing) - 10} more", file=sys.stderr)
    sys.exit(1)
print(f"P12 OK  check-full manifest={expected} frame_unique={len(frame_titles)}")
PY
  then
    pass "check-full manifest titles on frame"
  else
    fail "check-full manifest titles on frame"
  fi
fi

echo "=== skylight-recipe-gates summary (hard_fail=$FAIL) ==="
exit "$FAIL"
