# Nextcloud Mail

Three Gmail accounts for OpenClaw: **family** (read-only enrich), **ops** and **work** (digest + urgent + draft/send).

## Setup (3 accounts)

1. Enable 2FA on each Gmail account; create an app password per account.
2. Store secrets in `~/.openclaw/.env.d/` (mode **600**):
   - `family-gmail-mail.secret`
   - `ops-gmail-mail.secret`
   - `work-gmail-mail.secret`
3. Copy `config/mail-accounts.example.json` → `~/.openclaw/config/mail-accounts.json` and set emails + secret filenames.
4. Set addresses (and optional IDs) in `.env`:
   - `FAMILY_GMAIL_ADDRESS`, `FAMILY_MAIL_ACCOUNT_ID`
   - `OPS_GMAIL_ADDRESS`, `OPS_MAIL_ACCOUNT_ID`
   - `WORK_GMAIL_ADDRESS`, `WORK_MAIL_ACCOUNT_ID`
5. Run sync:
   ```bash
   bash scripts/validate-mail-secrets.sh
   bash scripts/nc-mail-sync-accounts.sh --check   # discover
   bash scripts/nc-mail-sync-accounts.sh --apply   # create missing + occ sync
   bash scripts/mail-gates.sh --check
   ```

Family-only calendar enrich:

```bash
bash scripts/skylight-email-enrich-scan.sh
```

Ops/work automation:

```bash
bash scripts/email-daily-digest-post.sh --dry-run
bash scripts/email-urgent-scan.sh
```

Env: `FAMILY_MAIL_ACCOUNT_ID` pins family for E2; `URGENT_SCAN_ACCOUNTS=ops,work` for urgent scan.
