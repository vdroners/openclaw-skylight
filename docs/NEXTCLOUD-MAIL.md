# Nextcloud Mail

Read-only Gmail enrichment for calendar locations.

## Setup

1. Enable 2FA on Gmail; create an app password
2. Store in `~/.openclaw/.env.d/family-gmail-mail.secret` (chmod 600)
3. Set `FAMILY_GMAIL_ADDRESS` in `.env`
4. Run `bash scripts/nc-mail-add-gmail.sh`

## Scan

```bash
bash scripts/skylight-email-enrich-scan.sh
```

Env: `FAMILY_MAIL_ACCOUNT_ID` optional override after first add.
