# OpenClaw flight triage

## Scripts

| Script | Role |
|--------|------|
| `flight-triage-scan.sh` | Detect `.bin` under Flight Recordings (DAV PROPFIND) |
| `flight-triage-shell.sh` | Scan → propose newest unseen BIN (shell-direct cron) |
| `flight-triage-propose.sh` | Post Talk card with `@alfred YES triage-<id>` |
| `flight-triage-dispatch.sh` | Parse YES/NO → intake or reject |
| `flight-triage-intake.sh` | Collect intake fields, POST `/api/jobs` |
| `openclaw-flight-triage-gates.sh` | Dry-run gates |

## Env

- `NC_URL` / Nextcloud credentials via `load-nextcloud-env.sh`
- `FLIGHT_TRIAGE_TALK_ROOM` — optional; defaults to `SKYLIGHT_OPS_TALK_ROOM`
- `OPENCLAW_AGENT_MENTION` — `@alfred`

## Cron (shell-direct)

Sunday-independent daytime scan:

```bash
# Installed from config/references/cron-shell-direct.yaml
# alfred-cron-flight-triage-scan.timer — */30 8-18 America/Los_Angeles
OPENCLAW_SKYLIGHT_ROOT=/media/4TB/openclaw-skylight \
  python3 scripts/install-openclaw-shell-cron.sh
```

## Ops Talk

Relay `:8789` fast-path:

```text
@alfred YES triage-123456
@alfred NO triage-123456
```
