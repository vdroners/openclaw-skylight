# Plan: OpenClaw week-2 capacity (Talk lane relief)

**Status:** Implemented in v0.2.2  
**Verify:** `openclaw-ai-gates.sh --check` + `openclaw-day-review.sh --check`

## Goal

Stop Ops/Family Talk starvation from fleet `agentTurn` cron while keeping NC-GCS flight monitoring and mail automation.

## Waves

| Wave | Deliverable | Verification |
|------|-------------|--------------|
| A | Shell-direct: flight-event-monitor, email-to-event, backup-verify | CAP-F1/F2, CR-AUDIT |
| A | Test-week cron profile (reversible) | CAP-P1/P2 |
| A | Session prune for flight-event-monitor cron sessions | SESS-1/2 |
| B | Manual gates doc | C1/C2/DIS-5/S0/T3–T7 operator |
| C | `EMAIL_TO_EVENT_AUTO=0` until S0 | E2E-AUTO |
| D | `openclaw-day-review.sh` + G-DAY in ai-gates | PERF-1..5 |
| D | `talk-post.sh` dry-run + 502/503 retry | NC-TALK-* |
| E | Sign-off matrix template | docs/WEEK2-CAPACITY.md |

## Exit criteria (test week)

- G-* + G-DAY green (`hard_fail=0`)
- PERF-1..5 since profile baseline
- Manual C1/C2/DIS-5/S0 + T3–T7 recorded
- `restore-cron-profile.sh` scheduled after sign-off

## Rollback

```bash
bash ~/.openclaw/scripts/restore-cron-profile.sh
systemctl --user disable --now 'openclaw-cron-*.timer'
# Re-enable agentTurn entries in cron/jobs.json as needed
```
