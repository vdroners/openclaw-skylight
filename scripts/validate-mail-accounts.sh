#!/usr/bin/env bash
# Validate mail-accounts.json schema and secret files.
set -euo pipefail

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG="${1:-${OPENCLAW_DIR}/config/mail-accounts.json}"

python3 - "$CONFIG" "$OPENCLAW_DIR" <<'PY'
import json, sys
from pathlib import Path

config_path = Path(sys.argv[1])
openclaw = Path(sys.argv[2])
if not config_path.is_file():
    print(f"Gate X2: FAIL — missing {config_path}", file=sys.stderr)
    sys.exit(1)
data = json.loads(config_path.read_text())
accounts = data.get("accounts")
if not isinstance(accounts, list) or not accounts:
    print("Gate X2: FAIL — accounts must be non-empty list", file=sys.stderr)
    sys.exit(1)
roles = set()
for a in accounts:
    for k in ("role", "email", "secret_file", "account_name"):
        if k not in a:
            print(f"Gate X2: FAIL — missing {k} in account", file=sys.stderr)
            sys.exit(1)
    if a["role"] in roles:
        print(f"Gate X2: FAIL — duplicate role {a['role']}", file=sys.stderr)
        sys.exit(1)
    roles.add(a["role"])
    secret = openclaw / ".env.d" / a["secret_file"]
    if not secret.is_file():
        print(f"Gate X2: WARN — secret missing for {a['role']}: {secret}", file=sys.stderr)
print(f"Gate X2: PASS — {config_path.name} valid ({len(accounts)} accounts)")
PY
