#!/usr/bin/env python3
"""Curate Skylight recipes: fix bb-pdc20 Sidekick bodies + polish household recipes."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from skylight_recipe_lib import (  # noqa: E402
    BB_SNAPSHOT,
    category_for_bb_file,
    delete_recipe,
    extract_sidekick_from_markdown,
    household_category,
    list_categories,
    list_recipes,
    normalize_household_description,
    parse_title,
    update_recipe,
)

DELETE_TITLES = {
    "Sourdough Bread for Zojirushi",  # superseded by bb-pdc20 sourdough set
    "Easy Fluffy Pancakes",  # merged into Pancakes
}

RENAME = {
    "Pizza": "English Muffin Pizza",
    "Chick-fil-A Crispy Chicken Sandwich Copycat": "Crispy Chicken Sandwich",
    "The Best Chocolate Chip Cookie Recipe Ever": "Chocolate Chip Cookies",
    "Best Homemade Brownies": "Homemade Brownies",
    "OATMEAL YOGURT PANCAKES WITH BLACKBERRY CRUSH": "Oatmeal Yogurt Pancakes with Blackberry Crush",
    "Easy Black Bean Chicken Soup (One Pot, High Protein)": "Black Bean Chicken Soup",
    "Easy Homemade Biscuits": "Homemade Biscuits",
    "Brownies - Homemade": "Homemade Brownies",
    "Avocado Vegi Roll": "Avocado Veggie Roll",
}


def load_bb_index(snapshot: Path) -> dict[str, Path]:
    manifest = json.loads((snapshot / "manifest.json").read_text())
    idx: dict[str, Path] = {}
    for r in manifest.get("recipes", []):
        p = snapshot / r["file"]
        if p.is_file():
            idx[r["title"]] = p
    return idx


def merge_pancakes(recipes: list[dict]) -> tuple[str | None, str | None]:
    """Return (keep_id, delete_id) for pancake merge."""
    by_title = {(r.get("attributes") or {}).get("summary"): r for r in recipes}
    fluffy = by_title.get("Easy Fluffy Pancakes")
    basic = by_title.get("Pancakes")
    if not fluffy or not basic:
        return None, None
    body = (fluffy.get("attributes") or {}).get("description") or ""
    merged = normalize_household_description("Pancakes", body)
    return basic["id"], merged


def dedupe_by_title(
    recipes: list[dict],
    bb_titles: set[str],
    *,
    frame_id: str,
    auth: str,
    api_url: str,
    dry_run: bool,
) -> int:
    from collections import defaultdict

    by_title: dict[str, list[dict]] = defaultdict(list)
    for r in recipes:
        title = (r.get("attributes") or {}).get("summary") or ""
        if title:
            by_title[title].append(r)

    deleted = 0
    for title, group in sorted(by_title.items()):
        if len(group) < 2:
            continue

        def keep_score(r: dict) -> tuple:
            in_bb = title in bb_titles
            rid = str(r.get("id") or "0")
            try:
                num = int(rid)
            except ValueError:
                num = 0
            return (in_bb, num)

        group.sort(key=keep_score, reverse=True)
        keep = group[0]
        for dup in group[1:]:
            dup_id = dup["id"]
            if dry_run:
                print(f"DRY DEDUPE delete {title!r} id={dup_id} (keep {keep['id']})")
            else:
                delete_recipe(frame_id, auth, api_url, str(dup_id))
                print(f"DEDUPED delete {title!r} id={dup_id} (keep {keep['id']})")
                time.sleep(0.3)
            deleted += 1
    return deleted


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--bb-only", action="store_true")
    ap.add_argument("--household-only", action="store_true")
    ap.add_argument("--dedupe-only", action="store_true", help="Remove duplicate recipe titles only")
    ap.add_argument("--snapshot", type=Path, default=BB_SNAPSHOT)
    args = ap.parse_args()

    frame_id = os.environ["SKYLIGHT_FRAME_ID"]
    auth = os.environ["SKYLIGHT_AUTHORIZATION"]
    api_url = os.environ.get("SKYLIGHT_API_URL", "https://app.ourskylight.com/api")

    bb_index = load_bb_index(args.snapshot)
    bb_titles = set(bb_index)
    recipes = list_recipes(frame_id)

    if args.dedupe_only:
        deleted = dedupe_by_title(
            recipes,
            bb_titles,
            frame_id=frame_id,
            auth=auth,
            api_url=api_url,
            dry_run=args.dry_run,
        )
        print(f"DEDUPE_DONE deleted={deleted} dry={args.dry_run}")
        return 0

    cats = list_categories(frame_id)

    updated = 0
    deleted = 0
    skipped = 0

    # Titles already present on the frame (for rename-collision deletes)
    existing_titles = {
        (r.get("attributes") or {}).get("summary") or ""
        for r in recipes
    }

    # Pancakes merge (before delete pass)
    keep_id, merged_body = merge_pancakes(recipes)
    if keep_id and merged_body and not args.bb_only:
        cat = cats[household_category("Pancakes") or "Breakfast"]
        if args.dry_run:
            print(f"DRY UPDATE Pancakes (merged from Easy Fluffy) id={keep_id}")
        else:
            update_recipe(frame_id, auth, api_url, keep_id, "Pancakes", merged_body, cat)
            print(f"UPDATED Pancakes (merged) id={keep_id}")
            updated += 1
            time.sleep(0.3)

    for r in recipes:
        rid = r["id"]
        attrs = r.get("attributes") or {}
        title = attrs.get("summary") or ""
        body = attrs.get("description") or ""
        rel = r.get("relationships", {}).get("meal_category", {}).get("data", {})
        cur_cat_id = rel.get("id")
        cur_cat = next((k for k, v in cats.items() if v == cur_cat_id), "?")

        if title in DELETE_TITLES and not args.bb_only:
            if args.dry_run:
                print(f"DRY DELETE {title!r} id={rid}")
            else:
                delete_recipe(frame_id, auth, api_url, rid)
                print(f"DELETED {title!r} id={rid}")
                deleted += 1
                time.sleep(0.3)
            continue

        new_title = RENAME.get(title, title)

        # Rename would collide with an existing recipe → drop the old title instead
        if (
            not args.bb_only
            and new_title != title
            and new_title in existing_titles
            and title not in bb_titles
        ):
            if args.dry_run:
                print(f"DRY DELETE {title!r} id={rid} (rename collides with {new_title!r})")
            else:
                delete_recipe(frame_id, auth, api_url, rid)
                print(f"DELETED {title!r} id={rid} (kept existing {new_title!r})")
                deleted += 1
                time.sleep(0.3)
            continue

        if title in bb_titles and not args.household_only:
            path = bb_index[title]
            new_body = extract_sidekick_from_markdown(
                path.read_text(encoding="utf-8"), title=new_title
            )
            new_cat = cats[category_for_bb_file(path)]
            if body == new_body and cur_cat == category_for_bb_file(path) and new_title == title:
                skipped += 1
                continue
            if args.dry_run:
                print(f"DRY BB {title!r} -> cat={category_for_bb_file(path)} len={len(new_body)}")
            else:
                update_recipe(frame_id, auth, api_url, rid, new_title, new_body, new_cat)
                print(f"UPDATED BB {new_title!r} id={rid} cat={category_for_bb_file(path)}")
                updated += 1
                time.sleep(0.3)
            continue

        if title in bb_titles or args.bb_only:
            continue

        new_body = normalize_household_description(new_title, body)
        pref_cat = household_category(new_title) or household_category(title)
        new_cat_id = cats[pref_cat] if pref_cat else cur_cat_id

        if new_body == body and new_title == title and new_cat_id == cur_cat_id:
            skipped += 1
            continue

        if args.dry_run:
            print(f"DRY HOUSE {title!r} -> {new_title!r} cat={pref_cat or cur_cat}")
        else:
            update_recipe(frame_id, auth, api_url, rid, new_title, new_body, new_cat_id)
            print(f"UPDATED HOUSE {new_title!r} id={rid}")
            updated += 1
            time.sleep(0.3)

    print(f"CURATION_DONE updated={updated} deleted={deleted} skipped={skipped} dry={args.dry_run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
