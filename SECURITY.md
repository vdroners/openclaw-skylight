# Security Policy

## Never commit secrets

- Skylight passwords, Gmail app passwords, Nextcloud credentials
- Talk room tokens, Bearer tokens, frame IDs tied to your household
- Files under `.env`, `.env.d/*.secret`

Use `.env.example` as a template. Run `scripts/scrub-for-publish.sh` before every push.

## Reporting vulnerabilities

If you find a security issue in this integration (not the Skylight service itself), open a private GitHub security advisory or email the repository owner.

## Unofficial APIs

This project uses **unofficial** integrations that may change without notice:

- **Skylight** — propose-first workflow prevents silent calendar writes from chat.

MySubaru vehicle actuation is documented in the private **openclaw-subaru** repo.
