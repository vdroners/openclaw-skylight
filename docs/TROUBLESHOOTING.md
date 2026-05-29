# Troubleshooting

| Symptom | Fix |
|---------|-----|
| `SKYLIGHT_FRAME_ID not set` | Add to `.env` or run `skylight-login.sh` |
| E2 timeout | Run `occ mail:account:sync <id>` once; E2-S requires cached inbox |
| Calendar apply 404 | Use list API body, not GET by id — see API-QUIRKS |
| Chore apply 422 | Routine: BYHOUR in RRULE, omit start_time on PUT |
| talk-post fails | Check room token and NC credentials |
| scrub fails | Remove PII; run `scripts/scrub-for-publish.sh` for pattern |

Re-auth: `bash scripts/skylight-auth-refresh.sh`
