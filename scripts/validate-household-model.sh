#!/usr/bin/env bash
# Validate household-model JSON against schema (requires python3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${1:-${ROOT}/config/household-model.example.json}"

python3 - "$TARGET" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    print(f"X1 FAIL: missing {path}", file=sys.stderr)
    sys.exit(1)

data = json.loads(path.read_text())
required = ["frame_id", "writable_calendar_emails", "default_calendar_email"]
missing = [k for k in required if k not in data]
if missing:
    print(f"X1 FAIL: missing keys {missing}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data["writable_calendar_emails"], list) or not data["writable_calendar_emails"]:
    print("X1 FAIL: writable_calendar_emails must be non-empty list", file=sys.stderr)
    sys.exit(1)
print(f"Gate X1: PASS — {path.name} valid")
PY
