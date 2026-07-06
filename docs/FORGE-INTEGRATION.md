# Forge + Alfred + Nextcloud Talk — Operator Guide

Connect **3DPrintForge** (K1 Max) print events to Alfred via Talk notifications and `@alfred print` commands.

## URLs

| Use | URL |
|-----|-----|
| Forge dashboard | https://forge-vdroners.ddns.net |
| Webhook (public) | https://alfred-vdroners.ddns.net/forge-webhook |
| Relay health (local) | http://127.0.0.1:8790/health |

## One-time setup

```bash
cd /media/4TB/openclaw-skylight
bash scripts/install-to-openclaw.sh --force

# Secrets + Forge API key
bash scripts/forge-bootstrap-secrets.sh

# Add to ~/.openclaw/.env (see .env.example FORGE_* block)
# FORGE_ENABLED=1
# FORGE_ALERT_TALK_ROOM=<talk_room_token>   # or omit to use SKYLIGHT_OPS_TALK_ROOM

# Deploy relay (docker on CPM network — required when CPM cannot reach host :8790)
cp docs/templates/forge-webhook-relay.py ~/.openclaw/forge-webhook-relay.py
bash scripts/setup-forge-webhook-relay-docker.sh
# Optional: user systemd relay (localhost-only) — superseded by docker relay above
# cp docs/templates/forge-webhook-relay.service ~/.config/systemd/user/
# systemctl --user enable --now forge-webhook-relay

# CPM public route (requires No-IP A record alfred-vdroners)
bash scripts/setup-cpm-alfred-forge-webhook.sh   # upstream forge-webhook-relay:8790
bash scripts/setup-ddclient-alfred-forge-dns.sh   # adds hostname to ddclient (sudo)

# Configure Forge outgoing webhook
bash scripts/forge-configure-webhook.sh

# Cron monitor (every 5 min)
OPENCLAW_SKYLIGHT_ROOT="$(pwd)" python3 scripts/install-openclaw-shell-cron.sh

# Gates
bash scripts/forge-gates.sh --check --phase all
```

## Talk commands (fast-path, no LLM)

| Command | Action |
|---------|--------|
| `@alfred print status` | K1 Max state, file, temps |
| `@alfred print queue` | Moonraker queue |
| `@alfred print slicer` | Forge Slicer health |
| `@alfred print help` | Command list |

## Alert routing

- **Primary:** `[forge]` messages via `talk-post.sh` → `FORGE_ALERT_TALK_ROOM` (default: Skylight Ops `jf7zijqp`)
- **Real-time:** Forge DB webhook → CPM → `forge-webhook-relay.py`
- **Resilience:** `forge-print-monitor.sh` cron (offline, stuck print, slicer down)
- **Optional native push:** set `FORGE_NATIVE_NOTIFY=1` (uses nc_gcs `/api/notify` subject `forge_alert`)

Enable Talk push notifications for the alert room on mobile/desktop.

## Rollback

```bash
docker rm -f forge-webhook-relay
# or: systemctl --user stop forge-webhook-relay
# Disable webhook in Forge UI (Settings → Notifications → Webhooks)
# Set FORGE_ENABLED=0 in ~/.openclaw/.env
```

## Backup (Nextcloud DB)

User timer `alfred-nc-db-backup.timer` runs at **03:05** (replaces broken root 03:00 cron):

```bash
cp docs/templates/alfred-nc-db-backup.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now alfred-nc-db-backup.timer
# Retire root cron when sudo available:
sudo bash scripts/disable-root-nc-backup-cron.sh
```

Set `NEXTCLOUD_DB_BACKUP_DIR` and optional `MYSQL_PASSWORD` in `~/.openclaw/.env`.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| No webhook alerts | `bash scripts/forge-gates.sh --check --phase webhook,infra` |
| Public URL 502 | CPM cannot reach host `127.0.0.1:8790` — run `setup-forge-webhook-relay-docker.sh` and set `FORGE_CPM_UPSTREAM_HOST=forge-webhook-relay` |
| Forge webhook delivery `ENOTFOUND` | Create No-IP A record `alfred-vdroners` → public IP; run `setup-ddclient-alfred-forge-dns.sh` |
| `forge-vdroners` DNS missing | No-IP free tier has cloud/vpn/alfred only — use `alfred-vdroners` for webhooks or recreate 3rd hostname |
| Forge rejects webhook URL | Must be public HTTPS (SSRF blocks 127.0.0.1 / 10.x) |
| Relay 401 on test | HMAC secret must match Forge webhook + `forge-webhook.secret` |
| Slicer red | `systemctl --user status forge-slicer` |
| `@alfred print` slow | Should be <5s; check relay/shim fast-path wiring |

## E2E sign-off (manual — G-FORGE-E*)

1. Slice a small test part (~15 min) in Forge
2. Start print from dashboard
3. Confirm Talk receives `[forge] Print Started` and `[forge] Print Finished`
4. Post `SIGN-OFF forge integration` in Ops Talk when G-FORGE-E1..E4 pass

| Gate | Status |
|------|--------|
| G-FORGE-E1 print_started in Talk | PASS (webhook path 2026-07-06; live print optional) |
| G-FORGE-E2 print_finished in Talk | PASS (webhook path 2026-07-06; live print optional) |
| G-FORGE-E3 monitor detects Forge down | Verified via `--force-alert` dry-run |
| G-FORGE-E4 VERIFY V11–V14 | Pending supervised print |
