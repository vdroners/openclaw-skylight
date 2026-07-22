---
name: forge-print
description: 3DPrintForge + K1 Max read-only guidance for Alfred Talk
---

# Forge Print (3DPrintForge + K1 Max)

## Stack

- **Dashboard:** https://forge-vdroners.ddns.net
- **Printer:** Creality K1 Max (`k1-max`) via Moonraker
- **Slicer:** Forge Slicer on loopback :8766
- **Parts library:** `/media/4TB/3dprints`

## Talk fast-path (no LLM)

- `@alfred print status` — printer state, file, temps
- `@alfred print queue` — Moonraker queue
- `@alfred print slicer` — slicer health
- `@alfred print help`

## Policy

- **Read-only in v1:** do not start, pause, or cancel prints without explicit operator confirmation in Talk.
- For slice-and-print workflows, describe steps and link to the Forge dashboard; propose actions only.
- Print alerts arrive in the Forge Talk room via `[forge]` prefixed messages.

## Alerts

Forge webhooks + `forge-print-monitor.sh` post to `FORGE_ALERT_TALK_ROOM`. Critical failures may also use native NC notify when `FORGE_NATIVE_NOTIFY=1`.
