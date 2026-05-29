# Nextcloud Talk

Post Family Hub cards:

```bash
bash scripts/talk-post.sh "message body" "$SKYLIGHT_FAMILY_TALK_ROOM"
```

Requires `NEXTCLOUD_URL`, `NEXTCLOUD_USER`, `NEXTCLOUD_PASS` in `.env`.

Route proposal replies through `skylight-family-hub-dispatch.sh` before LLM handling.
