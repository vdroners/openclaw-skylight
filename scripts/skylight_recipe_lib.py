#!/usr/bin/env python3
"""Parse and normalize Skylight Sidekick recipe text."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

BOILERPLATE_RE = re.compile(r"^Copy everything below.*$", re.I | re.M)

SECTION_CATEGORY: dict[str, str] = {
    "01-white": "Snack",
    "02-wholewheat": "Snack",
    "03-european": "Snack",
    "04-multigrain": "Snack",
    "05-gluten-free": "Snack",
    "06-salt-free": "Snack",
    "07-sugar-free": "Snack",
    "08-vegan": "Snack",
    "09-rapid-white": "Snack",
    "10-rapid-wholewheat": "Snack",
    "11-dough": "Dinner",
    "12-sourdough": "Snack",
    "13-cake": "Snack",
    "14-jam": "Snack",
    "15-homemade": "Snack",
}

DINNER_HOMEMADE = {
    "Meatloaf Miracle",
    "Homemade Pasta",
    "Tomato Pasta",
    "Gluten Free Dinner Bread",
    "Homemade Butter Rolls",
}


def parse_title(text: str, fallback: str) -> str:
    m = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', text, re.M)
    return m.group(1).strip() if m else fallback


def strip_sidekick_boilerplate(text: str) -> str:
    text = BOILERPLATE_RE.sub("", text)
    lines = [ln for ln in text.splitlines()]
    while lines and not lines[0].strip():
        lines.pop(0)
    return "\n".join(lines).strip()


def extract_sidekick_from_markdown(text: str, title: str | None = None) -> str:
    block = re.search(r"## Sidekick import\s*\n(.*?)(?:\n## |\Z)", text, re.S)
    if block:
        desc = strip_sidekick_boilerplate(block.group(1).strip())
    else:
        body = re.sub(r"^---\s*\n.*?\n---\s*\n", "", text, count=1, flags=re.S)
        desc = body.strip()[:8000]
    if title:
        lines = desc.splitlines()
        if lines and lines[0].strip() == title:
            lines = lines[1:]
            while lines and not lines[0].strip():
                lines.pop(0)
            desc = "\n".join(lines).strip()
    return desc


def category_for_bb_file(path: Path) -> str:
    section = path.parts[-2] if len(path.parts) >= 2 else ""
    title = path.stem.replace("-", " ").title()
    if section == "15-homemade":
        # Re-read title from file if possible
        pass
    cat = SECTION_CATEGORY.get(section, "Snack")
    if section == "15-homemade":
        try:
            t = parse_title(path.read_text(encoding="utf-8"), path.stem)
            if t in DINNER_HOMEMADE:
                return "Dinner"
        except OSError:
            pass
    return cat


def normalize_household_description(title: str, body: str) -> str:
    if not (body or "").strip():
        if title == "Leftovers":
            return (
                "Leftovers night\n\n"
                "Ingredients:\n- Leftover portions from the fridge\n\n"
                "Instructions:\n"
                "1. Reheat leftovers safely (165°F / 74°C for poultry and leftovers).\n"
                "2. Serve with a simple side salad or fruit if needed.\n"
                "3. Clear dated containers after the meal."
            )
        return body

    body = strip_sidekick_boilerplate(body)
    notes: list[str] = []
    ing_lines: list[str] = []
    instr_lines: list[str] = []
    pre_lines: list[str] = []
    section = None

    for ln in body.splitlines():
        s = ln.strip()
        if s.startswith("Source:"):
            url = s[7:].strip()
            if url:
                notes.append(url)
            continue
        if re.match(r"^Ingredients:\s*$", s, re.I):
            section = "ing"
            continue
        if re.match(r"^(Instructions|Directions):\s*$", s, re.I):
            section = "instr"
            continue
        if section == "ing":
            if s.startswith(("- ", "* ")):
                ing_lines.append("- " + s.lstrip("-* ").strip())
            elif re.match(r"^\d", s) or s.startswith("For "):
                ing_lines.append("- " + s)
            elif s:
                ing_lines.append("- " + s)
        elif section == "instr":
            if not s:
                continue
            if re.match(r"^\d+\.", s) or s.startswith(("- ", "* ")):
                instr_lines.append(re.sub(r"^\*\s+", "- ", s))
            elif len(s) > 100 and "!" in s and "recipe" in s.lower():
                continue  # drop marketing fluff
            else:
                instr_lines.append(s)
        else:
            if s and title.lower() not in s.lower():
                if not (len(s) > 120 and "!" in s):
                    pre_lines.append(s)

    out: list[str] = [title, ""]
    if pre_lines:
        out.extend(pre_lines[:4])
        out.append("")
    out.append("Ingredients:")
    out.extend(ing_lines or ["- See instructions"])
    out.append("")
    out.append("Instructions:")
    if instr_lines:
        # Renumber if lines already numbered
        out.extend(instr_lines)
    else:
        out.append("1. Follow the steps above.")
    if notes:
        out.append("")
        out.append("Notes:")
        for n in notes[:2]:
            out.append(f"- Source: {n}")
    return "\n".join(out).strip()


def household_category(title: str) -> str | None:
    """Return preferred category or None to keep existing."""
    mapping = {
        "Milk & Cereal": "Breakfast",
        "Eggs": "Breakfast",
        "Pancakes": "Breakfast",
        "Oatmeal": "Breakfast",
        "Sourdough Discard Pancakes": "Breakfast",
        "Grilled Cheese": "Lunch",
        "Salad": "Lunch",
        "Soup": "Lunch",
        "Wraps": "Lunch",
        "English Muffin Pizza": "Lunch",
        "Leftovers": "Lunch",
        "Carrots and Hummus": "Snack",
        "Cheese and Crackers": "Snack",
        "Best Homemade Brownies": "Snack",
        "Brownie Batter Chia Pudding": "Snack",
        "The Best Chocolate Chip Cookie Recipe Ever": "Snack",
        "Green Chicken Enchilada Soup": "Dinner",
        "Sushi Rice": "Dinner",
        "Avocado Vegi Roll": "Dinner",
        "Miso Glazed Salmon": "Dinner",
        "Wood Ear Mushroom Salad 凉拌木耳": "Dinner",
        "Mediterranean Chicken and Orzo": "Dinner",
        "Greek Yogurt Chicken Skewers with Lemon Herb Couscous": "Dinner",
        "Baked Cod with Roasted Mediterranean Vegetables and Quinoa": "Dinner",
        "Chick-fil-A Crispy Chicken Sandwich Copycat": "Dinner",
        "Chicken and Chickpea Salad": "Lunch",
    }
    return mapping.get(title)


def list_categories(frame_id: str) -> dict[str, str]:
    out = subprocess.check_output(
        ["skylight", "meals", "listCategories", "--frame-id", frame_id, "--json"],
        text=True,
    )
    data = json.loads(out)
    return {
        (c.get("attributes") or {}).get("label", ""): c["id"]
        for c in data.get("data", [])
    }


def list_recipes(frame_id: str) -> list[dict]:
    out = subprocess.check_output(
        ["skylight", "meals", "listRecipes", "--frame-id", frame_id, "--json"],
        text=True,
    )
    return json.loads(out).get("data", [])


def update_recipe(
    frame_id: str,
    auth: str,
    api_url: str,
    recipe_id: str,
    summary: str,
    description: str,
    category_id: str,
) -> None:
    import subprocess
    import tempfile

    payload = json.dumps(
        {
            "summary": summary,
            "description": description,
            "meal_category_id": category_id,
        }
    )
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as tf:
        tf.write(payload)
        tmp = tf.name
    url = f"{api_url.rstrip('/')}/frames/{frame_id}/meals/recipes/{recipe_id}"
    proc = subprocess.run(
        [
            "curl",
            "-sS",
            "-f",
            "-X",
            "PUT",
            "-H",
            f"Authorization: {auth}",
            "-H",
            "Content-Type: application/json",
            "--data-binary",
            f"@{tmp}",
            url,
        ],
        capture_output=True,
        text=True,
    )
    Path(tmp).unlink(missing_ok=True)
    if proc.returncode != 0:
        raise RuntimeError(f"PUT {recipe_id} failed: {proc.stderr or proc.stdout}")


def delete_recipe(frame_id: str, auth: str, api_url: str, recipe_id: str) -> None:
    import subprocess

    url = f"{api_url.rstrip('/')}/frames/{frame_id}/meals/recipes/{recipe_id}"
    proc = subprocess.run(
        [
            "curl",
            "-sS",
            "-f",
            "-X",
            "DELETE",
            "-H",
            f"Authorization: {auth}",
            url,
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"DELETE {recipe_id} failed: {proc.stderr or proc.stdout}")
