# Nextcloud Talk

## Post messages

```bash
bash scripts/talk-post.sh "message body" "$SKYLIGHT_FAMILY_TALK_ROOM"
bash scripts/talk-post.sh "ops brief" "$OPS_TALK_ROOM"
```

Requires `NEXTCLOUD_URL`, `NEXTCLOUD_USER`, `NEXTCLOUD_PASS` in `~/.openclaw/.env`.

## User guides

- [FAMILY-HUB-GUIDE.md](FAMILY-HUB-GUIDE.md) — open-room household chat, proposals, `@alfred help`
- [OPS-TALK-GUIDE.md](OPS-TALK-GUIDE.md) — `@alfred` required, automation room split, e2e YES/NO

## Sender identity (alfred user vs Talk Bot)

Two outbound paths exist by default:

| Path | API | Talk UI shows |
|------|-----|----------------|
| `talk-post.sh` (cron, proposals, dispatch) | `POST .../chat/{room}` as `NEXTCLOUD_USER` | Your NC user (e.g. `alfred`) |
| OpenClaw plugin LLM replies | `POST .../bot/{room}/message` with `botSecret` | **Talk Bot** badge |

To use **one identity** (recommended):

```bash
bash scripts/enable-talk-user-outbound.sh --apply
systemctl --user restart openclaw-gateway
bash scripts/enable-talk-user-outbound.sh --check   # gate G1-7
```

Sets `NEXTCLOUD_TALK_USER_OUTBOUND=1` and patches the OpenClaw Talk send path to shell out to `talk-post.sh`. **Re-run `--apply` after every `npm i -g openclaw@…` upgrade** — npm replaces the channel bundle and drops the patch.

Inbound webhooks still use the Talk bot registration; only **outbound** appearance changes.

## Room policy (operator `openclaw.json`)

| Room env | Typical use | Human messages |
|----------|-------------|----------------|
| `SKYLIGHT_FAMILY_TALK_ROOM` | Proposals, digest, household chat | Any (no `@` for questions) |
| `SKYLIGHT_OPS_TALK_ROOM` | Fleet briefs, `@alfred` ops chat | `@alfred` required |
| `HEALTH_REPORT_TALK_ROOM` / `WATCHDOG_TALK_ROOM` / `FLIGHT_ALERT_TALK_ROOM` | Automation alerts | Cron only |
| OpenClaw 1:1 DM | Direct chat | Any |

## Inbound routing matrix (Family Hub `9x4f25n3`)

NC Talk bot posts to **`:8788`** (`talk-webhook-shim.py`). Order matters:

| Message pattern | Handler | LLM? |
|-----------------|---------|------|
| `@alfred YES\|NO\|EDIT enrich-*\|ask-*\|meal-plan-*` | `skylight-family-hub-dispatch.sh` (message **only**) | No |
| `@alfred help` | Static cheat sheet via `talk-post.sh` | No |
| `@alfred recipe …` / `@alfred bread …` | `skylight-recipe-talk-fast-path.sh` (message + room) | No |
| `@alfred meal plan` | `skylight-meal-plan-talk-fast-path.sh` → propose card | No |
| `@alfred chores` / `@alfred done …` | `skylight-chore-talk-fast-path.sh` | No |
| `@alfred subaru status` (etc.) | `subaru-talk-fast-path.sh` (message + room) | No |
| `@alfred print …` | `forge-talk-fast-path.sh` (message + room) | No |
| General calendar/chore chat | **hooks dispatch** → gateway `agentId=family` | Yes (14b) |
| Hooks failure | User-visible Talk error (`TALK_SHIM_PLUGIN_FALLBACK=0` default) | No silent plugin fallback |
| `@alfred …` via relay `:8789` | **204 skip** (`OPEN_ROOMS_NO_RELAY_LLM`) for open rooms; Ops keeps relay | No / Ops yes |

Family Hub dispatch posts **Got it — checking…** immediately (`TALK_DISPATCH_ACK`, gate G-UX-1).

Ops `@alfred` uses relay `:8789` → gateway `agentId=main` (8b-32k).

### Shim contract (household dispatch)

The shim must call dispatch with **one argument** (message text). Passing the room token as a second arg overwrites `MSG` in dispatch and breaks YES/NO regex matching.

Subaru fast-path still receives `(message, room_token)`.

## Proposal replies (mandatory routing)

Family Hub messages matching `@alfred YES|NO|EDIT enrich-*|ask-*|meal-plan-*` (alias from `OPENCLAW_AGENT_MENTION` / `load-agent-env.sh`):

1. **Shim fast-path** on `:8788` → `skylight-family-hub-dispatch.sh` — primary for bot webhook
2. **Relay fast-path** (operator `nc-webhook-relay.py`) — secondary if `webhook_listeners` wired to `:8789`
3. Unknown / expired IDs → Talk error from `skylight-household-reply-handler.sh`

```bash
bash scripts/skylight-family-hub-dispatch.sh "@alfred NO enrich-chore-001"
```

Exit 0 = handled; 2 = not a proposal command; 1 = error.

## Talk response gates

```bash
bash scripts/talk-response-audit.sh --check --phase all
```

Covers gateway/relay/shim ports, room policy, dispatch scripts, bot coverage, outbound identity (G1-7), usability (G-UX-1), synthetic mention tests.

See [OPENCLAW-STACK.md](OPENCLAW-STACK.md).
