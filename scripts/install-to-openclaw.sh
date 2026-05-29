#!/usr/bin/env bash
# Symlink openclaw-skylight into ~/.openclaw (idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "${OPENCLAW_DIR}/scripts" "${OPENCLAW_DIR}/workspace/skills" "${OPENCLAW_DIR}/config"

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

for f in "${ROOT}"/scripts/*.sh; do
  base=$(basename "$f")
  case "$base" in
    install-to-openclaw.sh|scrub-for-publish.sh|publish-gates.sh) continue ;;
  esac
  link_one "$f" "${OPENCLAW_DIR}/scripts/$base"
done

link_one "${ROOT}/skills/skylight" "${OPENCLAW_DIR}/workspace/skills/skylight"
link_one "${ROOT}/skills/email-intelligence" "${OPENCLAW_DIR}/workspace/skills/email-intelligence"

if [[ ! -f "${OPENCLAW_DIR}/config/household-model.json" ]]; then
  cp "${ROOT}/config/household-model.example.json" "${OPENCLAW_DIR}/config/household-model.json"
  echo "install: copied household-model.example.json → ~/.openclaw/config/household-model.json (edit with your IDs)"
fi

export OPENCLAW_SKYLIGHT_ROOT="$ROOT"
echo "Gate I1: install ok — OPENCLAW_SKYLIGHT_ROOT=$ROOT"
echo "Re-run safe: symlinks updated idempotently (I2)"
