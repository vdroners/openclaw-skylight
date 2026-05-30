# Alfred Talk response fix — sign-off template

**Plan:** Talk response policy + mention detection + delivery fix

## Room policy (target)

| Room | Env / token | Human messages |
|------|-------------|----------------|
| Family Hub | `$SKYLIGHT_FAMILY_TALK_ROOM` | Any |
| Ops / OpenClaw AI | `$OPS_TALK_ROOM` | `@alfred` only |
| Alfred DM | 1:1 | Any |

Operator-local (not in this repo): `openclaw.json` room policy, `nc-webhook-relay.py`, systemd units.

## Automated gate sign-off

| Gate | Description | Status | Date |
|------|-------------|--------|------|
| G0-PASS | Baseline captured | | |
| G1-PASS | openclaw.json room policy | | |
| G2-PASS | nc-webhook-relay fixes | | |
| G3-PASS | Dispatch scripts deployed | | |
| G4-PASS | NC bot + relay wiring | | |
| G5-PASS | Docs updated | | |
| G6-PASS | Stack gates integrated | | |
| G-FINAL | All automated gates green | | |

```bash
bash ~/.openclaw/scripts/talk-response-audit.sh --check --phase all
bash ~/.openclaw/scripts/alfred-ai-gates.sh --check
```

## Live Talk matrix (operator)

| Test | Room | Expected | Status | Date |
|------|------|----------|--------|------|
| T1 | Ops | No reply without @ | | |
| T2 | Ops | Reply to `@alfred` | | |
| T3 | Ops | UI @-chip reply | | |
| T4 | Family Hub | Reply to plain question | | |
| T5 | Family Hub | YES/NO fast-path | | |
| T6 | Alfred DM | Reply to hello | | |
| T7 | Ops | Cron post, no agent follow-up | | |
| T8 | Family Hub | Single reply (no double) | | |
| T9 | Ops | Two `@alfred` msgs 5s apart | | |

## Config changes summary

- Ops room: `requireMention: true`
- Family Hub: `requireMention: false`
- `hooks.allowRequestSessionKey: true` (relay dispatch)
- Relay: rich-text mentions, Family Hub no duplicate LLM, `deliver: true`, dedupe
