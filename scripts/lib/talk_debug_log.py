"""Debug-mode NDJSON logger for Alfred Talk flow (session 85756f)."""

from __future__ import annotations

import json
import time

_LOG_PATH = "/media/4TB/nc-gcs/.cursor/debug-85756f.log"
_SESSION_ID = "85756f"


def talk_debug(
    hypothesis_id: str,
    location: str,
    message: str,
    data: dict | None = None,
) -> None:
    # #region agent log
    try:
        with open(_LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    {
                        "sessionId": _SESSION_ID,
                        "hypothesisId": hypothesis_id,
                        "location": location,
                        "message": message,
                        "data": data or {},
                        "timestamp": int(time.time() * 1000),
                    }
                )
                + "\n"
            )
    except OSError:
        pass
    # #endregion
