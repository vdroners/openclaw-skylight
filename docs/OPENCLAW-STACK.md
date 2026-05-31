# OpenClaw stack — repo vs operator-local

This repo is the **canonical source** for Skylight household scripts, mail gates, Talk post helpers, and OpenClaw skills. Some OpenClaw infrastructure stays operator-local by design.

## From this repo (`install-to-openclaw.sh`)

| Category | Examples |
|----------|----------|
| Household | audit, propose, apply, dispatch, rollback |
| Chores | fill-blanks, dedupe-mom, chore lib |
| Mail | sync, digest, urgent, mail-gates |
| Recipes | import, batch, curate |
| Talk helpers | talk-post, talk-response-audit |
| Gates | household-gates, openclaw-ai-gates, mail-gates |
| Skills | skylight, email-intelligence, flight-triage |

**Skills install:** OpenClaw 2026.4.24 rejects skill symlinks outside the workspace root. `install-to-openclaw.sh` **copies** (`rsync`) skills into `~/.openclaw/workspace/skills/`. Re-run `bash scripts/install-to-openclaw.sh --force` after every skill update. Gate **I3** verifies paths stay under workspace.

## Operator-local (`~/.openclaw` only)

| Asset | Why local |
|-------|-----------|
| `openclaw.json` | Secrets, room tokens, model routing |
| `nc-webhook-relay.py` | LAN webhook + mention fast-path |
| `.env` / `.env.d/*.secret` | Credentials |
| systemd units | `openclaw-gateway`, `nc-webhook-relay`, `${OPENCLAW_CRON_UNIT_PREFIX:-openclaw-cron}-*.timer` |
| `state/household-proposals/` | Runtime proposal batches |
| `state/test-week-profile-applied.txt` | PERF baseline for G-DAY gates |
| `workspace/references/cron-shell-direct.yaml` | Synced from repo on install (editable locally) |
| HPB / NC-GCS fleet docs | Out of community scope |

## Week-2 capacity bundle (v0.2.2+)

Shipped in this repo:

| Script | Role |
|--------|------|
| `run-openclaw-cron-shell.sh` | Execute post script + append `cron/runs/*.jsonl` |
| `install-openclaw-shell-cron.sh` | systemd timers from `cron-shell-direct.yaml` |
| `apply-test-week-cron-profile.sh` / `restore-cron-profile.sh` | Reversible agentTurn disable |
| `flight-event-monitor.sh` | NC-GCS fleet/gateway monitor (no LLM) |
| `email-to-event-shell.sh` | Wrapper around classify scan |
| `backup-verify-shell.sh` | DB backup freshness (CAP-F3 infra) |
| `openclaw-day-review.sh` | G-DAY PERF/CAP/SESS gates |
| `cron-audit.sh` | CR-AUDIT table + critical job status |
| `household-proposal-nudge.sh` | Optional Family Hub pending reminder |

See [WEEK2-CAPACITY.md](WEEK2-CAPACITY.md).

## Recommended gate order

```bash
bash scripts/talk-response-audit.sh --check --phase all   # Talk ingress
bash scripts/mail-gates.sh --check
bash scripts/skylight-household-gates.sh
bash scripts/openclaw-ai-gates.sh --check                 # Cron + TR-ALL
bash scripts/publish-gates.sh                           # Before git push
```

## Talk response policy

| Room | Human messages |
|------|----------------|
| `$SKYLIGHT_FAMILY_TALK_ROOM` | Any (plugin path) |
| `$OPS_TALK_ROOM` | `@openclaw` required |
| OpenClaw DM | Any (`dmPolicy: open`) |

See [NEXTCLOUD-TALK.md](NEXTCLOUD-TALK.md) and [plans/openclaw_talk_response_fix.md](plans/openclaw_talk_response_fix.md).
