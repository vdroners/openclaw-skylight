# Security Policy

## Never commit secrets

- Skylight passwords, Gmail app passwords, Nextcloud credentials
- Talk room tokens, Bearer tokens, frame IDs tied to your household
- Files under `.env`, `.env.d/*.secret`

Use `.env.example` as a template. Run `scripts/scrub-for-publish.sh` before every push.

## Reporting vulnerabilities

If you find a security issue in this integration (not the Skylight service itself), open a private GitHub security advisory or email the repository owner.

## Unofficial API

This project uses an **unofficial** Skylight API. It may change without notice. The propose-first workflow is intentional — no silent writes to family calendars from chat.
