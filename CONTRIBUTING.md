# Contributing

Thanks for helping improve OpenClaw + Skylight integrations.

## Before you push

```bash
bash scripts/publish-gates.sh      # structure, syntax, schema, scrub
bash scripts/scrub-for-publish.sh  # PII / secret grep
```

On homelab, also verify:

```bash
bash ~/.openclaw/scripts/mail-gates.sh --check
bash ~/.openclaw/scripts/skylight-household-gates.sh
```

Both must report **`hard_fail=0`** before a release tag.

## Scope

**In scope:** Skylight frame automation, household audit/propose/apply, Nextcloud Talk + Mail helpers, OpenClaw skills.

**Out of scope:** NC-GCS fleet ops, HPB patches, fleet QA skills, MySubaru vehicle automation (openclaw-subaru), operator-private runbooks.

## Pull requests

1. One logical change per PR
2. Update `CHANGELOG.md` under `[Unreleased]`
3. No real emails, Talk room tokens, frame IDs, or home paths in committed files
4. Document new gates in `docs/GATES.md`
5. Extend `README.md` if you add a new script bundle or config file

## OpenClaw project conventions

When adding scripts or skills:

| Rule | Why |
|------|-----|
| `set -euo pipefail` on bash scripts | Fail fast; safe for cron and gates |
| Load env via `load-skylight-env.sh` / `load-nextcloud-env.sh` | Single source for credentials |
| `--dry-run` for gate-safe paths | C1b, propose, defer-stale, digest must not clobber state in CI |
| No secrets in stdout on success | Gate logs may be pasted; use `Gate X: PASS` lines only |
| Skills use **exec** for HTTP | Mail API needs `OCS-APIREQUEST: true`; document in SKILL.md |
| Parameterize IDs via env + `household-model.json` | Keeps repo scrubbable for public publish |
| Idempotent install | `install-to-openclaw.sh` must be safe to re-run |

## Adding a mail or household gate

1. Implement check in the appropriate script (`mail-gates.sh` or `skylight-household-gates.sh`)
2. Add row to `docs/GATES.md`
3. Ensure `--check` mode avoids destructive side effects where possible

## Release tags

Tags (`v0.1.x`) only on commits that pass `publish-gates.sh` with no blocklist hits. Never tag with unscrubbed operator data.
