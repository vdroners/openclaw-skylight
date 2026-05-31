#!/usr/bin/env python3
"""Install systemd user timers for shell-direct cron jobs; disable OpenClaw agentTurn duplicates."""
from __future__ import annotations

import json
import os
import stat
import subprocess
import textwrap
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML required")

OPENCLAW = Path(os.environ.get("OPENCLAW_DIR", Path.home() / ".openclaw"))
SKYLIGHT_ROOT = Path(os.environ.get("OPENCLAW_SKYLIGHT_ROOT", ""))
MANIFEST = OPENCLAW / "workspace" / "references" / "cron-shell-direct.yaml"
if not MANIFEST.is_file() and SKYLIGHT_ROOT:
    alt = SKYLIGHT_ROOT / "config" / "references" / "cron-shell-direct.yaml"
    if alt.is_file():
        MANIFEST = alt
JOBS_PATH = OPENCLAW / "cron" / "jobs.json"
SYSTEMD_USER = Path.home() / ".config" / "systemd" / "user"
RUNNER = OPENCLAW / "scripts" / "run-openclaw-cron-shell.sh"


def expand_path(raw: str) -> str:
    return (
        raw.replace("${OPENCLAW_DIR}", str(OPENCLAW))
        .replace("$HOME", str(Path.home()))
    )


PREFIX = os.environ.get("OPENCLAW_CRON_UNIT_PREFIX", "openclaw-cron")


def cron_to_systemd(schedule: str) -> str:
    """Convert 5-field cron to systemd OnCalendar (Pacific tz set on service)."""
    parts = schedule.split()
    if len(parts) != 5:
        raise ValueError(f"unsupported schedule: {schedule}")
    minute, hour, dom, mon, dow = parts

    if minute.startswith("*/") and "-" in hour and dom == mon == dow == "*":
        step = minute[2:]
        h0, h1 = hour.split("-", 1)
        return f"*-*-* {h0}..{h1}:00/{step}"

    if minute == "0" and hour.startswith("*/") and dom == mon == dow == "*":
        return f"0/{hour[2:]}:00"

    if minute.isdigit() and hour.isdigit() and dom == mon == dow == "*":
        return f"{hour.zfill(2)}:{minute.zfill(2)}:00"

    if minute.isdigit() and dom.isdigit() and mon == "*" and dow == "*":
        return f"*-{dom.zfill(2)} {hour.zfill(2)}:{minute.zfill(2)}:00"

    if minute.isdigit() and hour.isdigit() and dom == "*" and mon == "*" and dow.isdigit():
        dow_map = {"0": "Sun", "1": "Mon", "2": "Tue", "3": "Wed", "4": "Thu", "5": "Fri", "6": "Sat"}
        return f"{dow_map.get(dow, dow)} {hour.zfill(2)}:{minute.zfill(2)}:00"

    raise ValueError(f"cannot convert schedule to OnCalendar: {schedule}")


def write_unit(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def main() -> None:
    RUNNER.chmod(RUNNER.stat().st_mode | stat.S_IXUSR)
    doc = yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}
    jobs = doc.get("jobs") or []
    SYSTEMD_USER.mkdir(parents=True, exist_ok=True)

    data = json.loads(JOBS_PATH.read_text(encoding="utf-8"))
    job_by_id = {j["id"]: j for j in data.get("jobs", [])}
    disabled = 0

    for job in jobs:
        jid = job["id"]
        name = job["name"]
        script = expand_path(job["script"])
        grep = job.get("success_grep", "POSTED")
        schedule = job["schedule"]
        tz = job.get("tz", "America/Los_Angeles")
        unit = f"{PREFIX}-{name}"

        service = textwrap.dedent(
            f"""\
            [Unit]
            Description=OpenClaw shell-direct cron: {name}
            After=network-online.target openclaw-gateway.service

            [Service]
            Type=oneshot
            Environment=OPENCLAW_DIR={OPENCLAW}
            Environment=TZ={tz}
            ExecStart={RUNNER} {jid} {name} {script} {grep}
            """
        )
        try:
            on_cal = cron_to_systemd(schedule)
        except ValueError as e:
            raise SystemExit(str(e)) from e

        timer = textwrap.dedent(
            f"""\
            [Unit]
            Description=Timer for OpenClaw shell-direct cron: {name}

            [Timer]
            OnCalendar={on_cal}
            Persistent=true
            Unit={unit}.service

            [Install]
            WantedBy=timers.target
            """
        )

        write_unit(SYSTEMD_USER / f"{unit}.service", service)
        write_unit(SYSTEMD_USER / f"{unit}.timer", timer)

        oc = job_by_id.get(jid)
        if oc and oc.get("enabled", True):
            oc["enabled"] = False
            note = f" [shell-direct via systemd {unit}.timer]"
            desc = oc.get("description") or ""
            if "shell-direct" not in desc:
                oc["description"] = (desc + note).strip()
            disabled += 1

    JOBS_PATH.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    for job in jobs:
        unit = f"{PREFIX}-{job['name']}.timer"
        subprocess.run(["systemctl", "--user", "enable", "--now", unit], check=False)

    print(f"Installed {len(jobs)} shell-direct timers; disabled {disabled} OpenClaw cron jobs")


if __name__ == "__main__":
    main()
