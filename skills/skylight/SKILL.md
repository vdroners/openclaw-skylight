---
name: skylight
description: >-
  Family Skylight Calendar frame — calendar, chores, lists, rewards, meals/recipes.
  Use for family hub requests. For fleet/ops calendars use calendar-intelligence (Nextcloud).
metadata:
  openclaw:
    requires:
      env:
        - SKYLIGHT_FRAME_ID
        - SKYLIGHT_EMAIL
---

# Skylight Calendar (family hub)

Control the household **Skylight frame** via the unofficial API at `https://app.ourskylight.com`.

## Alfred routing

| Topic | Skill |
|-------|-------|
| Family calendar, chores, grocery, rewards, recipes | **skylight** (this skill) |
| Fleet ops, NC CalDAV, flight debriefs | **calendar-intelligence** |
| Family cron digest Talk room | `` (Family Hub) |
| Ops cron / fleet brief Talk room | `` |

## Setup

Environment (from `~/.openclaw/.env` via `load-skylight-env.sh`):

- `SKYLIGHT_EMAIL` — Alfred Skylight login
- `SKYLIGHT_PASSWORD` — in `.env` only (never commit)
- `SKYLIGHT_FRAME_ID` — household ID (e.g. `1000001`)
- `SKYLIGHT_URL` — `https://app.ourskylight.com`
- `SKYLIGHT_TIMEZONE` — `America/Los_Angeles`
- `SKYLIGHT_DEFAULT_CALENDAR_ID` / `SKYLIGHT_DEFAULT_CALENDAR_ACCOUNT_ID` — parent Google (`1000101` / `ACCOUNT_ID`); frame default for new events
- `SKYLIGHT_DEFAULT_GROCERY_LIST_ID` — `GROCERY_LIST_ID`
- `SKYLIGHT_DEVICE_EMAIL` — Sidekick email import fallback (`family@example.com`)

Household reference: `~/.openclaw/docs/SKYLIGHT-HOUSEHOLD-MODEL.md`

**Auth:** Do **not** use legacy `POST /api/sessions` (returns "version no longer supported"). Prefer:

```bash
bash ~/.openclaw/scripts/skylight-login.sh
source ~/.openclaw/scripts/load-skylight-env.sh
```

