# Troubleshooting

| Symptom | Fix |
|---------|-----|
| `SKYLIGHT_FRAME_ID not set` | Add to `.env` or run `skylight-login.sh` |
| E2 timeout | Run `occ mail:account:sync <id>` once; E2-S requires cached inbox |
| Calendar apply 404 | Use list API body, not GET by id — see API-QUIRKS |
| Chore apply 422 | Routine: BYHOUR in RRULE, omit start_time on PUT |
| talk-post fails | Check room token and NC credentials; try `talk-post.sh --dry-run` |
| Two Talk senders (Bot vs user) | Run `enable-talk-user-outbound.sh` + restart gateway — [NEXTCLOUD-TALK.md](NEXTCLOUD-TALK.md) |
| Ops lane wait / Talk timeout | Apply test-week profile + shell-direct crons — [WEEK2-CAPACITY.md](WEEK2-CAPACITY.md) |
| False FLIGHT EVENT every 10m | Set `OPENCLAW_GATEWAY_HEALTH_URL`; omit `MAVLINK_GATEWAY_HEALTH_URL` if unreachable from host |
| CR-AUDIT last_status=error | Run job via `run-openclaw-cron-shell.sh` or wait for systemd timer |
| BACKUP_FAIL stale (CAP-F3) | Infra: refresh Nextcloud DB backup; not a G-DAY hard fail |
| scrub fails | Remove PII; run `scripts/scrub-for-publish.sh` for pattern |

Re-auth: `bash scripts/skylight-auth-refresh.sh`
