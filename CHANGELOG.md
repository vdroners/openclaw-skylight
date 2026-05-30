# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
