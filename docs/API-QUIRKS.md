# API quirks

Discovered against Skylight unofficial API (2026).

| Resource | Note |
|----------|------|
| Calendar classify | Match writable cals by **email label**, not numeric source id |
| Calendar GET by id | Often 404; load event from 60d list then PUT |
| Routine chore PUT | Omit `start_time`; set `BYHOUR=` in `recurrence_set` (allowed: 6, 14, 20) |
| Non-routine chore | Set `start_time` only |
| Calendar create | Flat JSON body; omit `calendar_id` for frame default |
| List item delete | Use bulk `deleteItems`; single delete broken |

Evening routine chores map to **BYHOUR=20** (8pm slot), not 19:00.