Token is cached in `~/.config/skylight/config.yaml` (Bearer). CLI: `~/go/bin/skylight` ([skylight-tools](https://github.com/aarons22/skylight-tools)).

**Smoke:** `bash ~/.openclaw/scripts/skylight-smoke.sh`

## CLI quick reference

```bash
source ~/.openclaw/scripts/load-skylight-env.sh
FID="$SKYLIGHT_FRAME_ID"

skylight frames listFrames --json
skylight chores listChores --frame-id "$FID" --after 2026-05-29 --before 2026-05-30 --json
skylight chores createChore --frame-id "$FID" --summary "..." --category-id CATEGORY_ID --start 2026-05-30
skylight lists listLists --frame-id "$FID" --json
skylight lists createItem --frame-id "$FID" --list-id LIST_ID --label "milk"
skylight reward-points get --frame-id "$FID" --json
skylight meals listRecipes --frame-id "$FID" --json
skylight meals createRecipe --frame-id "$FID" --summary "Title" --description "Ingredients...\nSteps..." --category-id MEAL_CAT_ID
skylight categories listCategories --frame-id "$FID" --json
skylight task-box listItems --frame-id "$FID" --json   # legacy — prefer scheduled chores
```

## Profile / category IDs (chore chart)

| ID | Person |
|----|--------|
| `2000001` | Alex |
| `2000002` | Jordan |
| `2000003` | Parent |
| `2000004` | Mom (calendar only) |

Scheduled chores are primary; task box was cleared 2026-05-29 (do not recreate duplicate task-bank entries).

## API (curl) — when CLI is insufficient

Load auth first:

```bash
source ~/.openclaw/scripts/load-skylight-env.sh
API="$SKYLIGHT_API_URL"
FID="$SKYLIGHT_FRAME_ID"
```

### Calendar events (read)

```bash
curl -s "$API/frames/$FID/calendar_events?date_min=YYYY-MM-DD&date_max=YYYY-MM-DD&timezone=$SKYLIGHT_TIMEZONE" \
  -H "Authorization: $SKYLIGHT_AUTHORIZATION" -H "Accept: application/json"
```

### Calendar events (create → Google two-way)

Use **flat JSON body** (not JSON:API). Omit `calendar_id` to use frame default (daniel `1000101`):

```bash
curl -s -X POST "$API/frames/$FID/calendar_events" \
  -H "Authorization: $SKYLIGHT_AUTHORIZATION" -H "Content-Type: application/json" \
  -H "User-Agent: SkylightMobile (web)" \
  -d '{
    "summary": "Alfred smoke: test event",
    "starts_at": "2026-05-30T09:00:00.000-07:00",
    "ends_at": "2026-05-30T09:30:00.000-07:00",
    "timezone": "America/Los_Angeles"
  }'
```

Probe: `bash ~/.openclaw/scripts/skylight-google-write-probe.sh`

### Source calendars

```bash
curl -s "$API/frames/$FID/source_calendars" -H "Authorization: $SKYLIGHT_AUTHORIZATION"
```

### Meals / recipes (Calendar Plus)

```bash
skylight meals createRecipe --frame-id "$FID" \
  --summary "Recipe name" \
  --description "Ingredients and steps as plain text" \
  --category-id "$(skylight meals listCategories --frame-id "$FID" --json | jq -r '.data[] | select(.attributes.label=="Snack") | .id')"
```

Bulk import from markdown: `bash ~/.openclaw/scripts/skylight-import-recipes.sh <recipe.md> [--category Snack]`

**Do not** auto-add recipe ingredients to the grocery list.

### Rewards catalog

```bash
curl -s "$API/frames/$FID/rewards" -H "Authorization: $SKYLIGHT_AUTHORIZATION"
curl -s -X POST "$API/frames/$FID/rewards" \
  -H "Authorization: $SKYLIGHT_AUTHORIZATION" -H "Content-Type: application/json" \
  -H "User-Agent: SkylightMobile (web)" \
  -d '{"name":"Choose family movie","point_value":20,"category_ids":[19116283,19255362],"respawn_on_redemption":true}'
```

Flat body; one reward resource per `category_id`. Balances: `skylight reward-points get`.

### Lists

Individual item delete is broken in the API; use bulk destroy via `skylight lists deleteItems`.

### Audit / cleanup scripts

```bash
bash ~/.openclaw/scripts/skylight-audit.sh              # readonly export + gates V-1..V-12
bash ~/.openclaw/scripts/skylight-audit-weekly.sh       # Sunday cron: diff + Family Hub post
bash ~/.openclaw/scripts/skylight-cleanup-apply.sh --dry-run B2 B3 B5
bash ~/.openclaw/scripts/skylight-family-morning-post.sh  # digest v2 + Talk (Family Hub)
bash ~/.openclaw/scripts/skylight-import-recipes-verify.sh --dry-run <recipe.md>
bash ~/.openclaw/scripts/skylight-auth-refresh.sh         # re-login if smoke fails
```

**Automation matrix:** `~/.openclaw/docs/ALFRED-AUTOMATION-CAPABILITIES.md`

### Tier A cron (family)

| Cron job | Script | Room |
|----------|--------|------|
| `skylight-family-morning` | `skylight-family-morning-post.sh` | `` |
| `skylight-audit-weekly` | `skylight-audit-weekly.sh` | `` |

Family digest includes: calendar today/tomorrow, reward points (Phoebe/Wesley/Dan), chores grouped by person, meals this week (`listSittings`), grocery pending (`lists listItems`).

## Family Hub propose-first (household audit)

Room **``** only. **Never silent-write** calendar/chores/lists from chat until operator approves.

### Mandatory first step (Family Hub room)

When the incoming message matches `@alfred (YES|NO|EDIT) (enrich-calendar-*|enrich-chore-*|ask-*)`, **exec dispatch before any other tool or LLM improvisation**:

```bash
bash ~/.openclaw/scripts/skylight-family-hub-dispatch.sh "<exact user message>"
```

- Exit **0** — handled; do not re-interpret or duplicate the action.
- Exit **2** — not a proposal command; continue with normal skill routing (C1/C2 below).
- Exit **1** — error; post the stderr to the room and stop.

Wire via OpenClaw Talk webhook or agent pre-tool hook pointing at the script above.

| Intent | Action |
|--------|--------|
| `@alfred YES enrich-chore-023` | dispatch → reply-handler → apply + confirmation post |
| `@alfred NO enrich-chore-024` | dispatch → rejected + confirmation post |
| `@alfred EDIT ask-003 …` | dispatch → edit noted + confirmation post |
| "add milk to grocery" | Propose list item card (C1 — no direct write) |
| "what's on the calendar Saturday?" | Read-only digest from API (C2) |

Workflow docs: `~/.openclaw/docs/SKYLIGHT-HOUSEHOLD-ENRICHMENT.md`

```bash
bash ~/.openclaw/scripts/skylight-household-deep-audit.sh
bash ~/.openclaw/scripts/skylight-household-propose.sh --limit 12
bash ~/.openclaw/scripts/skylight-household-gates.sh
bash ~/.openclaw/scripts/skylight-household-defer-stale.sh   # 7d ask_operator
```

## Test hygiene

Prefix smoke/test data with `Alfred smoke:` and delete after verification.

## Notes

- Unofficial API — may change without notice.
- Sidekick on the frame is complementary (voice/photo/email); Alfred uses API + Talk.
- Device email for Sidekick imports: `SKYLIGHT_DEVICE_EMAIL` (one recipe per email).
