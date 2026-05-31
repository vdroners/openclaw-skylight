# Operator relay mention snippet

Apply to `~/.openclaw/nc-webhook-relay.py`. Set `OPENCLAW_AGENT_MENTION` in `.env` to match your Talk bot alias (default `@openclaw`).

## Environment

| Variable | Example | Purpose |
|----------|---------|---------|
| `OPENCLAW_AGENT_MENTION` | `@openclaw` | Human-facing mention |
| `SKYLIGHT_FAMILY_TALK_ROOM` | `<family-hub-token>` | Family Hub room |
| `OPEN_ROOMS_NO_RELAY_LLM` | same as family room | Open room → plugin path (no duplicate LLM via relay) |
| `MENTION_ALIASES` | auto from mention | Rich-text alias detection |
| `BOT_ACTOR_IDS` | bot user id | Skip bot's own messages |

systemd unit should include:

```ini
EnvironmentFile=-~/.openclaw/.env
Environment=OPENCLAW_AGENT_MENTION=@openclaw
Environment=SKYLIGHT_FAMILY_TALK_ROOM=<family-hub-token>
Environment=OPEN_ROOMS_NO_RELAY_LLM=<family-hub-token>
```

## Python pattern

```python
AGENT_MENTION = (os.environ.get("OPENCLAW_AGENT_MENTION", "@openclaw").strip() or "@openclaw")
AGENT_NAME = AGENT_MENTION.lstrip("@").lower() or "openclaw"

_HOUSEHOLD_PROPOSAL_RE = re.compile(
    rf"(?i)@{re.escape(AGENT_NAME)}\s+(YES|NO|EDIT)\s+(enrich-calendar-|enrich-chore-|ask-)[0-9]+"
)
```

## Family Hub LLM routing

For hooks dispatch to gateway, use `agentId: "family"` and session key `agent:family:nextcloud-talk:group:<family-hub-token>` when `room_token == FAMILY_HUB_ROOM`.

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
