# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
- Family Hub dispatch for `@alfred YES|NO|EDIT` proposal replies
- Fast email enrich scan (subject-first, E2-S <60s gate)
- email-intelligence skill + NC Mail helpers
- Morning digest and weekly audit scripts
- `install-to-openclaw.sh`, `publish-gates.sh`, `scrub-for-publish.sh`
- Community docs, examples, cron templates
