#!/usr/bin/env python3
"""Fill blank Skylight chore fields from household-model defaults + RRULE inference."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import date
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from skylight_chore_lib import (  # noqa: E402
    apply_chore_update,
    build_enrichment,
    chore_time_defaults,
    list_chore_series,
    load_model,
    reward_defaults,
)

OPENCLAW = Path(os.environ.get("OPENCLAW_DIR", Path.home() / ".openclaw"))
MODEL = Path(os.environ.get("HOUSEHOLD_MODEL_JSON", OPENCLAW / "config" / "household-model.json"))
SNAP = OPENCLAW / "state" / "chore-fill-snapshots"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--person", help="Only fill chores for this person (name from household-model kid_categories)")
    args = ap.parse_args()

    frame_id = os.environ["SKYLIGHT_FRAME_ID"]
    auth = os.environ["SKYLIGHT_AUTHORIZATION"]
    api = os.environ["SKYLIGHT_API_URL"]

    model = load_model(MODEL)
    td = chore_time_defaults(model)
    rd = reward_defaults(model)
    kid_map = model.get("kid_categories") or {}
    person_filter = args.person.strip().lower() if args.person else None

    rows = list_chore_series(frame_id, model=model)
    if not args.dry_run:
        SNAP.mkdir(parents=True, exist_ok=True)

    applied = 0
    skipped = 0
    for row in rows:
        person = row.get("person") or kid_map.get(row.get("category_id"), "?")
        if person_filter and person.lower() != person_filter:
            continue

        fields = build_enrichment(row, td, rd, set(kid_map.keys()))
        if not fields:
            skipped += 1
            continue

        label = f"{person}: {row['summary']}"
        detail = (
            f"start={fields.get('start_time', row.get('start_time') or '-')} "
            f"routine={fields.get('routine', row.get('routine'))} "
            f"points={fields.get('reward_points')}"
        )
        if args.dry_run:
            print(f"DRY {label} -> {detail}")
            applied += 1
            continue

        cur = row["_raw"]
        snap = SNAP / f"{row['group_id']}-{date.today().isoformat()}-pre.json"
        if not snap.is_file():
            snap.write_text(json.dumps(cur, indent=2))
        try:
            apply_chore_update(frame_id, auth, api, row["group_id"], fields, cur)
            print(f"APPLIED {label} -> {detail}")
            applied += 1
            time.sleep(0.25)
        except Exception as exc:
            print(f"FAIL {label}: {exc}", file=sys.stderr)

    print(f"CHORE_FILL_DONE applied={applied} skipped={skipped} dry={args.dry_run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
