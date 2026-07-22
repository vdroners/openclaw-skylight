# Skylight chore organization plan

**Date:** 2026-07-20 (expanded from 2026-05-30)  
**Frame:** `5136415`  
**Goal:** Dan evening dishwasher + litter cadence + kitchen deep cleans; Phoebe morning unload / bathroom Mon; Mom three monthlies; short Done-when checklists on every series (Pill excepted).

## Design principles

### Time slots (bands)

| Band | Time | Use |
|------|------|-----|
| Morning unload / feed | `06:00` | Put away clean dishes; Feed/water cats |
| Mid-morning trash | `07:00` | Take out trash (every 3 days) |
| Deep clean | `10:00` | Weekly / interval / monthly deep work |
| Afternoon practice | `14:00` | Practice Bassoon |
| Evening routine | `20:00` | Kitchen counters, Start dishwasher, kid routines, Pill |

### Routine flag

- **`routine=true`** — daily habits with `BYHOUR` in RRULE.
- **`routine=false`** — periodic/deep chores (weekly, every-N-days, monthly).

### Reward points

| Tier | Points | Examples |
|------|--------|----------|
| Default | 1 | counters, dishwasher, trash, litter dump, sheets |
| Deep / monthly | 2 | vacuum, mop, toilet, windows, litter deep, fridge, drawers, stove/oven, Mom monthlies |
| Pill | null | Leave unset |

### Descriptions

Every series (except Pill) has a short **Done when:** checklist in `description`.

## Dan’s schedule (15 series)

| Chore | Frequency | Time | Pts | Routine |
|-------|-----------|------|----:|---------|
| Kitchen counters | Daily | 20:00 | 1 | yes |
| Start dishwasher | Daily | 20:00 | 1 | yes |
| Pill | Daily | 20:00 | — | yes |
| Take out trash | Every 3 days | 07:00 | 1 | no |
| Empty litter (dump tray) | Every 4 days | 10:00 | 1 | no |
| Deep clean litter box | Every 8 days | 10:00 | 2 | no |
| Vacuum (deep) | Tu+Sa weekly | 10:00 | 2 | no |
| Toilet | Wed weekly | 10:00 | 2 | no |
| Windows/Mirrors | Thu weekly | 10:00 | 2 | no |
| Mop | Sat weekly | 10:00 | 2 | no |
| Change sheets | Sat weekly | 10:00 | 1 | no |
| Clip murderpaws | Monthly 27th | 10:00 | 1 | no |
| Clean fridge | Monthly 1st | 10:00 | 2 | no |
| Clean kitchen drawers | Monthly 15th | 10:00 | 2 | no |
| Stove and oven deep clean | Every 2 months (1st) | 10:00 | 2 | no |

Canonical group ids live in `household-model.json` → `dan_chore_canonical`.

## Phoebe & Wesley

| Person | Morning | Day / evening | Periodic 10:00 |
|--------|---------|---------------|----------------|
| Phoebe | Put away clean dishes 06:00; Feed/water cats 06:00 | Practice Bassoon 14:00; Clean Room / Math / Read / Run 20:00 | Tub + Bathroom sink/counter **Mon**; Dust TU/SA; Laundry q5d |
| Wesley | — | Clean room, Brush teeth, Put away toys, Clean up shoes @ 20:00 | — |

## Mom (3 monthlies @ 10:00 / 2 pts)

| group_id | Title | Day |
|----------|-------|-----|
| `75543198` | Clean Shelf | 26th |
| `75673457` | Clean Shelf & Piano Top | 15th |
| `75960314` | Organize Knitting/Sewing | 18th |

## Implementation

### Config

- `~/.openclaw/config/household-model.json` — `chore_time_defaults`, `chore_reward_defaults`, `chore_schedule_notes`, `dan_chore_canonical`, `mom_chore_canonical`

### Scripts

| Script | Purpose |
|--------|---------|
| `skylight_chore_lib.py` | Infer times/points; PUT updates; create series (routine via post-create PUT) |
| `skylight-chore-expansion-apply.py` | Dry-run table + direct apply for 2026-07 expansion |
| `skylight-chores-fill-blanks.sh` | Batch fill blanks |
| `skylight-chores-dedupe-mom.sh` | Delete Mom duplicates |
| `skylight-household-deep-audit.sh` | Metrics + enrich proposals |

### Snapshots

`~/.openclaw/state/chore-expansion-snapshots/` (`pre-*.json`, `expansion-plan.json`, `post-*.json`)

## Verification

```bash
source ~/.openclaw/scripts/load-skylight-env.sh   # or openclaw-skylight equivalent
python3 scripts/skylight-chore-expansion-apply.py --dry-run
```

**Pass criteria (2026-07-20):**

- Dan has dishwasher + litter dump/deep pair + fridge/drawers/stove-oven
- Deep cleans show 2 pts; stove `INTERVAL=2`
- Phoebe: Put away clean dishes @ 06:00; Tub weekly Mon; Bassoon spelling; bathroom 10:00
- Mom: exactly 3 monthlies including piano/shelf
- Every non-Pill series has non-empty description checklist
