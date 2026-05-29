# Setup

## 1. Clone and configure

```bash
git clone git@github.com:vdroners/openclaw-skylight.git
cd openclaw-skylight
cp .env.example .env
cp config/household-model.example.json config/household-model.json
```

Edit `.env` with Skylight credentials and Nextcloud URL. Edit `household-model.json` with your frame ID, calendar emails, and kid category IDs.

## 2. Skylight login

```bash
bash scripts/skylight-login.sh
bash scripts/skylight-smoke.sh
```

Token caches in `~/.config/skylight/config.yaml`.

## 3. Install into OpenClaw

```bash
bash scripts/install-to-openclaw.sh
```

Symlinks scripts into `~/.openclaw/scripts/` and skills into `~/.openclaw/workspace/skills/`.

## 4. Nextcloud Mail (optional)

```bash
# Store Gmail app password in ~/.openclaw/.env.d/family-gmail-mail.secret (chmod 600)
bash scripts/nc-mail-add-gmail.sh
```

## 5. Run gates

```bash
bash scripts/skylight-household-baseline.sh
bash scripts/skylight-household-deep-audit.sh
bash scripts/skylight-household-gates.sh
```

## OpenClaw skills

Enable in OpenClaw config:

- `skylight` — family frame API
- `email-intelligence` — NC Mail discovery

Wire Family Hub Talk messages to `skylight-family-hub-dispatch.sh` before LLM tools when message matches `@alfred YES|NO|EDIT`.
