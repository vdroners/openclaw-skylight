# Alfred Home AI — implementation plan (v0.2.1+)

Checked-in summary of the homelab hardening plan. Full gate matrix lives in operator `openclaw-ai-gates.sh` + `validate-model-routing.sh`.

## Goals

- Tier 0 propose-first household AI
- Right model per workload (8b ops, 14b family, no LLM for cron/dispatch)
- Master pass/fail gates block regressions

## Waves

| Wave | Scope |
|------|--------|
| 1 | Repo v0.2.1: sync_skill, agent mention gates, I3, validate-model-routing |
| 2 | Relay template, systemd EnvironmentFile, runbook |
| 3 | Model routing YAML, family agent 14b, MDL gates |
| 4 | Skills copy refresh, bootstrap trim |
| 5 | Household catchup + manual C1/C2/C1b/DIS-5/S0 |
| 6 | Docs hygiene (AGENTS, SOUL, enrichment) |
| 7 | SEC-R secrets rotation |
| 8 | Tier 1 after S0 only |

## Model policy

| Tier | Workload | Model |
|------|----------|-------|
| 0 | YES/NO/EDIT, shell cron | None |
| 1 | Ops `@alfred` | qwen3:8b-32k (main) |
| 2 | Family Hub chat | qwen3:14b (family agent) |
| 3–7 | Cron profiles | per `cron-model-map.yaml` |

## Key gates

- **G-*** baseline: verify-alfred-stack, verify-openclaw-capabilities, mail-gates, household-gates, openclaw-ai-gates, talk-response-audit
- **I3**: skills copied under workspace (not symlink-escape)
- **MDL-1..11**: validate-model-routing.sh
- **C1, C2, C1b-LIVE, DIS-5, S0**: manual Family Hub (enrichment doc sign-off)

## Operator commands

```bash
bash /media/4TB/openclaw-skylight/scripts/install-to-openclaw.sh --force
bash ~/.openclaw/scripts/openclaw-catchup.sh --household
bash ~/.openclaw/scripts/openclaw-ai-gates.sh --check
bash ~/.openclaw/scripts/validate-model-routing.sh --check
```

See also: [OPENCLAW-STACK.md](../OPENCLAW-STACK.md), [GATES.md](../GATES.md), [templates/nc-webhook-relay-mention-snippet.md](../templates/nc-webhook-relay-mention-snippet.md).
