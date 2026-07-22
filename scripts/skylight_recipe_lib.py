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
    "16-web-adaptations": "Snack",
}

DINNER_HOMEMADE = {
    "Meatloaf Miracle",
    "Homemade Pasta",
    "Tomato Pasta",
    "Gluten Free Dinner Bread",
    "Homemade Butter Rolls",
}


_SMALL_WORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "but",
    "by",
    "for",
    "from",
    "in",
    "nor",
    "of",
    "on",
    "or",
    "the",
    "to",
    "vs",
    "with",
}

_ACRONYMS = {"BB", "PDX", "PCU", "NCSC", "BBQ", "GF"}


def parse_title(text: str, fallback: str) -> str:
    m = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', text, re.M)
    return m.group(1).strip() if m else fallback


def title_case_recipe(title: str) -> str:
    """Title-case a recipe name; preserve & / Chinese / known acronyms."""
    if not title:
        return title
    # Already mixed-case and not ALL CAPS — keep, just strip
    if not title.isupper() and any(c.islower() for c in title):
        return title.strip()

    def _word(w: str, idx: int) -> str:
        if not w:
            return w
        # Keep non-latin spans as-is
        if any(ord(c) > 127 for c in w):
            return w
        core = re.sub(r"[^A-Za-z0-9]", "", w)
        if core.upper() in _ACRONYMS:
            return w.upper() if w.isalpha() else w
        low = w.lower()
        alpha = re.sub(r"[^a-z]", "", low)
        if idx > 0 and alpha in _SMALL_WORDS:
            return low
        # Handle hyphenated / slash words
        parts = re.split(r"([-/])", w)
        out = []
        for p in parts:
            if p in "-/":
                out.append(p)
            elif not p:
                continue
            else:
                out.append(p[:1].upper() + p[1:].lower() if p else p)
        return "".join(out)

    words = title.strip().split()
    return " ".join(_word(w, i) for i, w in enumerate(words))


def soften_caps_line(s: str) -> str:
    """Title-case an ALL-CAPS line; leave mixed-case alone."""
    if not s:
        return s
    letters = [c for c in s if c.isalpha()]
    if len(letters) >= 4 and all(c.isupper() for c in letters):
        return title_case_recipe(s)
    return s


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
    cat = SECTION_CATEGORY.get(section, "Snack")
    if section == "15-homemade":
        try:
            t = parse_title(path.read_text(encoding="utf-8"), path.stem)
            if t in DINNER_HOMEMADE:
                return "Dinner"
        except OSError:
            pass
    return cat


def _looks_like_amount_line(s: str) -> bool:
    return bool(
        re.match(
            r"^("
            r"\d|"
            r"[¼½¾⅓⅔⅛⅜⅝⅞]|"
            r"\d+\s*/\s*\d|"
            r"to taste|"
            r"drizzle|"
            r"pinch|"
            r"for\b"
            r")",
            s,
            re.I,
        )
    )


def _parse_allcaps_cookbook(body: str) -> tuple[list[str], list[str]]:
    """Fallback for ALL-CAPS blog/cookbook dumps with section headers."""
    ing: list[str] = []
    instr: list[str] = []
    mode = "ing"
    for ln in body.splitlines():
        s = ln.strip()
        if not s:
            continue
        if re.match(r"^TO MAKE\b", s, re.I):
            mode = "instr"
            soft = soften_caps_line(s)
            soft = re.sub(r"^To Make\b", "Make", soft, flags=re.I)
            instr.append(soft.rstrip(":"))
            continue
        letters = [c for c in s if c.isalpha()]
        is_header = (
            len(letters) >= 4
            and all(c.isupper() for c in letters)
            and not _looks_like_amount_line(s)
            and len(s) < 40
        )
        if is_header and mode == "ing":
            ing.append(f"- For {title_case_recipe(s)}:")
            continue
        if mode == "ing":
            if _looks_like_amount_line(s) or s.isupper():
                ing.append("- " + soften_caps_line(s))
            else:
                mode = "instr"
                instr.append(soften_caps_line(s))
        else:
            instr.append(soften_caps_line(s))
    return ing, instr


