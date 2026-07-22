#!/usr/bin/env python3
"""Household chore expansion: dry-run table + direct Skylight writes.

Plan: Dan dishwasher/litter/kitchen deep cleans, Phoebe polish, Wesley
checklists, Mom piano (keep if present). Skip Pill (leave as-is).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from skylight_chore_lib import (  # noqa: E402
    apply_chore_update,
    create_chore_series,
    find_series_chore,
    list_chore_series,
    load_model,
)


def done(*bullets: str) -> str:
    lines = ["Done when:"]
    lines.extend(f"- {b}" for b in bullets)
    return "\n".join(lines)


# --- Checklists ---
CHECKLISTS: dict[str, str] = {
    "Kitchen counters": done(
        "Wipe counters + stove top",
        "Clear crumbs / sticky spots",
        "Sink clear of dirty dishes (load dishwasher if space)",
    ),
    "Start dishwasher": done(
        "Load leftover dirty dishes",
        "Add detergent",
        "Start the wash cycle",
    ),
    "Take out trash": done(
        "Bag kitchen trash (and full bathroom if needed)",
        "Replace liners",
        "Bins back in place",
    ),
    "Empty litter (dump tray)": done(
        "Empty auto-scooper dump tray into bag",
        "Tie bag and put in outdoor trash",
        "Wipe tray rim if dusty",
    ),
    "Deep clean litter box": done(
        "Empty dump tray",
        "Wipe / scoop stuck litter from box surfaces",
        "Refresh litter as needed; put tools away",
    ),
    "Vacuum (deep)": done(
        "Vacuum main floors + high-traffic rugs",
        "Empty canister / bag if full",
        "Put vacuum away",
    ),
    "Toilet": done(
        "Clean bowl + seat + rim",
        "Wipe sink / faucet nearby if used",
        "Replace empty TP if needed",
    ),
    "Windows/Mirrors": done(
        "Clean assigned windows / mirrors streak-free",
        "Wipe sills",
        "Put supplies away",
    ),
    "Mop": done(
        "Sweep or vacuum first if needed",
        "Mop kitchen + main hard floors",
        "Rinse mop; put away",
    ),
    "Change sheets": done(
        "Strip bed; put dirty sheets in laundry",
        "Put on clean sheets + pillowcases",
        "Make bed",
    ),
    "Clip murderpaws": done(
        "Clip cat claws carefully (all paws)",
        "Reward / calm cats after",
        "Put clippers away",
    ),
    "Clean fridge": done(
        "Toss expired food",
        "Wipe shelves + drawers",
        "Restock neatly; wipe door seals if sticky",
    ),
    "Clean kitchen drawers": done(
        "Empty one section at a time",
        "Wipe crumbs / spills",
        "Return items organized",
    ),
    "Stove and oven deep clean": done(
        "Wipe stove top + knobs",
        "Clean oven interior (self-clean or manual)",
        "Wipe oven door glass; put racks back",
    ),
    "Put away clean dishes": done(
        "Unload clean dishwasher / drying rack",
        "Put dishes in cabinets",
        "Leave sink clear",
    ),
    "Feed/water cats": done(
        "Fill food bowls",
        "Refresh water bowls",
        "Quick litter check (tell adult if dump tray full)",
    ),
    "Clean Bathroom sink/counter": done(
        "Clear clutter from counters",
        "Wipe sink + faucet + counters",
        "Hang towels neat",
    ),
    "Tub": done(
        "Rinse tub / shower walls",
        "Scrub soap scum; rinse",
        "Wipe faucet; hang mat/towel",
    ),
    "Practice Bassoon": done(
        "Practice assigned pieces / scales",
        "Put instrument away safely",
        "Mark practice done in log if used",
    ),
    "Clean Room": done(
        "Clothes in hamper or put away",
        "Floor clear of clutter",
        "Bed made / surfaces tidy",
    ),
    "Practice Math": done(
        "Complete assigned practice",
        "Show work if needed",
        "Put materials away",
    ),
    "Read book": done(
        "Read for the time / pages set",
        "Bookmark page",
        "Put book away",
    ),
    "Dust": done(
        "Dust assigned surfaces / shelves",
        "Shake cloth outside if needed",
        "Put supplies away",
    ),
    "Laundry": done(
        "Start or move a load as assigned",
        "Move clean clothes to fold/hang",
        "Empty lint trap if dryer used",
    ),
    "Run": done(
        "Complete the scheduled run / outdoor time",
        "Stretch briefly after",
        "Put shoes away",
    ),
    "Brush teeth": done(
        "Brush teeth thoroughly",
        "Rinse sink",
        "Put toothbrush away",
    ),
    "Clean room": done(
        "Toys / clothes off the floor",
        "Bed area tidy",
        "Put dirty clothes in hamper",
    ),
    "Put away toys": done(
        "Pick up toys in shared spaces",
        "Return to bins / shelves",
        "Leave walkways clear",
    ),
    "Clean up shoes": done(
        "Shoes paired by the door / rack",
        "No shoes left mid-floor",
        "Muddy shoes wiped if needed",
    ),
    "Clean Shelf": done(
        "Clear shelf items carefully",
        "Dust / wipe shelf",
        "Return items neat",
    ),
    "Organize Knitting/Sewing": done(
        "Sort yarn / fabric / tools",
        "Put projects in labeled spots",
        "Clear work surface",
    ),
    "Clean Shelf & Piano Top": done(
        "Clear shelf + piano top",
        "Dust / wipe surfaces",
        "Return decor neatly (no clutter)",
    ),
}


def person_map(model: dict[str, Any]) -> dict[str, str]:
    """name -> category_id"""
    out: dict[str, str] = {}
    for cid, name in (model.get("kid_categories") or {}).items():
        out[str(name)] = str(cid)
    for cid, name in (model.get("parent_categories") or {}).items():
        out[str(name)] = str(cid)
    return out


def index_by_person(rows: list[dict[str, Any]]) -> dict[str, dict[str, dict[str, Any]]]:
    """person -> lower(summary) -> row"""
    out: dict[str, dict[str, dict[str, Any]]] = {}
    for r in rows:
        p = r.get("person") or "?"
        out.setdefault(p, {})[str(r.get("summary") or "").strip().lower()] = r
    return out


def build_plan(rows: list[dict[str, Any]], cats: dict[str, str]) -> list[dict[str, Any]]:
    by = index_by_person(rows)
    dan = by.get("Dan") or {}
    phoebe = by.get("Phoebe") or {}
    wesley = by.get("Wesley") or {}
    mom = by.get("Mom") or {}
    ops: list[dict[str, Any]] = []

    def upd(person: str, title_key: str, *, new_summary: str | None = None, **fields: Any) -> None:
        row = (by.get(person) or {}).get(title_key.lower())
        if not row:
            ops.append({
                "op": "MISSING",
                "person": person,
                "match": title_key,
                "note": f"series not found for update → {new_summary or title_key}",
                "fields": fields,
            })
            return
        summary = new_summary or row["summary"]
        f = dict(fields)
        if new_summary:
            f["summary"] = new_summary
        if "description" not in f:
            f["description"] = CHECKLISTS.get(summary) or CHECKLISTS.get(row["summary"])
        ops.append({
            "op": "UPDATE",
            "person": person,
            "group_id": row["group_id"],
            "from": row["summary"],
            "to": summary,
            "before": {
                "start_time": row.get("start_time"),
                "routine": row.get("routine"),
                "reward_points": row.get("reward_points"),
                "rrule": (row.get("recurrence_set") or [""])[0],
                "description": ((row.get("description") or "")[:40] or None),
            },
            "fields": f,
        })

    def create(person: str, summary: str, **fields: Any) -> None:
        f = dict(fields)
        f.setdefault("description", CHECKLISTS.get(summary))
        ops.append({
            "op": "CREATE",
            "person": person,
            "category_id": cats[person],
            "to": summary,
            "fields": f,
        })

    # --- Dan updates ---
    upd("Dan", "Kitchen counters",
        start_time="20:00", routine=True, reward_points=1,
        description=CHECKLISTS["Kitchen counters"])
    upd("Dan", "Take out trash",
        start_time="07:00", routine=False, reward_points=1,
        description=CHECKLISTS["Take out trash"])
    upd("Dan", "Deep Clean Cat Box", new_summary="Empty litter (dump tray)",
        start_time="10:00", routine=False, reward_points=1,
        recurrence_set=["RRULE:FREQ=DAILY;INTERVAL=4"],
        description=CHECKLISTS["Empty litter (dump tray)"])
    upd("Dan", "Vacuum (deep)",
        start_time="10:00", routine=False, reward_points=2,
        description=CHECKLISTS["Vacuum (deep)"])
    upd("Dan", "Toilet",
        start_time="10:00", routine=False, reward_points=2,
        description=CHECKLISTS["Toilet"])
    upd("Dan", "Windows/Mirrors",
        start_time="10:00", routine=False, reward_points=2,
        description=CHECKLISTS["Windows/Mirrors"])
    upd("Dan", "Mop",
        start_time="10:00", routine=False, reward_points=2,
        description=CHECKLISTS["Mop"])
    upd("Dan", "Change sheets",
        start_time="10:00", routine=False, reward_points=1,
        description=CHECKLISTS["Change sheets"])
    upd("Dan", "Clip murderpaws",
        start_time="10:00", routine=False, reward_points=1,
        description=CHECKLISTS["Clip murderpaws"])
    # Pill: skip

    # Dan creates (skip if already present)
    if "start dishwasher" not in dan:
        create("Dan", "Start dishwasher",
               start_time="20:00", routine=True, reward_points=1,
               recurrence_set="RRULE:FREQ=DAILY;INTERVAL=1")
    else:
        upd("Dan", "Start dishwasher",
            start_time="20:00", routine=True, reward_points=1)

    if "deep clean litter box" not in dan:
        create("Dan", "Deep clean litter box",
               start_time="10:00", routine=False, reward_points=2,
               recurrence_set="RRULE:FREQ=DAILY;INTERVAL=8")
    else:
        upd("Dan", "Deep clean litter box",
            start_time="10:00", routine=False, reward_points=2,
            recurrence_set=["RRULE:FREQ=DAILY;INTERVAL=8"])

    if "clean fridge" not in dan:
        create("Dan", "Clean fridge",
               start_time="10:00", routine=False, reward_points=2,
               recurrence_set="RRULE:FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=1")
    else:
        upd("Dan", "Clean fridge", start_time="10:00", routine=False, reward_points=2)

    if "clean kitchen drawers" not in dan:
        create("Dan", "Clean kitchen drawers",
               start_time="10:00", routine=False, reward_points=2,
               recurrence_set="RRULE:FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15")
    else:
        upd("Dan", "Clean kitchen drawers", start_time="10:00", routine=False, reward_points=2)

    if "stove and oven deep clean" not in dan:
        create("Dan", "Stove and oven deep clean",
               start_time="10:00", routine=False, reward_points=2,
               recurrence_set="RRULE:FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=1")
    else:
        upd("Dan", "Stove and oven deep clean",
            start_time="10:00", routine=False, reward_points=2,
            recurrence_set=["RRULE:FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=1"])

    # --- Phoebe ---
    upd("Phoebe", "Dishes", new_summary="Put away clean dishes",
        start_time="06:00", routine=True, reward_points=1,
        recurrence_set=["RRULE:FREQ=DAILY;INTERVAL=1;WKST=MO"],
        description=CHECKLISTS["Put away clean dishes"])
    upd("Phoebe", "Clean Bathroom sink/counter",
        start_time="10:00", routine=False, reward_points=1,
        recurrence_set=["RRULE:FREQ=WEEKLY;INTERVAL=1;WKST=SU;BYDAY=MO"],
        description=CHECKLISTS["Clean Bathroom sink/counter"])
    upd("Phoebe", "Tub",
        start_time="10:00", routine=False, reward_points=1,
        recurrence_set=["RRULE:FREQ=WEEKLY;INTERVAL=1;WKST=SU;BYDAY=MO"],
        description=CHECKLISTS["Tub"])
    upd("Phoebe", "Practice Basson", new_summary="Practice Bassoon",
        start_time="14:00", routine=True, reward_points=1,
        description=CHECKLISTS["Practice Bassoon"])
    for title in (
        "Feed/water cats", "Clean Room", "Practice Math", "Read book",
        "Dust", "Laundry", "Run",
    ):
        if title.lower() in phoebe:
            upd("Phoebe", title, description=CHECKLISTS[title])

    # --- Wesley ---
    for title in ("Brush teeth", "Clean room", "Put away toys", "Clean up shoes"):
        if title.lower() in wesley:
            upd("Wesley", title, description=CHECKLISTS[title])

    # --- Mom ---
    for title in ("Clean Shelf", "Organize Knitting/Sewing", "Clean Shelf & Piano Top"):
        if title.lower() in mom:
            upd("Mom", title,
                start_time="10:00", routine=False, reward_points=2,
                description=CHECKLISTS[title])
        elif title == "Clean Shelf & Piano Top":
            create("Mom", title,
                   start_time="10:00", routine=False, reward_points=2,
                   recurrence_set="RRULE:FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15")

    return ops


def print_table(ops: list[dict[str, Any]]) -> None:
    print("\n## Chore expansion dry-run\n")
    print("| op | person | from → to | schedule / pts | notes |")
    print("|----|--------|-----------|----------------|-------|")
    for o in ops:
        op = o["op"]
        person = o["person"]
        if op == "CREATE":
            f = o["fields"]
            sched = f.get("recurrence_set") or ""
            pts = f.get("reward_points")
            st = f.get("start_time")
            print(
                f"| CREATE | {person} | → **{o['to']}** | "
                f"{st} pts={pts} `{sched}` | new series |"
            )
        elif op == "MISSING":
            print(f"| MISSING | {person} | {o['match']} | — | {o['note']} |")
        else:
            f = o["fields"]
            b = o["before"]
            bits = []
            if f.get("summary") and f["summary"] != o["from"]:
                bits.append(f"rename")
            if "reward_points" in f and f["reward_points"] != b.get("reward_points"):
                bits.append(f"pts {b.get('reward_points')}→{f['reward_points']}")
            if "start_time" in f and f["start_time"] != b.get("start_time"):
                bits.append(f"time {b.get('start_time')}→{f['start_time']}")
            if "recurrence_set" in f:
                new_r = f["recurrence_set"]
                if isinstance(new_r, list):
                    new_r = new_r[0] if new_r else ""
                if new_r != b.get("rrule"):
                    bits.append(f"rrule→`{new_r}`")
            if f.get("description"):
                bits.append("checklist")
            note = ", ".join(bits) or "touch"
            print(
                f"| UPDATE | {person} | {o['from']} → **{o['to']}** | "
                f"gid={o['group_id']} | {note} |"
            )
    print(f"\nTotal ops: {len(ops)} "
          f"(create={sum(1 for o in ops if o['op']=='CREATE')}, "
          f"update={sum(1 for o in ops if o['op']=='UPDATE')}, "
          f"missing={sum(1 for o in ops if o['op']=='MISSING')})")
    print("Pill: skipped (leave as-is).")


def apply_ops(
    ops: list[dict[str, Any]],
    *,
    frame_id: str,
    auth: str,
    api_url: str,
    raw_by_gid: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for o in ops:
        if o["op"] == "MISSING":
            results.append({**o, "status": "skipped_missing"})
            continue
        try:
            if o["op"] == "CREATE":
                f = o["fields"]
                gid = create_chore_series(
                    frame_id,
                    o["category_id"],
                    o["to"],
                    recurrence_set=f["recurrence_set"],
                    start_time=f.get("start_time"),
                    routine=bool(f.get("routine")),
                    reward_points=int(f.get("reward_points") or 1),
                    description=f.get("description"),
                    auth=auth,
                    api_url=api_url,
                )
                results.append({**o, "status": "ok", "group_id": gid})
                print(f"CREATE ok {o['person']}/{o['to']} gid={gid}")
            else:
                cur = raw_by_gid.get(str(o["group_id"]))
                if not cur:
                    raise RuntimeError(f"no raw row for {o['group_id']}")
                apply_chore_update(
                    frame_id, auth, api_url, str(o["group_id"]), o["fields"], cur,
                )
                results.append({**o, "status": "ok"})
                print(f"UPDATE ok {o['person']}/{o['to']} gid={o['group_id']}")
            time.sleep(0.35)
        except Exception as e:  # noqa: BLE001
            results.append({**o, "status": "fail", "error": str(e)})
            print(f"FAIL {o.get('op')} {o.get('to')}: {e}", file=sys.stderr)
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument(
        "--model",
        default=str(Path.home() / ".openclaw/config/household-model.json"),
    )
    args = ap.parse_args()
    if not args.dry_run and not args.apply:
        args.dry_run = True

    model = load_model(Path(args.model))
    frame_id = os.environ.get("SKYLIGHT_FRAME_ID") or str(model.get("frame_id") or "")
    if not frame_id:
        print("SKYLIGHT_FRAME_ID missing", file=sys.stderr)
        return 1

    # Include Mom in list_chore_series person map
    model_list = dict(model)
    model_list["kid_categories"] = {
        **(model.get("kid_categories") or {}),
        **(model.get("parent_categories") or {}),
    }
    rows = list_chore_series(frame_id, days=90, model=model_list)
    for r in rows:
        a = (r.get("_raw") or {}).get("attributes") or {}
        r["description"] = a.get("description")

    cats = person_map(model)
    ops = build_plan(rows, cats)
    print_table(ops)

    snap_dir = Path.home() / ".openclaw/state/chore-expansion-snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)
    plan_path = snap_dir / "expansion-plan.json"
    plan_path.write_text(json.dumps(ops, indent=2, default=str))
    print(f"\nWrote plan → {plan_path}")

    if args.dry_run and not args.apply:
        return 0

    auth = os.environ.get("SKYLIGHT_AUTHORIZATION") or ""
    api_url = os.environ.get("SKYLIGHT_API_URL") or "https://app.ourskylight.com/api"
    if not auth:
        print("SKYLIGHT_AUTHORIZATION missing", file=sys.stderr)
        return 1

    raw_by_gid = {str(r["group_id"]): r["_raw"] for r in rows if r.get("_raw")}
    results = apply_ops(
        ops, frame_id=frame_id, auth=auth, api_url=api_url, raw_by_gid=raw_by_gid,
    )
    out = snap_dir / "expansion-apply-results.json"
    out.write_text(json.dumps(results, indent=2, default=str))
    fails = [r for r in results if r.get("status") == "fail"]
    print(f"\nApplied: ok={sum(1 for r in results if r.get('status')=='ok')} "
          f"fail={len(fails)} → {out}")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
