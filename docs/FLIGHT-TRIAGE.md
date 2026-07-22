# OpenClaw flight triage

## Scripts

| Script | Role |
|--------|------|
| `flight-triage-scan.sh` | Detect new `.bin` under Flight Recordings (DAV PROPFIND) |
| `flight-triage-propose.sh` | Post Talk card with `@openclaw YES triage-<id>` |
| `flight-triage-dispatch.sh` | Parse YES/NO |
| `flight-triage-intake.sh` | Collect intake fields, POST `/api/jobs` |
| `openclaw-flight-triage-gates.sh` | Dry-run gates |

## Env

- `NC_URL` — Nextcloud base URL
- `NC_AT_PUBLISH_TOKEN` or operator app password
- `FLIGHT_TRIAGE_TALK_ROOM` — Talk room token (ops)

## Cron

```bash
# In openclaw-catchup.sh optional path:
bash scripts/flight-triage-scan.sh && bash scripts/flight-triage-propose.sh
```

Wire Talk webhook to `flight-triage-dispatch.sh` in `~/.openclaw/openclaw.json`.
