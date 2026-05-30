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

## Operator-local (`~/.openclaw` only)

| Asset | Why local |
|-------|-----------|
| `openclaw.json` | Secrets, room tokens, model routing |
| `nc-webhook-relay.py` | LAN webhook + mention fast-path |
| `.env` / `.env.d/*.secret` | Credentials |
| systemd units | `openclaw-gateway`, `nc-webhook-relay`, cron timers |
| `state/household-proposals/` | Runtime proposal batches |
| HPB / NC-GCS fleet docs | Out of community scope |

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
