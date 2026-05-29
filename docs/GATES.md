# Gate matrix

Run `scripts/skylight-household-gates.sh` locally and `scripts/publish-gates.sh` before push.

## Household gates (automated)

| Gate | PASS criteria |
|------|---------------|
| G-0b | skylight-smoke.sh |
| B0 | baseline JSON frozen |
| A1–A3 | deep audit proposals + metrics |
| W-1, W-2 | calendar/chore write probes |
| E1 | NC Mail account |
| E2, E2-S | email hints + scan <60s |
| P0, P0b | propose dry-run, no batch clobber |
| P1–P4, P2 | batch state |
| P-EMAIL, P-DEDUP | email-only + terminal skip |
| C1b | dispatch NO → rejected |
| P5 | defer-stale dry-run |
| P3, R1, R2 | delta + regression |

## Manual gates

| Gate | Test |
|------|------|
| C1 | `@alfred add milk to grocery` → proposal only |
| C2 | `@alfred what's on the calendar Saturday?` → read-only |
| S0 | `SIGN-OFF household audit` in Family Hub |

## Publish gates

| Gate | Check |
|------|-------|
| S1 | scrub-for-publish.sh |
| S2–S8 | size, .env.example, bash -n, PII, community files, cron |
| X1 | validate-household-model.sh |
| I1–I3 | install + homelab regression |
| F1–F4 | fresh clone smoke + tag |
| GH-1 | GitHub scrub workflow |
