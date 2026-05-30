# Household enrichment

See [SETUP.md](SETUP.md) for install. Propose-first workflow:

```bash
bash scripts/skylight-household-deep-audit.sh
bash scripts/skylight-email-enrich-scan.sh
bash scripts/skylight-household-propose.sh --limit 12
bash scripts/skylight-household-propose.sh --email-only --limit 4
```

Approve in Family Hub:

```
@openclaw YES enrich-chore-001
@openclaw NO enrich-calendar-002
```

Dispatch (mandatory first step for proposal replies):

```bash
bash scripts/skylight-family-hub-dispatch.sh "@openclaw NO enrich-chore-001"
```

Full operator guide: copy from your local `~/.openclaw/docs/SKYLIGHT-HOUSEHOLD-ENRICHMENT.md` after install.
