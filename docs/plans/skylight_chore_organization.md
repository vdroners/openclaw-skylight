# Skylight chore organization plan

**Goal:** Fill blank chore metadata, organize frequency/time bands, dedupe parent monthly chores, codify defaults for audits.

## Time bands

| Band | Time | Use |
|------|------|-----|
| Morning | `06:00` | Pet feed |
| Mid-morning | `07:00` | Trash (every N days) |
| Deep clean | `10:00` | Weekly / interval ≥4 / monthly |
| Evening routine | `20:00` | Daily kid routines |

## Reward points

| Tier | Points | Examples |
|------|--------|----------|
| Default | 1 | dishes, trash, counters |
| Deep | 2 | vacuum, mop, shelf, organize |
| Monthly | 2 | parent monthly tasks |

## Scripts (this repo)

| Script | Purpose |
|--------|---------|
| `skylight_chore_lib.py` | Infer times/points; PUT updates |
| `skylight-chores-fill-blanks.sh` | Batch fill (`--dry-run`, `--person Name`) |
| `skylight-chores-dedupe-mom.sh` | Consolidate duplicate parent monthly chores |
| `skylight-household-deep-audit.sh` | Metrics + enrich proposals |

Configure defaults in `~/.openclaw/config/household-model.json` (`chore_time_defaults`, `chore_reward_defaults`, `parent_chore_dedupe`).

## Verification

```bash
bash scripts/skylight-chores-fill-blanks.sh --dry-run
bash scripts/skylight-chores-dedupe-mom.sh --dry-run
bash scripts/skylight-household-deep-audit.sh
```

**Pass:** `chores_missing_start_time` = 0; Mom monthly series reduced to canonical set.
