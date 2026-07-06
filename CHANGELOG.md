# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Forge Alfred follow-up:** docker webhook relay on CPM network (`setup-forge-webhook-relay-docker.sh`); CPM upstream auto-detect; `disable-root-nc-backup-cron.sh`; NC DB backup systemd templates
- `docs/FORGE-INTEGRATION.md` — operator guide (docker relay, backup timer, E2E sign-off)

### Changed

- `nc-db-backup-run.sh` — MYSQL_PASSWORD from `~/.openclaw/.env` or `cloud_db` env (no hardcoded default)
- `forge-gates.sh` — docker relay I1; I6 POST probe; W2 delivery check
- `.env.example` — `FORGE_CPM_UPSTREAM_HOST`, backup env vars
- `validate-mail-secrets.sh` / `scrub-for-publish.sh` — SEC-2 operator scope
- `test-week-cron-profile.yaml` — stuck agentTurn jobs removed

### Added

- **SKY-30..33 recipe Talk + meal tools:** recipe/bread fast-path in Talk shim; lookup CLI; bread bake timer; meal-plan propose/apply; recipe dedupe; full BB snapshot sync
- `scripts/skylight-recipe-talk-fast-path.sh`, `scripts/lib/recipe_talk_match.py` — `@alfred recipe` / `@alfred bread` (no LLM)
- `scripts/skylight-recipe-lookup.sh` — CLI lookup shared with Talk fast-path
- `scripts/skylight-bread-timer.sh` — start + scheduled completion Talk post
- `scripts/skylight-meal-plan-propose.sh` — weekly dinner plan with YES/NO via `createSitting`
- `scripts/skylight-recipe-dedupe.sh` + `skylight-curate-recipes.py --dedupe-only`
- `scripts/skylight-sync-all-bb-recipes.sh` — batch import all manifest sections
- `scripts/talk-webhook-shim.py` — recipe fast-path routing (installed to `~/.openclaw/talk-webhook-shim.py`)
- **Web recipe adaptations (BB-PDC20 section 16):** six recipes in snapshot library (`16-web-adaptations/`) — machine WHITE/CAKE courses plus manual Copeland biscuits; Southern Living raisin enrichment in factory `raisin-bread.md`
- `scripts/skylight-sync-web-recipes.sh` — import web section + curate BB manifest on Skylight
- `scripts/skylight-recipe-gates.sh` — P12 parse/import gates for web adaptations
- `docs/SKYLIGHT-RECIPES.md` — operator guide for recipe library and Alfred commands
- Makefile targets: `recipes-gates`, `recipes-web-sync`, `recipes-full-sync`
- `skylight_recipe_lib.py`: `BB_SNAPSHOT`, `WEB_ADAPTATIONS_SECTION`, `prep_type_from_markdown`, `machine_line_ok`, manifest helpers; section `16-web-adaptations` → Snack

### Changed

- `skylight-import-recipes-batch.sh` — default meal category auto from section folder (was hardcoded Snack)
- `skylight-import-recipes-verify.sh` — P12 accepts manual oven recipes (`Oven:` / not used) in addition to `Course:`

- **MySubaru / vehicle integration** moved to sibling repo **openclaw-subaru** (private). Install both into `~/.openclaw` if you use Skylight + Subaru.

## [0.2.2] - 2026-05-31

### Added

- **Week-2 capacity bundle:** shell-direct cron, test-week profile, G-DAY gates — [docs/WEEK2-CAPACITY.md](docs/WEEK2-CAPACITY.md)
- `scripts/openclaw-day-review.sh` — PERF/CAP/SESS/NC/E2E-AUTO daily review + JSON log
- `scripts/flight-event-monitor.sh` — NC-GCS fleet monitor without LLM
- `scripts/email-to-event-shell.sh`, `backup-verify-shell.sh`, `household-proposal-nudge.sh`
- `scripts/cron-audit.sh` — CR-AUDIT gate (backup-verification deferred as CAP-F3)
- `scripts/apply-test-week-cron-profile.sh`, `restore-cron-profile.sh`
- `scripts/install-openclaw-shell-cron.sh` — systemd timers from `config/references/cron-shell-direct.yaml`
- `config/references/cron-shell-direct.yaml`, `test-week-cron-profile.yaml`
- `docs/OPERATOR-MANUAL-GATES.md`, `docs/plans/openclaw_week2_capacity.md`
- Makefile targets: `day-review`, `shell-cron`
- `.env.example`: `EMAIL_TO_EVENT_AUTO`, gateway health URLs, backup dir, cron unit prefix

### Fixed

- `run-openclaw-cron-shell.sh` — summary grep no longer fails under `pipefail` (blocked run log append)
- `talk-post.sh` — `--dry-run`, `--test-retry`; requires `SKYLIGHT_OPS_TALK_ROOM` (no hardcoded room token)
- `flight-event-monitor.sh` — accepts OpenClaw `"status":"live"`; mavlink alerts only with fleet activity
- `openclaw-day-review.sh` — empty WORST_MS journal pipeline under `pipefail`

### Changed

- `openclaw-ai-gates.sh` — G-DAY integrates `openclaw-day-review.sh`; CR-AUDIT via `cron-audit.sh`
- `install-to-openclaw.sh` — syncs `workspace/references/*.yaml` from repo

## [0.2.1] - 2026-05-30

### Fixed

