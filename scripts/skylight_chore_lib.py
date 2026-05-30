#!/usr/bin/env python3
"""Infer and apply Skylight chore field defaults (times, routine, points)."""
from __future__ import annotations

import json
import re
import subprocess
import urllib.error
import urllib.request
from datetime import date, timedelta
from pathlib import Path
from typing import Any

KID_CATS = {"19116283", "19255362", "19177556"}


def norm_title(s: str | None) -> str:
    return (s or "").strip().lower()


def load_model(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


def chore_time_defaults(model: dict[str, Any]) -> dict[str, tuple[str, bool]]:
    raw = model.get("chore_time_defaults") or {}
    out: dict[str, tuple[str, bool]] = {}
    for k, v in raw.items():
        if isinstance(v, list) and len(v) >= 2:
            out[k.lower()] = (str(v[0]), bool(v[1]))
        elif isinstance(v, tuple):
            out[k.lower()] = (str(v[0]), bool(v[1]))
    return out


def reward_defaults(model: dict[str, Any]) -> dict[str, int]:
    raw = model.get("chore_reward_defaults") or {}
    return {
        "default": int(raw.get("default", 1)),
        "deep": int(raw.get("deep", 2)),
        "monthly": int(raw.get("monthly", 2)),
    }


def lookup_time_defaults(ns: str, defaults: dict[str, tuple[str, bool]]) -> tuple[str, bool] | None:
    if ns in defaults:
        return defaults[ns]
    for key, val in defaults.items():
        if key in ns:
            return val
    return None


def infer_from_rrule(row: dict[str, Any]) -> tuple[str, bool] | None:
    rrules = row.get("recurrence_set") or []
    rrule = rrules[0] if rrules else ""
    ns = norm_title(row.get("summary"))

    if "BYHOUR=6" in rrule or ("feed" in ns and "cat" in ns):
        return ("06:00", True)
    if "BYHOUR=20" in rrule or "BYHOUR=14" in rrule:
        hour = "20:00" if "BYHOUR=20" in rrule else "14:00"
        return (hour, True)

    if "FREQ=DAILY" in rrule:
        m = re.search(r"INTERVAL=(\d+)", rrule)
        interval = int(m.group(1)) if m else 1
        if interval == 1:
            if any(k in ns for k in ("dishes", "clean room", "brush", "toys", "shoes", "kitchen", "counter")):
                return ("20:00", True)
        if interval == 3 and "trash" in ns:
            return ("07:00", False)
        if interval >= 4:
            return ("10:00", False)

    if "FREQ=WEEKLY" in rrule or "FREQ=MONTHLY" in rrule:
        return ("10:00", False)

    return None


def infer_reward_points(row: dict[str, Any], cfg: dict[str, int]) -> int:
    if row.get("reward_points") is not None:
        return int(row["reward_points"])
    ns = norm_title(row.get("summary"))
    rrule = (row.get("recurrence_set") or [""])[0]
    if "FREQ=MONTHLY" in rrule:
        return cfg["monthly"]
    if any(k in ns for k in ("vacuum", "mop", "deep", "window", "mirror", "shelf", "piano", "organize")):
        return cfg["deep"]
    return cfg["default"]


def build_enrichment(
    row: dict[str, Any],
    time_defaults: dict[str, tuple[str, bool]],
    reward_cfg: dict[str, int],
) -> dict[str, Any] | None:
    """Return fields to apply, or None if row is already complete."""
    fields: dict[str, Any] = {}
    ns = norm_title(row.get("summary"))
    cat = str(row.get("category_id") or "")

    if not row.get("start_time"):
        td = lookup_time_defaults(ns, time_defaults) or infer_from_rrule(row)
        if td:
            fields["start_time"] = td[0]
            fields["routine"] = td[1]
    elif cat in KID_CATS and not row.get("routine"):
        td = lookup_time_defaults(ns, time_defaults)
        if td and td[1]:
            fields["routine"] = True

    if row.get("reward_points") is None:
        fields["reward_points"] = infer_reward_points(row, reward_cfg)

    if not fields:
        return None
    if "reward_points" not in fields:
        fields["reward_points"] = row.get("reward_points") or reward_cfg["default"]
    return fields


def allowed_byhour(start_time: str) -> tuple[int, str]:
    hour = int((start_time or "20:00").split(":")[0])
    if hour <= 8:
        return 6, "06:00"
    if hour <= 15:
        return 14, "14:00"
    return 20, "20:00"


def sync_rrule(recurrence_set: list[str] | None, byhour: int, routine: bool) -> list[str]:
    if not routine:
        return list(recurrence_set or [])
    out: list[str] = []
    for rule in recurrence_set or []:
        if not rule.startswith("RRULE:"):
            out.append(rule)
            continue
        body = rule[6:]
        body = re.sub(r";BYHOUR=\d+", "", body)
        body = re.sub(r";BYMINUTE=\d+", "", body)
        out.append(f"RRULE:{body};BYHOUR={byhour}")
    return out or [f"RRULE:FREQ=DAILY;INTERVAL=1;WKST=MO;BYHOUR={byhour}"]


def list_chore_series(frame_id: str, days: int = 60) -> list[dict[str, Any]]:
    start = date.today().isoformat()
    end = (date.today() + timedelta(days=days)).isoformat()
    out = subprocess.check_output(
        [
            "skylight", "chores", "listChores",
            "--frame-id", frame_id,
            "--after", start,
            "--before", end,
            "--json",
        ],
        text=True,
    )
    data = json.loads(out)
    groups: dict[str, list] = {}
    for c in data.get("data") or []:
        a = c.get("attributes") or {}
        gid = str(a.get("group") or c["id"].split("-")[0])
        groups.setdefault(gid, []).append(c)

    kid_cats = KID_CATS  # noqa — caller may override via model
    rows: list[dict[str, Any]] = []
    for gid, items in groups.items():
        i = items[0]
        a = i.get("attributes") or {}
        rel = (i.get("relationships") or {}).get("category") or {}
        cat_id = str((rel.get("data") or {}).get("id") or "")
        rows.append({
            "group_id": gid,
            "summary": a.get("summary") or "",
            "category_id": cat_id,
            "person": {"19116283": "Phoebe", "19255362": "Wesley", "19177556": "Dan"}.get(cat_id, "?"),
            "reward_points": a.get("reward_points"),
            "recurrence_set": a.get("recurrence_set"),
            "routine": a.get("routine"),
            "start_time": a.get("start_time"),
            "_raw": i,
        })
    return rows


def apply_chore_update(
    frame_id: str,
    auth: str,
    api_url: str,
    group_id: str,
    fields: dict[str, Any],
    cur: dict[str, Any],
) -> None:
    target_time = fields.get("start_time") or "20:00"
    routine = bool(fields.get("routine"))
    bh, _slot = allowed_byhour(target_time)
    a = cur.get("attributes") or {}
    rel = (cur.get("relationships") or {}).get("category") or {}
    cat_id = (rel.get("data") or {}).get("id")
    body = {
        "summary": a.get("summary"),
        "reward_points": fields.get("reward_points", a.get("reward_points") or 1),
        "routine": routine,
        "recurrence_set": sync_rrule(a.get("recurrence_set"), bh, routine),
        "start": a.get("start"),
        "category_id": cat_id,
    }
    if not routine:
        body["start_time"] = target_time

    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/frames/{frame_id}/chores/{group_id}",
        data=data,
        headers={
            "Authorization": auth,
            "Content-Type": "application/json",
            "User-Agent": "SkylightMobile (web)",
        },
        method="PUT",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError(f"PUT chores/{group_id} -> HTTP {resp.status}")


def find_series_chore(chores_json: dict, group_id: str) -> dict | None:
    for c in chores_json.get("data") or []:
        a = c.get("attributes") or {}
        g = str(a.get("group") or c["id"].split("-")[0])
        if g == str(group_id):
            return c
    return None
