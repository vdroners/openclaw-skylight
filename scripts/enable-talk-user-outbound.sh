#!/usr/bin/env bash
# Route OpenClaw nextcloud-talk outbound through talk-post.sh (NC user account)
# instead of the Talk Bot API — consistent sender with cron/dispatch scripts.
#
# Usage: enable-talk-user-outbound.sh [--check] [--revert]
# Re-run after: npm i -g openclaw@<version>
set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ENV_FILE="${OPENCLAW_DIR}/.env"
MARKER="OPENCLAW_TALK_USER_OUTBOUND_PATCH"

find_channel_js() {
  local p
  for p in /home/vdroners/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/dist/channel-*.js; do
    [[ -f "$p" ]] || continue
    if grep -q 'sendMessageNextcloudTalk' "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

CHANNEL_JS="$(find_channel_js || true)"
MODE="${1:---apply}"

apply_env() {
  grep -q '^NEXTCLOUD_TALK_USER_OUTBOUND=' "$ENV_FILE" 2>/dev/null \
    || echo 'NEXTCLOUD_TALK_USER_OUTBOUND=1' >>"$ENV_FILE"
  if grep -q '^NEXTCLOUD_TALK_USER_OUTBOUND=0' "$ENV_FILE" 2>/dev/null; then
    sed -i 's/^NEXTCLOUD_TALK_USER_OUTBOUND=0/NEXTCLOUD_TALK_USER_OUTBOUND=1/' "$ENV_FILE"
  fi
}

apply_patch() {
  [[ -n "$CHANNEL_JS" ]] || { echo "FAIL: openclaw channel bundle not found" >&2; exit 1; }
  if grep -q "$MARKER" "$CHANNEL_JS"; then
    echo "PASS patch already applied: $CHANNEL_JS"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  python3 - "$CHANNEL_JS" "$tmp" "$MARKER" <<'PY'
import sys
from pathlib import Path
src, dst, marker = sys.argv[1:4]
text = Path(src).read_text(encoding="utf-8")
needle = '\tif (!text?.trim()) throw new Error("Message must be non-empty for Nextcloud Talk sends");\n\tconst tableMode = resolveMarkdownTableMode({'
insert = (
    '\tif (!text?.trim()) throw new Error("Message must be non-empty for Nextcloud Talk sends");\n'
    f'\t// {marker}\n'
    '\tif (process.env.NEXTCLOUD_TALK_USER_OUTBOUND === "1") {\n'
    '\t\tconst { execFile } = await import("node:child_process");\n'
    '\t\tconst { promisify } = await import("node:util");\n'
    '\t\tconst talkPost = `${process.env.HOME}/.openclaw/scripts/talk-post.sh`;\n'
    '\t\tawait promisify(execFile)("bash", [talkPost, text.trim(), roomToken], {\n'
    '\t\t\tenv: { ...process.env, NEXTCLOUD_URL: baseUrl, NEXTCLOUD_USER: account.config.apiUser?.trim() || process.env.NEXTCLOUD_USER || "", NEXTCLOUD_PASS: process.env.NEXTCLOUD_PASS || "" },\n'
    '\t\t\ttimeout: 120000\n'
    '\t\t});\n'
    '\t\trecordNextcloudTalkOutboundActivity(account.accountId);\n'
    '\t\treturn { messageId: "talk-post-user", roomToken };\n'
    '\t}\n'
    '\tconst tableMode = resolveMarkdownTableMode({'
)
if needle not in text:
    raise SystemExit("FAIL: anchor not found in openclaw channel bundle (upgrade changed send.ts?)")
Path(dst).write_text(text.replace(needle, insert, 1), encoding="utf-8")
PY
  cp "$CHANNEL_JS" "${CHANNEL_JS}.bak-pre-user-outbound"
  mv "$tmp" "$CHANNEL_JS"
  echo "PASS patched $CHANNEL_JS (backup ${CHANNEL_JS}.bak-pre-user-outbound)"
}

revert_patch() {
  [[ -n "$CHANNEL_JS" ]] || { echo "no channel js" >&2; exit 1; }
  local bak="${CHANNEL_JS}.bak-pre-user-outbound"
  [[ -f "$bak" ]] || { echo "no backup to revert" >&2; exit 1; }
  cp "$bak" "$CHANNEL_JS"
  echo "reverted $CHANNEL_JS from backup"
}

case "$MODE" in
  --check)
    [[ -n "$CHANNEL_JS" ]] && grep -q "$MARKER" "$CHANNEL_JS" && echo "PASS user-outbound patch present" || { echo "FAIL patch missing" >&2; exit 1; }
    grep -q '^NEXTCLOUD_TALK_USER_OUTBOUND=1' "$ENV_FILE" 2>/dev/null && echo "PASS env NEXTCLOUD_TALK_USER_OUTBOUND=1" || { echo "FAIL env not set" >&2; exit 1; }
    ;;
  --revert)
    revert_patch
    ;;
  --apply|*)
    apply_env
    apply_patch
    echo "Restart gateway: systemctl --user restart openclaw-gateway"
    ;;
esac
