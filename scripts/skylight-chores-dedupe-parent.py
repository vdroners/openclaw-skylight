#!/usr/bin/env python3
"""Consolidate duplicate parent-member monthly chores using household-model config."""
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


def load_dedupe_config() -> tuple[str, list[str], dict[str, str]]:
    model_path = os.environ.get("HOUSEHOLD_MODEL_JSON") or str(
        OPENCLAW / "config" / "household-model.json"
    )
    if not Path(model_path).is_file():
        print(f"DEDUPE_SKIP no model at {model_path}", file=sys.stderr)
        return "Parent", [], {}

    model = json.loads(Path(model_path).read_text())
    dedupe = model.get("parent_chore_dedupe") or {}
    legacy = model.get("parent_chore_canonical") or model.get("mom_chore_canonical") or {}

    member_label = str(dedupe.get("member_label") or "Parent")
    delete_ids = [str(x) for x in dedupe.get("delete_group_ids") or []]
    keep_renames = {str(k): str(v) for k, v in (dedupe.get("keep_renames") or legacy).items()}
    return member_label, delete_ids, keep_renames


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

    member_label, delete_ids, keep_renames = load_dedupe_config()
    if not delete_ids and not keep_renames:
        print("DEDUPE_DONE deleted=0 renamed=0 dry=True (no parent_chore_dedupe config)")
        return 0

    frame_id = os.environ["SKYLIGHT_FRAME_ID"]
    auth = os.environ["SKYLIGHT_AUTHORIZATION"]
    api = os.environ["SKYLIGHT_API_URL"]

    model = {}
    model_path = os.environ.get("HOUSEHOLD_MODEL_JSON") or str(OPENCLAW / "config" / "household-model.json")
    if Path(model_path).is_file():
        model = json.loads(Path(model_path).read_text())

    rows = {r["group_id"]: r for r in list_chore_series(frame_id, model=model)}
    if not args.dry_run:
        SNAP.mkdir(parents=True, exist_ok=True)

    deleted = 0
    for gid in delete_ids:
        row = rows.get(gid)
        if not row:
            print(f"SKIP delete {gid}: not found")
            continue
        label = f"{member_label}: {row['summary']} ({gid})"
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
    for gid, title in keep_renames.items():
        row = rows.get(gid)
        if not row:
            print(f"SKIP rename {gid}: not found")
            continue
        if row["summary"] == title:
            continue
        label = f"{member_label}: {row['summary']} -> {title}"
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
