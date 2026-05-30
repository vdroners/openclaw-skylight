# Nextcloud Talk

## Post messages

```bash
bash scripts/talk-post.sh "message body" "$SKYLIGHT_FAMILY_TALK_ROOM"
bash scripts/talk-post.sh "ops brief" "$OPS_TALK_ROOM"
```

Requires `NEXTCLOUD_URL`, `NEXTCLOUD_USER`, `NEXTCLOUD_PASS` in `~/.openclaw/.env`.

## Room policy (operator `openclaw.json`)

| Room env | Typical use | Human messages |
|----------|-------------|----------------|
| `SKYLIGHT_FAMILY_TALK_ROOM` | Proposals, digest, household chat | Any |
| `OPS_TALK_ROOM` | Fleet briefs, `@alfred` ops chat | `@alfred` required |
| Alfred 1:1 DM | Direct chat | Any |

## Proposal replies (mandatory routing)

Family Hub messages matching `@alfred YES|NO|EDIT enrich-*|ask-*`:

1. **Relay fast-path** (operator `nc-webhook-relay.py` → `skylight-family-hub-dispatch.sh`) — preferred
2. **Agent exec** dispatch before any other tool if relay did not run

```bash
bash scripts/skylight-family-hub-dispatch.sh "@alfred NO enrich-chore-001"
```

Exit 0 = handled; 2 = not a proposal command; 1 = error.

## Talk response gates

```bash
bash scripts/talk-response-audit.sh --check --phase all
```

Covers gateway/relay ports, room policy in `openclaw.json`, dispatch scripts, bot coverage, synthetic mention tests.

See [ALFRED-STACK.md](ALFRED-STACK.md) and [plans/alfred_talk_response_fix.md](plans/alfred_talk_response_fix.md).