def normalize_household_description(title: str, body: str) -> str:
    title = title.strip()
    if not (body or "").strip():
        if title == "Leftovers":
            return (
                f"{title}\n\n"
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
        if not s:
            continue
        if re.match(r"^Source:\s*", s, re.I):
            url = re.sub(r"^Source:\s*", "", s, flags=re.I).strip()
            if url:
                notes.append(url)
            continue
        # Ingredients: or Ingredients (for BB-CEC20):
        if re.match(r"^Ingredients\b", s, re.I):
            section = "ing"
            continue
        if re.match(r"^(Instructions|Directions)\s*:?\s*$", s, re.I):
            section = "instr"
            continue
        if re.match(r"^How to Make\b", s, re.I):
            section = "instr"
            continue
        if section == "ing":
            # Skip "for quantities see recipe card" fluff / checkbox remnants
            if re.search(r"recipe card|see below|bottom of the page", s, re.I):
                continue
            if s.startswith(("▢", "☐", "☑", "□")):
                soft = soften_caps_line(re.sub(r"^[▢☐☑□]\s*", "", s))
                ing_lines.append("- " + soft)
                continue
            soft = soften_caps_line(s)
            if soft.startswith(("- ", "* ")):
                ing_lines.append("- " + soft.lstrip("-* ").strip())
            elif re.match(r"^\d", soft) or soft.lower().startswith("for "):
                ing_lines.append("- " + soft)
            else:
                # Ingredient name + colon prose → keep name as bullet
                if ":" in soft and len(soft) > 40:
                    name = soft.split(":", 1)[0].strip()
                    if name and len(name) < 60:
                        ing_lines.append("- " + name)
                    continue
                ing_lines.append("- " + soft)
        elif section == "instr":
            soft = soften_caps_line(s)
            if re.match(r"^\d+\.", soft) or soft.startswith(("- ", "* ")):
                instr_lines.append(re.sub(r"^\*\s+", "- ", soft))
            elif len(soft) > 100 and "!" in soft and "recipe" in soft.lower():
                continue  # drop marketing fluff
            else:
                instr_lines.append(soft)
        else:
            soft = soften_caps_line(s)

            def _norm_title(x: str) -> str:
                x = x.lower().replace("vegi", "veggie")
                return re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "", x)

            # Skip title echo (including pre-rename spelling variants)
            if _norm_title(soft) == _norm_title(title):
                continue
            if title.lower() in soft.lower() and len(soft) < len(title) + 10:
                continue
            low = soft.lower()
            marketing = any(
                w in low
                for w in (
                    "delicious",
                    "perfect",
                    "weeknight",
                    "melt-in-your-mouth",
                    "yes please",
                )
            )
            if marketing and (len(soft) > 60 or "!" in soft):
                continue
            if len(soft) > 120 and "!" in soft:
                continue
            pre_lines.append(soft)

    # Fallback: ALL-CAPS cookbook dump with no Ingredients/Instructions labels
    if not ing_lines and not instr_lines:
        fb_ing, fb_instr = _parse_allcaps_cookbook(body)
        if fb_ing or fb_instr:
            ing_lines, instr_lines = fb_ing, fb_instr
            pre_lines = []

    # Prefer measured quantity lines over short name-only marketing lists
    if ing_lines:
        amountish = [
            x
            for x in ing_lines
            if _looks_like_amount_line(x.lstrip("- ")) or re.search(r"\d", x)
        ]
        namish = [x for x in ing_lines if x not in amountish]
        if len(amountish) >= 3 and namish:
            ing_lines = amountish

    out: list[str] = [title, ""]
    if pre_lines:
        out.extend(pre_lines[:3])
        out.append("")
    out.append("Ingredients:")
    out.extend(ing_lines or ["- See instructions"])
    out.append("")
    out.append("Instructions:")
    if instr_lines:
        # Renumber bare paragraphs into steps when none are numbered
        if not any(re.match(r"^\d+\.", ln) for ln in instr_lines):
            numbered = []
            n = 1
            for ln in instr_lines:
                if ln.startswith("- "):
                    numbered.append(ln)
                else:
                    numbered.append(f"{n}. {ln}")
                    n += 1
            out.extend(numbered)
        else:
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
        "Oatmeal Yogurt Pancakes with Blackberry Crush": "Breakfast",
        "Grilled Cheese": "Lunch",
        "Salad": "Lunch",
        "Soup": "Lunch",
        "Wraps": "Lunch",
        "English Muffin Pizza": "Lunch",
        "Leftovers": "Lunch",
        "Carrots and Hummus": "Snack",
        "Cheese and Crackers": "Snack",
        "Best Homemade Brownies": "Snack",
        "Homemade Brownies": "Snack",
        "Brownie Batter Chia Pudding": "Snack",
        "The Best Chocolate Chip Cookie Recipe Ever": "Snack",
        "Chocolate Chip Cookies": "Snack",
        "Homemade Biscuits": "Snack",
        "Banana Bread": "Snack",
        "Green Chicken Enchilada Soup": "Dinner",
        "Black Bean Chicken Soup": "Dinner",
        "Sushi Rice": "Dinner",
        "Avocado Vegi Roll": "Dinner",
        "Avocado Veggie Roll": "Dinner",
        "Miso Glazed Salmon": "Dinner",
        "Wood Ear Mushroom Salad 凉拌木耳": "Dinner",
        "Mediterranean Chicken and Orzo": "Dinner",
        "Greek Yogurt Chicken Skewers with Lemon Herb Couscous": "Dinner",
        "Baked Cod with Roasted Mediterranean Vegetables and Quinoa": "Dinner",
        "Chick-fil-A Crispy Chicken Sandwich Copycat": "Dinner",
        "Crispy Chicken Sandwich": "Dinner",
        "Chicken and Chickpea Salad": "Lunch",
        "Chinese Steamed Egg (蒸水蛋)": "Dinner",
    }
    return mapping.get(title)


