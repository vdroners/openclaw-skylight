# NC Assistant integration spike (P3)

**Status:** Talk remains the primary Alfred UX. This doc records options for a future in-app surface on `cloud_app`.

## What was inspected

Nextcloud ships an **Assistant** app (`integration_openai` / `assistant`) that can expose chat in the web UI when an STT/LLM provider is configured. NC-GCS already uses `integration_openai` for faster-whisper STT in `TalkService::transcribeAudio`.

## Options

| Option | Effort | Notes |
|--------|--------|-------|
| **A. Talk-only (current)** | Done | Family Hub + Ops rooms; shim/relay routing; lowest ops burden |
| **B. Assistant + external provider** | Medium | Point Assistant at local Ollama/OpenAI-compatible endpoint; duplicate of gateway models unless unified |
| **C. Custom nc_gcs panel** | Large | Full Vue operator UI — explicitly deferred |
| **D. Talk deep-link from nc_gcs** | Small | Link flight session UI to existing Talk room (already have session rooms + bot) |

## Recommendation

Stay on **Option A** until an operator needs Assistant-specific features (global NC search, file context). If pursuing **B**, verify:

1. Assistant app enabled on `cloud_app`
2. Provider URL matches an OpenAI-compatible endpoint (could mirror Ollama)
3. No second personality/SOUL — gateway agents remain source of truth

**No Assistant hook was implemented** in this pass — no supported low-effort external-provider bridge found that avoids duplicating OpenClaw session state.

## Flight rooms

NC-GCS `TalkService::setupBotInRoom` posts a one-line capability hint when the bot joins a flight session room.
