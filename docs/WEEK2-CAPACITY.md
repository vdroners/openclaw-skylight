# Week-2 capacity relief (Talk lane starvation)

OpenClaw **v0.2.2** adds shell-direct cron, a reversible **test-week profile**, and daily **G-DAY** gates so Family Hub and Ops Talk stay responsive while fleet `agentTurn` jobs run in the background.

## Problem

High-frequency `agentTurn` cron jobs (especially `flight-event-monitor` every 10 minutes) consumed the gateway lane and caused:

- Ops room `lane wait exceeded` (87+ waits / 24h observed)
- LLM timeouts on Talk turns
- Starvation of human `@openclaw` messages in Family Hub and Ops

## Solution (three layers)

| Layer | Mechanism | Outcome |
|-------|-----------|---------|
| **Shell-direct** | systemd user timers + `run-openclaw-cron-shell.sh` | No LLM for digest, urgent scan, flight monitor, email-to-event scan, backup verify |
| **Test-week profile** | `apply-test-week-cron-profile.sh` | Disables ~21 heavy `agentTurn` jobs; keeps ≤25 enabled |
| **G-DAY gates** | `openclaw-day-review.sh` | PERF/CAP/SESS/NC/E2E-AUTO checks since profile baseline |

## Quick start (operator)

```bash
cd openclaw-skylight
bash scripts/install-to-openclaw.sh --force

# 1. Apply reversible disable list (backs up jobs.json)
bash ~/.openclaw/scripts/apply-test-week-cron-profile.sh

# 2. Install shell-direct systemd timers (disables duplicate OpenClaw cron entries)
OPENCLAW_SKYLIGHT_ROOT="$(pwd)" python3 scripts/install-openclaw-shell-cron.sh

# 3. Verify
bash scripts/openclaw-ai-gates.sh --check
bash ~/.openclaw/scripts/openclaw-day-review.sh --check
```

Restore after sign-off:

```bash
bash ~/.openclaw/scripts/restore-cron-profile.sh
```

## Shell-direct jobs (shipped in repo)

| Job | Script | Schedule | Success token |
|-----|--------|----------|---------------|
| email-daily-digest | `email-daily-digest-post.sh` | 07:00 | `DIGEST_POSTED` |
| skylight-family-morning | `skylight-family-morning-post.sh` | 07:30 | `SKYLIGHT_FAMILY_BRIEF_POSTED` |
| email-urgent-flag | `email-urgent-scan.sh` | */15 7–19 | `urgent-alert` |
| skylight-audit-weekly | `skylight-audit-weekly.sh` | Sun 08:00 | `SKYLIGHT_AUDIT_WEEKLY_POSTED` |
| **flight-event-monitor** | `flight-event-monitor.sh` | */10 6–20 | `FLIGHT_MONITOR` |
| **email-to-event** | `email-to-event-shell.sh` | */20 7–20 | `email-to-event:` |
| **backup-verification** | `backup-verify-shell.sh` | 04:00 | `BACKUP_OK` |

Manifest: `config/references/cron-shell-direct.yaml` (synced to `~/.openclaw/workspace/references/` on install).

### flight-event-monitor behavior

- **OpenClaw gateway** (`OPENCLAW_GATEWAY_HEALTH_URL`, default `http://127.0.0.1:18789/health`) must return 2xx with `"ok":true` or `"status":"live"`.
- **MAVLink gateway** (`MAVLINK_GATEWAY_HEALTH_URL`) is optional — alerts only when fleet activity exists and mavlink is unreachable.
- Posts to `SKYLIGHT_OPS_TALK_ROOM` only when there is something to report (active flights, online vehicles, or gateway down).

### email-to-event auto gate

Set `EMAIL_TO_EVENT_AUTO=0` in `.env` until Family Hub **S0** sign-off. Scan still classifies mail; auto-create branch is skipped.

## Test-week profile

File: `config/references/test-week-cron-profile.yaml`

- Disables noisy QA/fleet/report `agentTurn` jobs by **name**
- Writes baseline timestamp to `~/.openclaw/state/test-week-profile-applied.txt`
- PERF journal metrics in `openclaw-day-review.sh` count events **since** that timestamp

## G-DAY gate summary

Integrated in `openclaw-ai-gates.sh` via `openclaw-day-review.sh`:

| Gate | PASS criteria |
|------|---------------|
| PERF-1 | Ops lane waits ≤5 since baseline |
| PERF-2 | LLM timeouts ≤3 |
| PERF-3 | Incomplete turns = 0 |
| PERF-4 | Worst ops lane wait ≤120s |
| PERF-5 | Morning digest + family brief posted today |
| CAP-F1/F2 | Shell timers ran for flight + email-to-event |
| CAP-P1/P2 | ≤25 enabled agentTurn; no enabled */10 agentTurn |
| SESS-1/2 | flight-event-monitor sessions ≤5; prune timer active |
| NC-TALK-* | talk-post dry-run, retry helper, HPB edge, 502/503 count |
| E2E-AUTO | `EMAIL_TO_EVENT_AUTO=0` in `.env` |
| CR-AUDIT | Critical shell-direct jobs `last_status=ok` (backup deferred — CAP-F3) |

Manual gates (operator UI): **C1**, **C2**, **DIS-5**, **S0**, **T3–T7** — see [OPERATOR-MANUAL-GATES.md](OPERATOR-MANUAL-GATES.md).

## Daily operator rhythm

```bash
bash ~/.openclaw/scripts/openclaw-ai-gates.sh --check
bash ~/.openclaw/scripts/openclaw-day-review.sh --check
```

Optional engagement nudge (no LLM):

```bash
bash ~/.openclaw/scripts/household-proposal-nudge.sh --dry-run
bash ~/.openclaw/scripts/household-proposal-nudge.sh   # live post when >5 pending
```

## Legacy timer prefix

Homelab installs that already use a legacy systemd unit prefix can set in `~/.openclaw/.env`:

```bash
OPENCLAW_CRON_UNIT_PREFIX=your-legacy-prefix
```

Default is `openclaw-cron`. G-DAY checks use this env var for timer unit names.

## Related docs

- [GATES.md](GATES.md) — full matrix
- [OPENCLAW-STACK.md](OPENCLAW-STACK.md) — repo vs operator-local
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — lane wait, false flight alerts, cron runner
- [plans/openclaw_week2_capacity.md](plans/openclaw_week2_capacity.md) — implementation plan
