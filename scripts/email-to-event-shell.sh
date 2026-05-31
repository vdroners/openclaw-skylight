#!/usr/bin/env bash
# Shell-direct wrapper for email-to-event-scan (no agentTurn LLM wrapper).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load-nextcloud-env.sh"

bash "${SCRIPT_DIR}/email-to-event-scan.sh"
