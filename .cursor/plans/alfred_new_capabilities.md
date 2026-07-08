# Alfred New Capabilities (checked-in)

Ship Family Hub shim fast-paths (meal-plan YES, recipe, help, chores), weekly meal-plan shell cron, and flight-triage scan timer + Ops YES/NO dispatch.

## Verify

```bash
bash scripts/install-to-openclaw.sh --force
systemctl --user restart talk-webhook-shim.service nc-webhook-relay.service
RECIPE_TALK_DRY_RUN=1 bash ~/.openclaw/scripts/skylight-recipe-talk-fast-path.sh "@alfred recipe banana" 9x4f25n3
CHORE_TALK_DRY_RUN=1 bash ~/.openclaw/scripts/skylight-chore-talk-fast-path.sh "@alfred chores" 9x4f25n3
bash ~/.openclaw/scripts/skylight-meal-plan-propose.sh --dry-run
bash ~/.openclaw/scripts/openclaw-flight-triage-gates.sh
bash ~/.openclaw/scripts/talk-response-audit.sh --check --phase all
bash ~/.openclaw/scripts/openclaw-ai-gates.sh --check
```

Safety: no `EMAIL_TO_EVENT_AUTO=1`; propose-first calendar/grocery unchanged.
