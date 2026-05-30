# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.2.1] - 2026-05-30

### Fixed

- **Skills install:** `install-to-openclaw.sh` copies skills into workspace (`sync_skill`) — OpenClaw 2026.4.24 rejects symlink-escape outside workspace root
- **`load-agent-env.sh`:** no longer clobbers caller `MODEL` variable (`AGENT_HOUSEHOLD_MODEL`)
- **`talk-response-audit.sh`:** exports `HOUSEHOLD_MODEL_JSON` before agent env load; G2 synthetics use `OPENCLAW_AGENT_MENTION`

### Added

- Gate **I3:** post-install check that workspace skills are real directories under `~/.openclaw/workspace/skills/`
- `scripts/validate-model-routing.sh` — MDL gates for main/family agents and shell-direct cron
- `openclaw-ai-gates.sh`: CR-1 digest direct check; MDL block; mention-aware DIS-1/DIS-3
- `docs/plans/alfred_home_ai_fixes.md` — home AI hardening plan
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
