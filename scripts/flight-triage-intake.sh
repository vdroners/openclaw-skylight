#!/usr/bin/env bash
# flight-triage-intake.sh — POST job to nc_ardupilot_triage (after YES).
set -euo pipefail

BIN_PATH="${1:-}"
RUN_LABEL="${2:-}"
FOCUS="${3:-}"

NC_URL="${NC_URL:-}"
TOKEN="${NC_AT_PUBLISH_TOKEN:-}"

[[ -n "$BIN_PATH" && -n "$RUN_LABEL" ]] || { echo "Usage: $0 BIN_PATH RUN_LABEL [FOCUS]"; exit 2; }

BODY=$(jq -n \
	--arg bin "$BIN_PATH" \
	--arg label "$RUN_LABEL" \
	--arg focus "$FOCUS" \
	'{bin_path:$bin, run_label:$label, intake:{focus_question:$focus, bin_path:$bin, run_label:$label, airframe_class:"quadplane", compare_to_baseline:"auto"}}')

ENDPOINT="${NC_URL%/}/index.php/apps/nc_ardupilot_triage/api/jobs"
curl -sS -X POST "$ENDPOINT" \
	-H "Content-Type: application/json" \
	-H "Authorization: Basic $(printf '%s' "${NC_WEBDAV_USERNAME:-NCAdmin}:${NC_WEBDAV_PASSWORD:-}" | base64 -w0)" \
	-d "$BODY"
