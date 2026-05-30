# Public release checklist

Before tagging a public release:

1. `bash scripts/scrub-for-publish.sh` — no blocklist hits, no legacy agent branding
2. `bash scripts/publish-gates.sh` — syntax, schema, `.env.example` complete
3. Confirm `.env` and `*.secret` are **not** tracked (`git ls-files '*.secret'`)
4. Clone fresh: copy `.env.example` → `.env`, fill placeholders only
5. `bash scripts/install-to-openclaw.sh` — symlinks resolve
6. On a configured homelab: `make gates` → `hard_fail=0`

## What stays operator-local

| Item | Location |
|------|----------|
| Credentials | `~/.openclaw/.env`, `~/.openclaw/.env.d/*.secret` |
| Frame / calendar IDs | `~/.openclaw/config/household-model.json` |
| Talk room tokens | `.env` + household-model |
| Gateway / relay | `~/.openclaw/openclaw.json`, `nc-webhook-relay.py` |

## Mention alias

Default Talk command prefix is `@openclaw`. Override with:

```bash
OPENCLAW_AGENT_MENTION=@your-bot-name
```

Or set `"agent_mention": "@your-bot-name"` in `household-model.json`.
