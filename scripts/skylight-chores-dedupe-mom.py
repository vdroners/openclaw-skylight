#!/usr/bin/env python3
"""Consolidate Mom's duplicate monthly piano/shelf chores on Skylight."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from skylight_chore_lib import apply_chore_update, list_chore_series  # noqa: E402

OPENCLAW = Path(os.environ.get("OPENCLAW_DIR", Path.home() / ".openclaw"))
SNAP = OPENCLAW / "state" / "chore-dedupe-snapshots"
MOM_CAT = "19116222"

# group_id -> canonical title (rename before/after delete)
KEEP_RENAMES: dict[str, str] = {
    "75543198": "Clean Shelf",
    "75673457": "Clean Shelf & Piano Top",
    "75960314": "Organize Knitting/Sewing",
}

DELETE_GROUP_IDS = [
    # 4 duplicate Clean Shelf (all BYMONTHDAY=26)
    "75543218",
    "75543220",
    "75543233",
    "75543238",
    # 3 piano variants superseded by 75673457
    "75712911",
    "75543392",
    "75543523",
    # duplicate Organize Knitting/sewing
    "75960370",
]


def delete_series(frame_id: str, group_id: str) -> None:
    subprocess.run(
        [
            "skylight", "chores", "deleteChore",
            "--frame-id", frame_id,
            "--chore-id", group_id,
            "--apply-to", "all",
        ],
        check=True,
        capture_output=True,
        text=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    frame_id = os.environ["SKYLIGHT_FRAME_ID"]
    auth = os.environ["SKYLIGHT_AUTHORIZATION"]
    api = os.environ["SKYLIGHT_API_URL"]

    rows = {r["group_id"]: r for r in list_chore_series(frame_id)}
    if not args.dry_run:
        SNAP.mkdir(parents=True, exist_ok=True)

    deleted = 0
    for gid in DELETE_GROUP_IDS:
        row = rows.get(gid)
        if not row:
            print(f"SKIP delete {gid}: not found")
            continue
        label = f"Mom: {row['summary']} ({gid})"
        if args.dry_run:
            print(f"DRY DELETE {label}")
            deleted += 1
            continue
        snap = SNAP / f"{gid}-{date.today().isoformat()}-pre.json"
        if not snap.is_file():
            snap.write_text(json.dumps(row["_raw"], indent=2))
        try:
            delete_series(frame_id, gid)
            print(f"DELETED {label}")
            deleted += 1
            time.sleep(0.3)
        except subprocess.CalledProcessError as exc:
            print(f"FAIL DELETE {label}: {exc.stderr or exc}", file=sys.stderr)

    renamed = 0
    for gid, title in KEEP_RENAMES.items():
        row = rows.get(gid)
        if not row:
            print(f"SKIP rename {gid}: not found")
            continue
        if row["summary"] == title:
            continue
        label = f"Mom: {row['summary']} -> {title}"
        if args.dry_run:
            print(f"DRY RENAME {label}")
            renamed += 1
            continue
        fields = {
            "start_time": row.get("start_time") or "10:00",
            "routine": bool(row.get("routine")),
            "reward_points": row.get("reward_points") or 2,
        }
        cur = dict(row["_raw"])
        cur.setdefault("attributes", {})["summary"] = title
        try:
            apply_chore_update(frame_id, auth, api, gid, fields, cur)
            print(f"RENAMED {label}")
            renamed += 1
            time.sleep(0.3)
        except Exception as exc:
            print(f"FAIL RENAME {label}: {exc}", file=sys.stderr)

    print(f"DEDUPE_DONE deleted={deleted} renamed={renamed} dry={args.dry_run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
