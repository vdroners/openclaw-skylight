"""Shared OpenClaw gateway hooks dispatch for Nextcloud Talk (relay + shim)."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

try:
    from talk_debug_log import talk_debug  # noqa: E402
except ImportError:
    def talk_debug(hypothesis_id, location, message, data=None):  # type: ignore[misc]
        pass

_ACK_DEDUPE: dict[str, float] = {}
_FAST_READ_RE = re.compile(
    r"(?i)\b("
    r"what(?:'s| is) on|calendar|saturday|sunday|monday|tuesday|wednesday|thursday|friday|"
    r"chores? today|schedule|this week|tomorrow|meal|grocery"
    r")\b"
)


def resolve_hooks_token() -> str:
    token = (os.environ.get("OPENCLAW_HOOKS_TOKEN") or "").strip()
    if token:
        return token
    try:
        with open(os.path.expanduser("~/.openclaw/hooks-token.txt"), encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def resolve_family_hub_room() -> str:
    return (os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM") or "9x4f25n3").strip()


def agent_id_for_room(room_token: str, family_hub_room: str | None = None) -> str:
    fam = family_hub_room if family_hub_room is not None else resolve_family_hub_room()
    return "family" if room_token == fam else "main"


def is_family_fast_read(message: str) -> bool:
    if os.environ.get("FAMILY_FAST_READ", "0") != "1":
        return False
    text = (message or "").strip()
    if not text:
        return False
    max_words = int(os.environ.get("FAMILY_FAST_MAX_WORDS", "12"))
    if len(text.split()) > max_words:
        return False
    return bool(_FAST_READ_RE.search(text))


def resolve_agent_id(room_token: str, message: str, family_hub_room: str | None = None) -> str:
    fam = family_hub_room if family_hub_room is not None else resolve_family_hub_room()
    if room_token == fam and is_family_fast_read(message):
        return "main"
    return agent_id_for_room(room_token, fam)


def strip_agent_mention(text: str, agent_name: str) -> str:
    cleaned = re.sub(rf"(?i)(^|\s)@{re.escape(agent_name)}[:\s]?", " ", text or "").strip()
    return cleaned or (text or "").strip()


def post_talk_message(room_token: str, message: str) -> bool:
    if not room_token or not (message or "").strip():
        return False
    talk_post = os.path.expanduser("~/.openclaw/scripts/talk-post.sh")
    if not os.path.isfile(talk_post):
        return False
    try:
        result = subprocess.run(
            ["bash", talk_post, message.strip(), room_token],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception as exc:
        print(f"[talk-hooks] talk-post failed: {exc}", flush=True)
        return False


def _ack_dedupe_key(room_token: str, message: str) -> str:
    digest = hashlib.sha256(message.strip().lower().encode()).hexdigest()[:16]
    return f"{room_token}:{digest}"


def should_post_dispatch_ack(room_token: str, family_hub_room: str | None = None) -> bool:
    fam = family_hub_room if family_hub_room is not None else resolve_family_hub_room()
    if os.environ.get("TALK_DISPATCH_ACK", "").strip() == "0":
        return False
    if os.environ.get("TALK_DISPATCH_ACK", "").strip() == "1":
        return True
    if room_token == fam:
        return True
    return os.environ.get("TALK_OPS_ACK", "0").strip() == "1"


def post_dispatch_ack(room_token: str, message: str, family_hub_room: str | None = None) -> bool:
    if not should_post_dispatch_ack(room_token, family_hub_room):
        return False
    dedupe_s = float(os.environ.get("TALK_ACK_DEDUPE_SECONDS", "10"))
    key = _ack_dedupe_key(room_token, message)
    now = time.monotonic()
    last = _ACK_DEDUPE.get(key, 0.0)
    if now - last < dedupe_s:
        return False
    _ACK_DEDUPE[key] = now
    fam = family_hub_room if family_hub_room is not None else resolve_family_hub_room()
    default = (
        "Got it — checking…"
        if room_token == fam
        else "Got it — working on that…"
    )
    ack = (os.environ.get("TALK_ACK_MESSAGE") or default).strip()
    return post_talk_message(room_token, ack)


def dispatch_talk_to_gateway(
    *,
    room_token: str,
    message: str,
    actor_id: str = "",
    origin: str = "talk-hooks-dispatch",
    family_hub_room: str | None = None,
    agent_name: str | None = None,
    strip_mention: bool = False,
    gateway_url: str | None = None,
    hooks_token: str | None = None,
    timeout_seconds: int = 240,
    http_timeout: float = 8.0,
    log_prefix: str = "[talk-hooks]",
    post_ack: bool = True,
) -> bool:
    """Wake OpenClaw via POST /hooks/agent. Returns True if wake accepted."""
    token = hooks_token if hooks_token is not None else resolve_hooks_token()
    if not token:
        print(f"{log_prefix} ERROR: no hooks token configured; cannot dispatch", flush=True)
        return False

    cleaned = (message or "").strip()
    if not cleaned:
        return False

    if strip_mention:
        name = (agent_name or os.environ.get("OPENCLAW_AGENT_MENTION", "@alfred").lstrip("@") or "alfred")
        cleaned = strip_agent_mention(cleaned, name)
        if not cleaned:
            return False

    fam_room = family_hub_room if family_hub_room is not None else resolve_family_hub_room()
    agent = resolve_agent_id(room_token, cleaned, fam_room)
    session_key = f"agent:{agent}:nextcloud-talk:group:{room_token}"
    gateway = (gateway_url or os.environ.get("GATEWAY_URL") or "http://127.0.0.1:18789").rstrip("/")
    talk_debug(
        "H3",
        "talk_hooks_dispatch.py:dispatch_start",
        "hooks dispatch attempt",
        {"room": room_token, "agent": agent, "sessionKey": session_key, "origin": origin},
    )

    body = {
        "name": "talk-mention",
        "message": cleaned,
        "agentId": agent,
        "wakeMode": "now",
        "deliver": True,
        "channel": "nextcloud-talk",
        "to": f"nextcloud-talk:{room_token}",
        "sessionKey": session_key,
        "timeoutSeconds": timeout_seconds,
    }
    talk_debug(
        "H4",
        "talk_hooks_dispatch.py:dispatch_body",
        "hooks payload delivery target",
        {"room": room_token, "channel": body["channel"], "to": body["to"], "sessionKey": session_key},
    )
    req = urllib.request.Request(
        f"{gateway}/hooks/agent",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "X-OpenClaw-Origin": origin,
            "X-OpenClaw-Actor": actor_id or "unknown",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=http_timeout) as resp:
            status = resp.status
            print(
                f"{log_prefix} dispatched room={room_token} agent={agent} actor={actor_id} "
                f"({len(cleaned)} chars) -> HTTP {status}",
                flush=True,
            )
            if 200 <= status < 300 and post_ack:
                ack_ok = post_dispatch_ack(room_token, cleaned, fam_room)
                talk_debug(
                    "H4",
                    "talk_hooks_dispatch.py:dispatch_ok",
                    "hooks dispatch accepted",
                    {"room": room_token, "agent": agent, "httpStatus": status, "ackPosted": ack_ok},
                )
            else:
                talk_debug(
                    "H3",
                    "talk_hooks_dispatch.py:dispatch_bad_status",
                    "hooks dispatch non-2xx",
                    {"room": room_token, "agent": agent, "httpStatus": status},
                )
            return 200 <= status < 300
    except TimeoutError:
        print(
            f"{log_prefix} dispatched room={room_token} agent={agent} actor={actor_id} "
            f"({len(cleaned)} chars) -> HTTP timeout (wake likely started)",
            flush=True,
        )
        if post_ack:
            ack_ok = post_dispatch_ack(room_token, cleaned, fam_room)
            talk_debug(
                "H4",
                "talk_hooks_dispatch.py:dispatch_timeout",
                "hooks dispatch timeout treated as started",
                {"room": room_token, "agent": agent, "ackPosted": ack_ok},
            )
        return True
    except urllib.error.HTTPError as exc:
        talk_debug(
            "H3",
            "talk_hooks_dispatch.py:dispatch_http_error",
            "hooks dispatch HTTP error",
            {"room": room_token, "agent": agent, "httpStatus": exc.code},
        )
        print(
            f"{log_prefix} dispatch HTTPError room={room_token} status={exc.code} "
            f"body={exc.read()[:200]!r}",
            flush=True,
        )
        return False
    except Exception as exc:
        print(f"{log_prefix} dispatch EXCEPTION room={room_token}: {exc}", flush=True)
        return False
