# Forge integration gates (`forge-gates.sh --check`)

| Gate | PASS criteria |
|------|---------------|
| G-FORGE-P0..P5 | Preflight: container, slicer, Moonraker, HTTPS, printer online, state API |
| G-FORGE-C1..C6 | FORGE_ENABLED, secret files mode 600, talk room, API auth |
| G-FORGE-I1..I7 | relay systemd, port 8790, health, public URL, unsigned POST → 401 |
| G-FORGE-W1 | Forge `alfred-talk` webhook active |
| G-FORGE-M1,M3,M4 | monitor dry-run, state file, force-alert |
| G-FORGE-F1..F3 | dispatch help, fast-path dry-run, matcher specificity |
| G-FORGE-T1..T2 | talk-post (via C5); room membership manual |
| G-FORGE-N1 | nc-notify dry-run (when `FORGE_NATIVE_NOTIFY=1`) |
| FORGE-ALL | Aggregated in `openclaw-ai-gates.sh` when `FORGE_ENABLED=1` |

Manual sign-off: G-FORGE-E1..E4 (supervised test print) — see [FORGE-INTEGRATION.md](FORGE-INTEGRATION.md).