BB_SNAPSHOT = Path.home() / ".cursor/snapshots/skylight-bb-pdc20-recipes"
WEB_ADAPTATIONS_SECTION = "16-web-adaptations"


def prep_type_from_markdown(text: str) -> str:
    m = re.search(r"^prep_type:\s*(\S+)\s*$", text, re.M)
    return m.group(1).strip() if m else "bread-machine"


def machine_line_ok(description: str, prep_type: str) -> bool:
    """True when Sidekick body documents machine course or manual oven path."""
    low = description.lower()
    if prep_type in ("hand-oven", "hand-mix"):
        return "oven:" in low or "not used" in low or "hand-mix" in low
    return "Course:" in description


def load_manifest(snapshot: Path | None = None) -> dict:
    snap = snapshot or BB_SNAPSHOT
    return json.loads((snap / "manifest.json").read_text(encoding="utf-8"))


def manifest_recipes(snapshot: Path | None = None, section: str | None = None) -> list[dict]:
    data = load_manifest(snapshot)
    rows = data.get("recipes", [])
    if section:
        rows = [r for r in rows if r.get("section") == section]
    return rows


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


def _yaml_scalar(text: str, key: str) -> str | None:
    m = re.search(rf"^{re.escape(key)}:\s*(.+?)\s*$", text, re.M)
    if not m:
        return None
    val = m.group(1).strip()
    if val.startswith('"') and val.endswith('"'):
        return val[1:-1]
    if val.startswith("'") and val.endswith("'"):
        return val[1:-1]
    return val


def _parse_crust_times(text: str) -> dict[str, str]:
    raw = _yaml_scalar(text, "crust_times")
    if not raw:
        return {}
    try:
        data = json.loads(raw.replace("'", '"'))
        return {str(k).lower(): str(v) for k, v in data.items()}
    except json.JSONDecodeError:
        return {}


