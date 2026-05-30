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
| G0-PASS | Baseline captured | PASS | 2026-05-30 |
| G1-PASS | openclaw.json room policy | PASS | 2026-05-30 |
| G2-PASS | nc-webhook-relay fixes | PASS | 2026-05-30 |
| G3-PASS | Dispatch scripts deployed | PASS | 2026-05-30 |
| G4-PASS | NC bot + relay wiring | PASS | 2026-05-30 |
| G5-PASS | Docs updated | PASS | 2026-05-30 |
| G6-PASS | Stack gates integrated | PASS | 2026-05-30 |
| G-FINAL | All automated gates green | PASS | 2026-05-30 |

```bash
bash ~/.openclaw/scripts/talk-response-audit.sh --check --phase all
bash ~/.openclaw/scripts/alfred-ai-gates.sh --check
```

## Live Talk matrix (operator)

| Test | Room | Expected | Status | Date |
|------|------|----------|--------|------|
| T1 | Ops | No reply without @ | Partial (G2-5 relay 204) | 2026-05-30 |
| T2 | Ops | Reply to `@alfred` | Partial (G2-3 relay 200) | 2026-05-30 |
| T3 | Ops | UI @-chip reply | Pending (manual UI) | |
| T4 | Family Hub | Reply to plain question | Pending (manual UI) | |
| T5 | Family Hub | YES/NO fast-path | Pending (manual UI) | |
| T6 | Alfred DM | Reply to hello | Pending (manual UI) | |
| T7 | Ops | Cron post, no agent follow-up | Pending (manual UI) | |
| T8 | Family Hub | Single reply (no double) | Partial (G2-4 skip) | 2026-05-30 |
| T9 | Ops | Two `@alfred` msgs 5s apart | Pending (manual UI) | |

## Config changes summary

- Ops room: `requireMention: true`
- Family Hub: `requireMention: false`
- `hooks.allowRequestSessionKey: true` (relay dispatch)
- Relay: rich-text mentions, Family Hub no duplicate LLM, `deliver: true`, dedupe
