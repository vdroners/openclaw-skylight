# Household model

Copy `config/household-model.example.json` to `config/household-model.json` (or `~/.openclaw/config/household-model.json` after install).

## Fields

| Field | Purpose |
|-------|---------|
| `frame_id` | Skylight frame ID |
| `writable_calendar_emails` | Calendars Alfred may PATCH |
| `default_calendar_email` | Default for new events |
| `kid_categories` | Profile ID → name map for chore grouping |
| `chore_time_defaults` | Title → `[time, routine]` for proposals |
| `email_keywords` | Extra keywords for email enrich scan |

Validate:

```bash
bash scripts/validate-household-model.sh config/household-model.json
```
