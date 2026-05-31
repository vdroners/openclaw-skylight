# Operator checklist — manual Family Hub gates

Run in your **Family Hub** Talk room. Record PASS dates in your local enrichment / sign-off doc.

| Gate | Command / action | Pass criteria | Status |
|------|------------------|---------------|--------|
| **C1** | `@openclaw add milk to grocery` | Proposal card only; no grocery PATCH | Pending |
| **C2** | `@openclaw what's on the calendar Saturday?` | Read-only Skylight digest | Pending |
| **C1b-LIVE** | `@openclaw NO <valid enrich-chore-id>` | Rejected + confirmation post | Pending |
| **DIS-5** | `@openclaw YES <valid-id>` then rollback script | Apply + rollback restores snapshot | Pending |
| **S0** | Post `SIGN-OFF household audit` | Recorded in enrichment doc | Pending |
| **T3–T7** | Talk matrix (ops mention, rate limit, fast-path) | Per [NEXTCLOUD-TALK.md](NEXTCLOUD-TALK.md) | Pending |
| **HOME-NUDGE** | `household-proposal-nudge.sh` (optional) | One reminder or waived | Pending |

Automated prerequisites (run before manual tests):

```bash
bash scripts/skylight-household-gates.sh
bash scripts/mail-gates.sh --check
bash scripts/openclaw-ai-gates.sh --check
bash ~/.openclaw/scripts/openclaw-day-review.sh --check
```

Family Hub YES/NO/EDIT must route through your **nc-webhook-relay** Talk mention hook so dispatch runs before the LLM.
