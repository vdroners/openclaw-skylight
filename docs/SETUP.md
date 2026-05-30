# Setup

Complete walkthrough for homelab install. See [README.md](../README.md) for architecture and design principles.

## 1. Clone and configure

```bash
git clone git@github.com:vdroners/openclaw-skylight.git
cd openclaw-skylight
cp .env.example ~/.openclaw/.env
cp config/household-model.example.json ~/.openclaw/config/household-model.json
```

Edit `~/.openclaw/.env`:

- Skylight login, frame ID, calendar IDs, Family Hub Talk room token
- Nextcloud URL and credentials

Edit `~/.openclaw/config/household-model.json`:

- `writable_calendar_emails`, `calendar_source_ids`, kid `category` IDs, chore defaults

Validate:

```bash
bash scripts/validate-household-model.sh ~/.openclaw/config/household-model.json
```

## 2. Skylight login

```bash
bash scripts/skylight-login.sh
bash scripts/skylight-smoke.sh
```

Token caches in `~/.config/skylight/config.yaml`. Re-auth: `bash scripts/skylight-auth-refresh.sh`.

## 3. Install into OpenClaw

```bash
export OPENCLAW_SKYLIGHT_ROOT="$(pwd)"
bash scripts/install-to-openclaw.sh
```

Symlinks `scripts/` → `~/.openclaw/scripts/` and skills → `~/.openclaw/workspace/skills/`.

Use `--force` to replace local script copies with symlinks. Keep operator wrappers (e.g. a custom `nc-mail-add-daniel-gmail.sh`) outside the symlink path or restore after install.

## 4. Nextcloud Mail (three accounts)

See [NEXTCLOUD-MAIL.md](NEXTCLOUD-MAIL.md). Summary:

```bash
mkdir -p ~/.openclaw/.env.d
# chmod 600: family-gmail-mail.secret, ops-gmail-mail.secret, work-gmail-mail.secret

cp config/mail-accounts.example.json ~/.openclaw/config/mail-accounts.json
bash scripts/validate-mail-secrets.sh
bash scripts/nc-mail-sync-accounts.sh --check
bash scripts/nc-mail-sync-accounts.sh --apply
bash scripts/mail-gates.sh --check
```

Merge printed `*_MAIL_ACCOUNT_ID` values into `~/.openclaw/.env`.

## 5. Run gates

```bash
bash scripts/skylight-household-baseline.sh
bash scripts/skylight-household-deep-audit.sh
bash scripts/skylight-household-gates.sh --skip-live   # first pass
bash scripts/skylight-household-gates.sh               # full live
```

Target: **`hard_fail=0`** on both `mail-gates.sh --check` and `skylight-household-gates.sh`.

## 6. OpenClaw skills

Enable in `openclaw.json`:

- `skylight` — family frame API
- `email-intelligence` — NC Mail (multi-account)

Wire Family Hub Talk so proposal replies exec dispatch first:

```bash
bash ~/.openclaw/scripts/skylight-family-hub-dispatch.sh "<message>"
```

When the message matches `@alfred YES|NO|EDIT (enrich-*|ask-*)`, dispatch runs the reply handler and posts confirmation to `SKYLIGHT_FAMILY_TALK_ROOM`.
