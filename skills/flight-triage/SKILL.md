---
name: flight-triage
description: Detect new ArduPilot BIN logs, ask the operator via Talk, collect triage intake, and submit jobs to nc_ardupilot_triage.
---

# Flight triage (Alfred)

When the operator or fleet workflow drops a new `.bin` under Nextcloud **Flight Recordings**:

1. Run `scripts/flight-triage-scan.sh` to list candidates.
2. Post a proposal card via `scripts/flight-triage-propose.sh`.
3. On `@alfred YES triage-<id>`, run `scripts/flight-triage-intake.sh` then submit to NC Ardupilot Triage.

Do not run `analyze-triage` directly unless the worker is down — prefer `POST /apps/nc_ardupilot_triage/api/jobs`.

Intake columns (Tier 1): focus_question, bin_path, run_label, aircraft_name, airframe_class, flight_intent, anything_notable, compare_to_baseline.
