#!/usr/bin/env bash
# Validate Alfred model routing vs openclaw.json + reference YAML maps.
# Usage: validate-model-routing.sh --check
set -euo pipefail

OPENCLAW="${OPENCLAW_DIR:-$HOME/.openclaw}"
CFG="${OPENCLAW}/openclaw.json"
ROUTING="${OPENCLAW}/workspace/references/model-routing.yaml"
CRON_MAP="${OPENCLAW}/workspace/references/cron-model-map.yaml"
SHELL_MANIFEST="${OPENCLAW}/workspace/references/cron-shell-direct.yaml"
HARD_FAIL=0

ok() { echo "PASS $*"; }
bad() { echo "FAIL $*" >&2; HARD_FAIL=$((HARD_FAIL + 1)); }
warn() { echo "WARN $*" >&2; }

[[ "${1:-}" == "--check" ]] || { echo "usage: $0 --check" >&2; exit 2; }

[[ -f "$ROUTING" ]] && ok "MDL-0 model-routing.yaml present" || bad "MDL-0 model-routing.yaml missing"

python3 - "$CFG" "$ROUTING" "$CRON_MAP" "$SHELL_MANIFEST" <<'PY'
import json, sys, subprocess
from pathlib import Path

cfg_path, routing_path, cron_map_path, shell_path = map(Path, sys.argv[1:5])
fail = 0

def ok(g, msg):
    print(f"PASS {g} {msg}")

def bad(g, msg):
    global fail
    fail = 1
    print(f"FAIL {g} {msg}", file=sys.stderr)

if not cfg_path.is_file():
    bad("MDL-1", "openclaw.json missing")
    raise SystemExit(fail)

cfg = json.loads(cfg_path.read_text())
agents = cfg.get("agents") or {}
main = next((a for a in (agents.get("list") or []) if a.get("id") == "main"), {})
family = next((a for a in (agents.get("list") or []) if a.get("id") == "family"), {})
main_model = ((main.get("model") or {}).get("primary") or "")
family_model = ((family.get("model") or {}).get("primary") or "")

if main_model == "ollama/qwen3:8b-32k":
    ok("MDL-1", f"main primary={main_model}")
else:
    bad("MDL-1", f"main primary={main_model!r} expected ollama/qwen3:8b-32k")

relay = Path.home() / ".openclaw" / "nc-webhook-relay.py"
relay_family = False
if relay.is_file():
    relay_text = relay.read_text()
    relay_family = (
        'agent_id = "family"' in relay_text
        and "FAMILY_HUB_ROOM" in relay_text
        and '"agentId": agent_id' in relay_text
    )
if family_model == "ollama/qwen3:14b" and relay_family:
    ok("MDL-2", f"family agent model={family_model} relay hooks agentId=family")
elif family_model == "ollama/qwen3:14b":
    ok("MDL-2", f"family agent model={family_model} (relay routing not verified)")
else:
    bad("MDL-2", f"Family Hub not on family/14b (model={family_model!r} relay={relay_family})")

allowed = set((cfg.get("hooks") or {}).get("allowedAgentIds") or [])
if "family" in allowed:
    ok("MDL-2b", "hooks.allowedAgentIds includes family")
else:
    bad("MDL-2b", "hooks.allowedAgentIds missing family")

# MDL-3 shell-direct disabled in OpenClaw cron
if shell_path.is_file() and Path(cfg_path.parent / "cron" / "jobs.json").is_file():
    try:
        import yaml
        manifest = yaml.safe_load(shell_path.read_text()) or {}
        jobs = json.loads((cfg_path.parent / "cron" / "jobs.json").read_text()).get("jobs", [])
        by_id = {j["id"]: j for j in jobs}
        for row in manifest.get("jobs", []):
            j = by_id.get(row["id"])
            if j and j.get("enabled", True):
                bad("MDL-3", f"{row['name']} still enabled in OpenClaw cron")
        if not fail:
            ok("MDL-3", "shell-direct jobs disabled in OpenClaw cron")
    except Exception as e:
        bad("MDL-3", f"shell-direct check error: {e}")

# MDL-11 ollama models present (remote API may serve models; warn if CLI missing)
ollama_bin = None
for cand in ("ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"):
    from shutil import which
    if cand == "ollama":
        ollama_bin = which("ollama")
        if ollama_bin:
            break
    elif Path(cand).is_file():
        ollama_bin = cand
        break
if not ollama_bin:
    print("WARN MDL-11 ollama CLI not in PATH — skip local model list check")
else:
    try:
        out = subprocess.check_output([ollama_bin, "list"], text=True, timeout=15)
        need = ["8b-32k", "14b", "72b", "coder-next"]
        missing = [n for n in need if n not in out]
        if missing:
            bad("MDL-11", f"ollama list missing patterns: {missing}")
        else:
            ok("MDL-11", "required ollama models present")
    except Exception as e:
        bad("MDL-11", f"ollama list failed: {e}")

raise SystemExit(fail)
PY
rc=$?
[[ "$rc" -eq 0 ]] || HARD_FAIL=$((HARD_FAIL + rc))

echo "hard_fail=${HARD_FAIL}"
exit "$HARD_FAIL"
