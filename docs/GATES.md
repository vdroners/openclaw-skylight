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
| C1 | `@openclaw add milk to grocery` → proposal only |
| C2 | `@openclaw what's on the calendar Saturday?` → read-only |
| S0 | `SIGN-OFF household audit` in Family Hub |

## Flight triage gates (OpenClaw + NC Ardupilot Triage)

| Gate | Command |
|------|---------|
| G-ALF-01..04 | `bash scripts/openclaw-flight-triage-gates.sh` |
| G-AT-* | `docker exec -u www-data cloud_app php .../nc_ardupilot_triage/tools/triage-api-gates.php` |
| G-WKR-* | `bash path/to/triage-worker/scripts/worker-gates.sh` (operator-local NC-GCS) |

## Publish gates

| Gate | Check |
|------|-------|
| S1 | scrub-for-publish.sh |
| S2–S8 | size, .env.example, bash -n, PII, community files, cron |
| X1 | validate-household-model.sh |
| I1–I3 | install + homelab regression; **I3** = workspace skills are copied dirs (not symlink-escape) |
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
| MAIL-READY | Mail accounts API responds 2xx (retries 503 during taskworker warm-up) |
| E2 / E2-S | Family enrich scan <60s on pinned family account |
| E2-ISOLATE | Enrich uses family ID only |
| MAIL-SMTP-OPS / MAIL-SMTP-WORK | Account detail includes `smtpHost` |
| MAIL-DIGEST | `email-daily-digest-post.sh --dry-run` exit 0 |
| MAIL-URGENT | `email-urgent-scan.sh` exit 0, JSON line |

Household aggregator calls `mail-gates.sh --check` unless `--skip-mail` is passed (`make gates` uses `--skip-mail` so mail runs once).

## Talk response gates (`talk-response-audit.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| G0 | Gateway + relay active; ports 8788/8789/18789; hooks token |
| G1 | Ops room requireMention true; Family Hub false; rich mentionPatterns |
| G2 | Relay deliver true; mention helper; Family Hub skips relay LLM; T5/T9 synthetic |
| G3 | dispatch + reply-handler executable; non-proposal exits 2 |
| G4 | Bot in Family Hub + Ops rooms; relay reachable |

Integrated in `openclaw-ai-gates.sh` as **TR-ALL**.

## Chore gates

| Script | Purpose |
|--------|---------|
| `skylight-chores-fill-blanks.sh --dry-run` | No pending blank fields |
| `skylight-chores-dedupe-mom.sh --dry-run` | Preview parent dedupe |
| W-2 | `skylight-chore-update-probe.sh` |

See [plans/skylight_chore_organization.md](plans/skylight_chore_organization.md).

## OpenClaw AI gates (`openclaw-ai-gates.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| AI-CRON-1..3 | Critical cron jobs status=ok within max age |
| AI-CRON-4 | Shell-direct jobs disabled in OpenClaw cron |
| DIS-1, DIS-3 | Family Hub dispatch dry-run + non-proposal exit 2 |
| CR-1 | email-daily-digest-post.sh DIGEST_POSTED |
| MDL-ALL | validate-model-routing.sh |
| CR-AUDIT | cron-audit.sh — critical shell-direct last_status=ok (backup deferred) |
| TR-ALL | talk-response-audit.sh --phase all |
| G-DAY | openclaw-day-review.sh — PERF/CAP/SESS/NC/E2E-AUTO (see below) |

### G-DAY gates (`openclaw-day-review.sh --check`)

Journal PERF metrics use `~/.openclaw/state/test-week-profile-applied.txt` as baseline when present.

| Gate | PASS criteria |
|------|---------------|
| PERF-1 | Ops lane waits ≤5 since baseline |
| PERF-2 | LLM timeouts ≤3 |
| PERF-3 | Incomplete turns = 0 |
| PERF-4 | Worst ops lane wait ≤120s (override: `PERF4_MAX_WAIT_S` in `.env`) |
| PERF-5 | Morning digest + family brief posted today |
| CAP-* | agentTurn disabled for shell-converted jobs |
| CAP-F1/F2 | flight + email-to-event shell timers ran in 24h |
| CAP-P1/P2 | ≤25 enabled agentTurn; no enabled */10 agentTurn |
| SESS-1/2 | flight-event-monitor sessions ≤5; prune timer active |
| NC-TALK-* | talk-post dry-run, retry, HPB, 502/503 count |
| HOME-1 / HOME-ENGAGE | Batch freshness; warn if >10 pending, 0 applied |
| E2E-AUTO | EMAIL_TO_EVENT_AUTO=0 |
| CTX-1 | AGENTS.md ≤8192 chars |
| DAY-1 | JSON summary written to logs/ |

Full operator guide: [WEEK2-CAPACITY.md](WEEK2-CAPACITY.md). Manual UI gates: [OPERATOR-MANUAL-GATES.md](OPERATOR-MANUAL-GATES.md).

## Related vehicle integration

MySubaru / Subaru Connected Services automation lives in the private **openclaw-subaru** repo (sibling to this project). See that repo's `docs/GATES.md` and `docs/SUBARU-VEHICLE.md`.

