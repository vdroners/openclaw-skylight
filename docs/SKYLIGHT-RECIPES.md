# Skylight recipe library (BB-PDC20 + web adaptations)

Markdown recipe library for Sidekick / Skylight API import. Lives outside this repo at:

`~/.cursor/snapshots/skylight-bb-pdc20-recipes/`

## Sections

| Folder | Count | Machine courses |
|--------|------:|-----------------|
| `01-white` … `15-homemade` | 55 | Factory Zojirushi BB-PDC20 book |
| `16-web-adaptations` | 7 | Web/household adaptations (5 machine + 2 manual oven) |

**Total:** 62 recipes in `manifest.json`.

## Web adaptations (section 16)

| Recipe | Course |
|--------|--------|
| Lavender-Thyme Bread | 1 WHITE |
| Banana Banana Bread | 13 CAKE |
| Lavender Lemon Bread | 13 CAKE |
| Japanese Milk Bread (Shokupan) | 1 WHITE (tangzhong pre-step) |
| Blueberry Lemon Lavender Bread | 13 CAKE |
| Copeland Buttermilk Biscuits (Popeyes-style) | Manual — oven 425°F |
| Blackberry Pie | Manual — oven 400°F then 350°F (Simply Recipes) |

Southern Living **Raisin Bread** changes are merged into factory `01-white/raisin-bread.md` (not a separate file).

## Alfred / OpenClaw commands

### Family Hub Talk (no LLM)

| Message | Handler |
|---------|---------|
| `@alfred recipe banana` | Course, crust times, Sidekick snippet |
| `@alfred recipe list web` | Section 16 titles |
| `@alfred bread courses` | BB-PDC20 course reference |
| `@alfred bread start lavender-thyme medium` | Timer + completion nudge |

### Shell / cron

```bash
source ~/.openclaw/scripts/load-skylight-env.sh

# Import web section + refresh all manifest recipes on Skylight
bash ~/.openclaw/scripts/skylight-sync-web-recipes.sh

# Full snapshot import (all 62 recipes) + curate
make -C ~/openclaw-skylight recipes-full-sync

# Gates: parse markdown + verify Skylight presence
bash ~/.openclaw/scripts/skylight-recipe-gates.sh --check --web-only
bash ~/.openclaw/scripts/skylight-recipe-gates.sh --check-full

# CLI lookup (shared with Talk fast-path)
bash ~/.openclaw/scripts/skylight-recipe-lookup.sh "banana"

# Weekly meal plan proposal (YES meal-plan-YYYY-wNN to apply)
bash ~/.openclaw/scripts/skylight-meal-plan-propose.sh --dry-run

# Dedupe duplicate titles on frame
bash ~/.openclaw/scripts/skylight-recipe-dedupe.sh --dry-run

# Curate: BB Sidekick from snapshot + household title/body polish
bash ~/.openclaw/scripts/skylight-curate-recipes.sh --bb-only
python3 ~/.openclaw/scripts/skylight-curate-recipes.py            # household + renames
python3 ~/.openclaw/scripts/skylight-curate-recipes.py --dry-run  # preview

# Bulk import any section (skips titles already on frame)
bash ~/.openclaw/scripts/skylight-import-recipes-batch.sh \
  ~/.cursor/snapshots/skylight-bb-pdc20-recipes/16-web-adaptations
```

Meal category defaults by section folder (`skylight_recipe_lib.py` `SECTION_CATEGORY`). Section `16-web-adaptations` → **Snack**.

## Sidekick style (frame)

Two templates live on the frame:

| Kind | Shape |
|------|--------|
| **BB / machine** | Snapshot Sidekick block: `Bread machine:` + `Course:` / `Oven:` / hand-mix note, then Ingredients / Instructions |
| **Household** | `Title` → `Ingredients:` → `Instructions:` → optional `Notes:` (Source) |

Household curation (`normalize_household_description`) Title Cases ALL-CAPS dumps, maps `Directions:` → `Instructions:`, shortens marketing titles via `RENAME` in `skylight-curate-recipes.py`, and drops blog fluff intros.

## Environment

| Variable | Default |
|----------|---------|
| `BB_SNAPSHOT` | `~/.cursor/snapshots/skylight-bb-pdc20-recipes` |
| `SKYLIGHT_FRAME_ID` | From `~/.openclaw/.env` |

## File format

Each recipe `.md` file includes YAML frontmatter, ingredient table, **Machine** block (or **Manual oven** for biscuits), **Sidekick import** block at bottom. Import cards for Photo/Talk live under `import-cards/<section>/`.