- **Skills install:** `install-to-openclaw.sh` copies skills into workspace (`sync_skill`) — OpenClaw 2026.4.24 rejects symlink-escape outside workspace root
- **`load-agent-env.sh`:** no longer clobbers caller `MODEL` variable (`AGENT_HOUSEHOLD_MODEL`)
- **`talk-response-audit.sh`:** exports `HOUSEHOLD_MODEL_JSON` before agent env load; G2 synthetics use `OPENCLAW_AGENT_MENTION`

### Added

- Gate **I3:** post-install check that workspace skills are real directories under `~/.openclaw/workspace/skills/`
- `scripts/validate-model-routing.sh` — MDL gates for main/family agents and shell-direct cron
- `openclaw-ai-gates.sh`: CR-1 digest direct check; MDL block; mention-aware DIS-1/DIS-3
- `docs/plans/openclaw_home_ai_fixes.md` — home AI hardening plan
- `docs/templates/nc-webhook-relay-mention-snippet.md` — operator relay `@alfred` pattern

### Changed

- **`skylight-household-gates.sh`:** C1b dry-run uses `OPENCLAW_AGENT_MENTION` (homelab `@alfred`)
- **`validate-model-routing.sh`:** MDL-2 checks relay hooks routing (room `agentId` invalid in OpenClaw 2026.4.24)


### Changed (public release prep)

- Rebrand Alfred → OpenClaw: `@openclaw` mention alias, renamed `openclaw-*` gate/catchup scripts
- Remove operator-specific IDs, emails, and family names from scripts/skills/docs
- Chore dedupe: `skylight-chores-dedupe-parent` reads `parent_chore_dedupe` from household-model
- Expanded `scrub-for-publish.sh` blocklist + legacy `alfred` branding check
- Mail API retry (`nc-http-retry.sh`) from v0.1.6 included in this release line

### Removed

- `skylight-chores-dedupe-mom` (operator-hardcoded group IDs)

## [0.1.6] - 2026-05-30

### Fixed

- Mail gates no longer false-fail on transient HTTP 503 when Nextcloud Mail taskworker is warming up
- New `nc-http-retry.sh`: `nc_wait_mail_api` + `nc_curl_retry` (503/502/409 backoff)
- Retry added to `nc-mail-sync-accounts`, `email-urgent-scan`, `skylight-email-enrich-scan`
- MAIL-CSRF gate reports explicit status codes instead of generic "unreachable"

## [0.1.5] - 2026-05-30

### Added

- Talk relay synthetic gates G2-7 (T5 YES/NO fast-path), G2-8/G2-8b (T9 spacing + rate limit)

### Changed

- `make gates` passes `--skip-mail` to household gates so mail runs once (~2 min faster)
- `skylight-household-gates.sh` accepts `--skip-mail`

## [0.1.4] - 2026-05-30

### Fixed

- `talk-response-audit.sh` G4-1 auto-resolves `NC_DB_PASS` from `cloud_db` container (no manual env required)

### Changed

- Talk fix plan sign-off: automated gates marked PASS; relay partial coverage noted for T1/T2/T8

## [0.1.3] - 2026-05-30

### Added

- Talk response gates: `talk-response-audit.sh`, TR-ALL in `alfred-ai-gates.sh`
- Chore organization: `skylight_chore_lib.py`, fill-blanks, dedupe-mom scripts
- Recipe curation: `skylight_recipe_lib.py`, `skylight-curate-recipes.sh`
- Alfred ops: `alfred-ai-gates.sh`, `alfred-catchup.sh`, `run-alfred-cron-shell.sh`
- Flight triage bundle + skill + gates
- Docs: `ALFRED-STACK.md`, `docs/plans/`, expanded `NEXTCLOUD-TALK.md`, `GATES.md`
- `Makefile` targets: install, gates, smoke, talk-gates, chore dry-runs
- Household model schema: `chore_reward_defaults`, `parent_categories`, canonical chore IDs

### Changed

- `install-to-openclaw.sh` symlinks `.py` scripts and `flight-triage` skill
- `skylight-household-deep-audit.sh` chore enrichment from model defaults + RRULE
- Recipe import batch: skip existing titles, Sidekick boilerplate strip
- `household-model.example.json` expanded chore defaults

## [0.1.2] - 2026-05-29

### Added

- Three-account Nextcloud Mail: family (read-only enrich), ops/work (digest + urgent)
- `mail-gates.sh` aggregator, `nc-mail-sync-accounts.sh`, mail account validators
- `email-daily-digest-post.sh` and `email-urgent-scan.sh` multi-account routing
- Mail gate matrix in `docs/GATES.md`; role routing in email-intelligence skill

### Fixed

- Household gates invoke `mail-gates.sh --check` (no apply during full run)
- Docker `mail:account:sync` timeout handling (180s) and digest `from` field parsing
- HTTP 409 retry in urgent scan API client

## [0.1.0] - 2026-05-29

### Added

- Skylight + household audit/propose/apply pipeline
- Family Hub dispatch for `@openclaw YES|NO|EDIT` proposal replies
- Fast email enrich scan (subject-first, E2-S <60s gate)
- email-intelligence skill + NC Mail helpers
- Morning digest and weekly audit scripts
- `install-to-openclaw.sh`, `publish-gates.sh`, `scrub-for-publish.sh`
- Community docs, examples, cron templates
