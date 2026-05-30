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

## Flight triage gates (Alfred + NC Ardupilot Triage)

| Gate | Command |
|------|---------|
| G-ALF-01..04 | `bash scripts/alfred-flight-triage-gates.sh` |
| G-AT-* | `docker exec -u www-data cloud_app php .../nc_ardupilot_triage/tools/triage-api-gates.php` |
| G-WKR-* | `bash /media/4TB/nc-gcs/services/triage-worker/scripts/worker-gates.sh` |

## Publish gates

| Gate | Check |
|------|-------|
| S1 | scrub-for-publish.sh |
| S2–S8 | size, .env.example, bash -n, PII, community files, cron |
| X1 | validate-household-model.sh |
| I1–I3 | install + homelab regression |
| F1–F4 | fresh clone smoke + tag |
| GH-1 | GitHub scrub workflow |

## Mail gates (`mail-gates.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| SEC | `validate-mail-secrets.sh` — secret files mode 600 |
| X2 | `validate-mail-accounts.sh` — schema + files |
| E1-* | `nc-mail-sync-accounts.sh --check` — family/ops/work listed, deduped |
| E1-SYNC | `occ mail:account:sync` per account (apply mode) |
| MAIL-STATE | `state/mail-account-ids.json` has all 3 roles |
| MAIL-ROUTE | Env `*_MAIL_ACCOUNT_ID` matches state |
| MAIL-CSRF | Mail API requires `OCS-APIREQUEST: true` |
| E2 / E2-S | Family enrich scan <60s on pinned family account |
| E2-ISOLATE | Enrich uses family ID only |
| MAIL-SMTP-OPS / MAIL-SMTP-WORK | Account detail includes `smtpHost` |
| MAIL-DIGEST | `email-daily-digest-post.sh --dry-run` exit 0 |
| MAIL-URGENT | `email-urgent-scan.sh` exit 0, JSON line |

Household aggregator calls `mail-gates.sh --check` (no account apply during full household run).

## Talk response gates (`talk-response-audit.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| G0 | Gateway + relay active; ports 8788/8789/18789; hooks token |
| G1 | Ops room requireMention true; Family Hub false; rich mentionPatterns |
| G2 | Relay deliver true; mention helper; Family Hub skips relay LLM |
| G3 | dispatch + reply-handler executable; non-proposal exits 2 |
| G4 | Bot in Family Hub + Ops rooms; relay reachable |

Integrated in `alfred-ai-gates.sh` as **TR-ALL**.

## Chore gates

| Script | Purpose |
|--------|---------|
| `skylight-chores-fill-blanks.sh --dry-run` | No pending blank fields |
| `skylight-chores-dedupe-mom.sh --dry-run` | Preview parent dedupe |
| W-2 | `skylight-chore-update-probe.sh` |

See [plans/skylight_chore_organization.md](plans/skylight_chore_organization.md).

## Alfred AI gates (`alfred-ai-gates.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| AI-CRON-1..3 | Critical cron jobs status=ok within max age |
| AI-CRON-4 | Shell-direct jobs disabled in OpenClaw cron |
| DIS-1, DIS-3 | Family Hub dispatch dry-run + non-proposal exit 2 |
| TR-ALL | `talk-response-audit.sh --phase all` |


