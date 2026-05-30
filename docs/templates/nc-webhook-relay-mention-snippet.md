# Operator relay mention snippet (homelab)

Apply to `~/.openclaw/nc-webhook-relay.py`. Public installs use `@openclaw`; homelab sets `OPENCLAW_AGENT_MENTION=@alfred`.

## Environment

| Variable | Homelab example | Purpose |
|----------|-----------------|----------|
| `OPENCLAW_AGENT_MENTION` | `@alfred` | Human-facing mention |
| `SKYLIGHT_FAMILY_TALK_ROOM` | `9x4f25n3` | Family Hub token |
| `OPEN_ROOMS_NO_RELAY_LLM` | `9x4f25n3` | Open room → plugin path (no duplicate LLM via relay) |
| `MENTION_ALIASES` | auto from mention | Rich-text alias detection |
| `ALFRED_ACTOR_IDS` | `alfred` | Skip bot's own messages |

systemd unit should include:

```ini
EnvironmentFile=-/home/vdroners/.openclaw/.env
Environment=OPENCLAW_AGENT_MENTION=@alfred
Environment=SKYLIGHT_FAMILY_TALK_ROOM=9x4f25n3
Environment=OPEN_ROOMS_NO_RELAY_LLM=9x4f25n3
```

## Python pattern

```python
AGENT_MENTION = (os.environ.get("OPENCLAW_AGENT_MENTION", "@alfred").strip() or "@alfred")
AGENT_NAME = (AGENT_MENTION.lstrip("@").lower() or "alfred")

_HOUSEHOLD_PROPOSAL_RE = re.compile(
    rf"(?i)@{re.escape(AGENT_NAME)}\s+(YES|NO|EDIT)\s+(enrich-calendar-|enrich-chore-|ask-)[0-9]+"
)
```

## Family Hub LLM routing

For hooks dispatch to gateway, use `agentId: "family"` and session key `agent:family:nextcloud-talk:group:9x4f25n3` when `room_token == FAMILY_HUB_ROOM`.

In `openclaw.json`:

- Add `agents.list[]` id `family` with `ollama/qwen3:14b`
- `hooks.allowedAgentIds`: include `"family"`

Do **not** set `channels.nextcloud-talk.rooms.*.agentId` — OpenClaw 2026.4.24 rejects it. Route Family Hub chat via relay hooks only.

## Log lines to expect

| Line | Meaning |
|------|---------|
| `household fast-path` | YES/NO/EDIT handled without LLM |
| `open-room-plugin-only` | Family Hub chat → Talk plugin (not relay LLM) |
| `dispatched room=` | Mention routed to gateway hooks |
