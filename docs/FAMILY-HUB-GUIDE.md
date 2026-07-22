# Family Hub — how to use Alfred

Room token: `SKYLIGHT_FAMILY_TALK_ROOM` (typically `9x4f25n3`).

## Ask questions (no @ needed)

Post calendar, chore, meal, or grocery questions directly. Alfred uses the **family** model (`qwen3:14b`) via the Talk shim on port **8788**.

You should see **Got it — checking…** within a few seconds, then a full reply within ~2 minutes.

## Household proposals

Morning digest lists pending cards with copy-paste lines:

```
@alfred YES enrich-chore-023
@alfred NO enrich-chore-023
@alfred EDIT enrich-chore-023 your note here
```

Unknown IDs get a friendly error in Talk — check the latest digest for current IDs.

## Subaru (fast, no LLM)

```
@alfred subaru status
```

## Help cheat sheet (no LLM)

```
@alfred help
```

## What Alfred does not do here

- Fleet / mavlink / NC-GCS ops → use the **Ops** Talk room with `@alfred`.
- Silent writes to Skylight — proposals only; YES applies after you confirm.

## If Alfred feels dead

1. Confirm you posted in Family Hub (not Ops).
2. Look for the ack line; if none, gateway or shim may be down.
3. Operator: `bash ~/.openclaw/scripts/talk-response-audit.sh --check --phase all`

See also [NEXTCLOUD-TALK.md](NEXTCLOUD-TALK.md).
