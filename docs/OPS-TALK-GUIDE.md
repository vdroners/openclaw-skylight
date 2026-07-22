# Ops Talk — how to use Alfred

Room token: `SKYLIGHT_OPS_TALK_ROOM` (typically `jf7zijqp`).

## Always mention @alfred

Plain ops chat is ignored. Use the NC `@alfred` chip or type `@alfred` before your question.

Routing: **nc-webhook-relay** `:8789` → gateway hooks with **main** agent (`qwen3:8b-32k`).

## Email-to-event proposals

```
@alfred YES e2e-abc123
@alfred NO e2e-abc123
```

Handled by relay fast-path (no LLM).

## Subaru

```
@alfred subaru status
```

## Forge / K1 Max

```
@alfred print status
@alfred print queue
@alfred print help
```

Print alerts (`[forge]` prefix) post to `FORGE_ALERT_TALK_ROOM` (defaults to ops room). See [FORGE-INTEGRATION.md](FORGE-INTEGRATION.md).

## Help (no LLM)

```
@alfred help
```

## Automation vs interactive chat

| Content | Room env | Prefix |
|---------|----------|--------|
| Daily health stack summary | `HEALTH_REPORT_TALK_ROOM` | `[health]` |
| Self-watchdog alerts | `WATCHDOG_TALK_ROOM` | `[watchdog]` |
| Flight / fleet / gateway alerts | `FLIGHT_ALERT_TALK_ROOM` | `[flight]` |
| Forge print alerts | `FORGE_ALERT_TALK_ROOM` | `[forge]` |
| Interactive `@alfred` ops Q&A | `SKYLIGHT_OPS_TALK_ROOM` | — |

Create a quiet **Alfred Automation** Talk room, register the bot, and point the three env vars at that room so this room stays readable.

Pin the room description: *Mention @alfred for fleet and ops help.*

## Rate limits

Double-tapping `@alfred` within a few seconds may show: *Easy — one question at a time.*

## Household vs fleet boundary

Family Hub (`9x4f25n3`) uses open-room chat and the **family** model. Do not expect Family Hub routing from Ops.

See [NEXTCLOUD-TALK.md](NEXTCLOUD-TALK.md) and [FAMILY-HUB-GUIDE.md](FAMILY-HUB-GUIDE.md).