def read_recipe_file(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    title = parse_title(text, path.stem.replace("-", " ").title())
    mc = _yaml_scalar(text, "machine_course")
    machine_course = None if mc in (None, "null") else int(mc)
    return {
        "path": path,
        "title": title,
        "id": path.stem,
        "section": path.parts[-2] if len(path.parts) >= 2 else "",
        "prep_type": prep_type_from_markdown(text),
        "machine_course": machine_course,
        "machine_course_name": _yaml_scalar(text, "machine_course_name") or "",
        "makes": _yaml_scalar(text, "makes") or "",
        "crust_times": _parse_crust_times(text),
        "machine_block": _extract_section(text, "## Machine"),
        "instructions": _extract_numbered_instructions(text),
    }


def _extract_section(text: str, heading: str) -> str:
    m = re.search(rf"{re.escape(heading)}\s*\n(.*?)(?:\n## |\Z)", text, re.S)
    if not m:
        return ""
    lines = []
    for ln in m.group(1).splitlines():
        s = ln.strip()
        if s.startswith("- "):
            lines.append(s[2:].strip())
    return "\n".join(lines)


def _extract_numbered_instructions(text: str) -> list[str]:
    m = re.search(r"## Instructions\s*\n(.*?)(?:\n---|\n## Sidekick|\Z)", text, re.S)
    if not m:
        return []
    steps = []
    for ln in m.group(1).splitlines():
        s = ln.strip()
        if re.match(r"^\d+\.", s):
            steps.append(re.sub(r"^\d+\.\s*", "", s))
    return steps


def manifest_index(snapshot: Path | None = None) -> list[dict]:
    snap = snapshot or BB_SNAPSHOT
    rows = manifest_recipes(snap)
    out = []
    for row in rows:
        rel = row.get("file") or ""
        path = snap / rel
        if not path.is_file():
            continue
        meta = read_recipe_file(path)
        meta["manifest_id"] = row.get("id")
        meta["manifest_section"] = row.get("section")
        out.append(meta)
    return out


def _score_match(query: str, meta: dict) -> int:
    q = query.lower().strip()
    if not q:
        return 0
    title = meta["title"].lower()
    rid = meta["id"].lower()
    if q == title or q == rid:
        return 1000
    if q in title or q in rid:
        return 500 + len(q)
    tokens = [t for t in re.split(r"\s+", q) if t]
    score = sum(100 for t in tokens if t in title or t in rid)
    return score


def search_recipes(query: str, *, section: str | None = None, snapshot: Path | None = None) -> list[dict]:
    rows = manifest_index(snapshot)
    if section:
        if section == "web":
            rows = [r for r in rows if r.get("manifest_section") == WEB_ADAPTATIONS_SECTION]
        else:
            rows = [r for r in rows if r.get("manifest_section") == section]
    if not (query or "").strip():
        return sorted(rows, key=lambda r: r["title"].lower())
    scored = [( _score_match(query, r), r) for r in rows]
    scored = [(s, r) for s, r in scored if s > 0]
    scored.sort(key=lambda x: (-x[0], x[1]["title"].lower()))
    return [r for _, r in scored]


def crust_duration_minutes(crust_times: dict[str, str], crust: str) -> int | None:
    key = (crust or "medium").lower()
    val = crust_times.get(key) or crust_times.get("medium") or next(iter(crust_times.values()), None)
    if not val:
        return None
    parts = val.split(":")
    if len(parts) != 2:
        return None
    try:
        return int(parts[0]) * 60 + int(parts[1])
    except ValueError:
        return None


def format_recipe_brief(meta: dict, *, crust: str = "medium") -> str:
    lines = [f"**{meta['title']}**"]
    prep = meta.get("prep_type") or "bread-machine"
    if prep == "hand-oven":
        lines.append("Manual oven — no bread machine course")
        block = meta.get("machine_block") or ""
        if block:
            lines.append(block)
    else:
        cname = meta.get("machine_course_name") or "?"
        cnum = meta.get("machine_course")
        lines.append(f"Course: {cnum} — {cname}" if cnum else f"Course: {cname}")
        ct = meta.get("crust_times") or {}
        if ct:
            order = ["light", "medium", "dark"]
            parts = [f"{k.title()} {ct[k]}" for k in order if k in ct]
            lines.append("Crust: " + " | ".join(parts))
            mins = crust_duration_minutes(ct, crust)
            if mins:
                lines.append(f"Selected crust ({crust}): ~{mins // 60}:{mins % 60:02d}")
        block = meta.get("machine_block") or ""
        if "add-beep" in block.lower() or "Add beep" in block:
            lines.append("Add beep: ~45 min (mix-ins or scrape)")
    steps = meta.get("instructions") or []
    if steps:
        lines.append("")
        lines.append("Steps:")
        for i, step in enumerate(steps[:6], 1):
            lines.append(f"{i}. {step}")
        if len(steps) > 6:
            lines.append(f"…{len(steps) - 6} more in Sidekick")
    return "\n".join(lines)


def bread_courses_help(snapshot: Path | None = None) -> str:
    ref = (snapshot or BB_SNAPSHOT) / "MACHINE-REFERENCE.md"
    if ref.is_file():
        text = ref.read_text(encoding="utf-8")
        m = re.search(r"## Course map\s*\n(.*?)(?:\n## |\Z)", text, re.S)
        if m:
            body = m.group(1).strip()
            keep = []
            for ln in body.splitlines():
                if ln.strip().startswith("|") and "Course" not in ln and "---" not in ln:
                    keep.append(ln.strip())
            if keep:
                return "BB-PDC20 courses (common):\n" + "\n".join(keep[:8])
    return (
        "BB-PDC20 courses (common):\n"
        "| 1 | WHITE | Crust 3:15 / 3:25 / 3:35 |\n"
        "| 13 | CAKE | Crust 1:40 / 1:50 / 2:00 |\n"
        "| 11 | DOUGH | Knead only — finish in oven |"
    )


def parse_ingredient_lines(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"## Ingredients\s*\n(.*?)(?:\n## |\Z)", text, re.S)
    if not m:
        return []
    items = []
    for ln in m.group(1).splitlines():
        s = ln.strip()
        if s.startswith("|") and not s.startswith("| Order") and "---" not in s:
            cols = [c.strip() for c in s.strip("|").split("|")]
            if len(cols) >= 3:
                items.append(f"{cols[1]} {cols[2]}".strip())
            elif len(cols) >= 2:
                items.append(cols[-1])
        elif s.startswith("|") is False and s.startswith("- "):
            items.append(s[2:].strip())
    extra = re.search(r"## Extra ingredients\s*\n(.*?)(?:\n## |\Z)", text, re.S)
    if extra:
        for ln in extra.group(1).splitlines():
            s = ln.strip()
            if s.startswith("|") and "---" not in s and "Amount" not in s:
                cols = [c.strip() for c in s.strip("|").split("|")]
                if len(cols) >= 2:
                    items.append(f"{cols[0]} {cols[1]}".strip())
    return items
