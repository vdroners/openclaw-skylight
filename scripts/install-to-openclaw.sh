#!/usr/bin/env bash
# Symlink openclaw-skylight into ~/.openclaw (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "${OPENCLAW_DIR}/scripts" "${OPENCLAW_DIR}/scripts/lib" "${OPENCLAW_DIR}/workspace/skills" "${OPENCLAW_DIR}/config" "${OPENCLAW_DIR}/workspace/references"

link_one() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    cur=$(readlink -f "$dst" 2>/dev/null || readlink "$dst")
    [[ "$cur" == "$src" ]] && return 0
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dst"
    else
      echo "install: skip existing $dst (use --force to replace with symlink)" >&2
      return 0
    fi
  fi
  ln -sf "$src" "$dst"
}

# OpenClaw gateway rejects workspace skill symlinks outside the workspace root.
sync_skill() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  elif [[ -d "$dst" && "$FORCE" -eq 0 ]]; then
    echo "install: skip existing skill dir $dst (use --force to refresh copy)" >&2
    return 0
  fi
  rm -rf "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${src}/" "${dst}/"
  else
    cp -a "${src}" "${dst}"
  fi
}

for f in "${ROOT}"/scripts/*.sh; do
  base=$(basename "$f")
  case "$base" in
    install-to-openclaw.sh|scrub-for-publish.sh|publish-gates.sh) continue ;;
  esac
  link_one "$f" "${OPENCLAW_DIR}/scripts/$base"
done

for f in "${ROOT}"/scripts/*.py; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  link_one "$f" "${OPENCLAW_DIR}/scripts/$base"
done

for f in "${ROOT}"/scripts/lib/*; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  link_one "$f" "${OPENCLAW_DIR}/scripts/lib/$base"
done

sync_skill "${ROOT}/skills/skylight" "${OPENCLAW_DIR}/workspace/skills/skylight"
sync_skill "${ROOT}/skills/email-intelligence" "${OPENCLAW_DIR}/workspace/skills/email-intelligence"
if [[ -d "${ROOT}/skills/flight-triage" ]]; then
  sync_skill "${ROOT}/skills/flight-triage" "${OPENCLAW_DIR}/workspace/skills/flight-triage"
fi
if [[ -d "${ROOT}/skills/forge-print" ]]; then
  sync_skill "${ROOT}/skills/forge-print" "${OPENCLAW_DIR}/workspace/skills/forge-print"
fi

# Operator mention alias: patch copied skills when OPENCLAW_AGENT_MENTION is set in .env
if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${OPENCLAW_DIR}/.env"
  if [[ -n "${OPENCLAW_AGENT_MENTION:-}" && "${OPENCLAW_AGENT_MENTION}" != "@openclaw" ]]; then
    find "${OPENCLAW_DIR}/workspace/skills" -name 'SKILL.md' -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do
          sed -i 's/@openclaw/'"${OPENCLAW_AGENT_MENTION}"'/g' "$f"
        done
  fi
fi

if [[ ! -f "${OPENCLAW_DIR}/config/household-model.json" ]]; then
  cp "${ROOT}/config/household-model.example.json" "${OPENCLAW_DIR}/config/household-model.json"
  echo "install: copied household-model.example.json → ~/.openclaw/config/household-model.json (edit with your IDs)"
fi

for ref in cron-shell-direct.yaml test-week-cron-profile.yaml; do
  src="${ROOT}/config/references/${ref}"
  dst="${OPENCLAW_DIR}/workspace/references/${ref}"
  if [[ -f "$src" && ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "install: copied workspace/references/${ref} (edit locally; not overwritten on re-install)"
  fi
done

for help in talk-help-family.txt talk-help-ops.txt; do
  link_one "${ROOT}/config/${help}" "${OPENCLAW_DIR}/config/${help}"
done

link_one "${ROOT}/scripts/talk-webhook-shim.py" "${OPENCLAW_DIR}/talk-webhook-shim.py"

export OPENCLAW_SKYLIGHT_ROOT="$ROOT"

# Gate I3: skills must be real dirs under workspace (OpenClaw rejects symlink-escape)
_i3_fail=0
for _sk in skylight email-intelligence forge-print; do
  _p="${OPENCLAW_DIR}/workspace/skills/${_sk}"
  if [[ ! -d "$_p" ]]; then
    echo "FAIL I3: missing skill dir $_p" >&2
    _i3_fail=1
    continue
  fi
  _real=$(readlink -f "$_p" 2>/dev/null || echo "$_p")
  case "$_real" in
    "${OPENCLAW_DIR}/workspace/skills/"*) echo "PASS I3: $_sk under workspace" ;;
    *) echo "FAIL I3: $_sk resolves outside workspace ($_real)" >&2; _i3_fail=1 ;;
  esac
done
if [[ -d "${OPENCLAW_DIR}/workspace/skills/flight-triage" ]]; then
  _real=$(readlink -f "${OPENCLAW_DIR}/workspace/skills/flight-triage" 2>/dev/null || true)
  case "$_real" in
    "${OPENCLAW_DIR}/workspace/skills/"*) echo "PASS I3: flight-triage under workspace" ;;
    *) echo "FAIL I3: flight-triage outside workspace" >&2; _i3_fail=1 ;;
  esac
fi
[[ "$_i3_fail" -eq 0 ]] || exit 1

echo "Gate I1: install ok — OPENCLAW_SKYLIGHT_ROOT=$ROOT"
echo "Re-run safe: symlinks updated idempotently (I2)"
echo "Note: skills are copied (not symlinked). Re-run --force after skill updates."
