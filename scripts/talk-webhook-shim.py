#!/usr/bin/env python3
"""
Nextcloud Talk webhook shim — intercept fast-paths before OpenClaw LLM.

NC bot posts to :8788 (this shim). OpenClaw plugin listens on :8787.
Also drops inbound messages from the OpenClaw NC user to stop error-reply loops.

Order (Family Hub):
  household YES/NO/EDIT (incl. meal-plan-*) → recipe/bread → meal plan propose →
  chores/done → help → subaru → hooks LLM / upstream
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
for _lib_dir in (
    os.path.join(SCRIPT_DIR, "lib"),
    os.path.expanduser("~/.openclaw/scripts/lib"),
    os.path.expanduser("~/.openclaw/lib"),
    os.path.expanduser("~/openclaw-subaru/scripts/lib"),
):
    if os.path.isdir(_lib_dir) and _lib_dir not in sys.path:
        sys.path.insert(0, _lib_dir)
from subaru_talk_match import (  # noqa: E402
    extract_room_token,
    extract_user_message,
    is_noise_echo,
    is_overflow_echo,
    is_subaru_command,
    is_talk_message_envelope,
    is_tool_json_payload,
    normalize_talk_text,
)
from talk_hooks_dispatch import dispatch_talk_to_gateway  # noqa: E402

try:
    from recipe_talk_match import is_recipe_command
except ImportError:  # pragma: no cover
    def is_recipe_command(text: str, agent_name: str = "alfred") -> bool:
        return False

try:
    from talk_help import is_help_command, load_help_text
except ImportError:  # pragma: no cover
    def is_help_command(text: str) -> bool:
        return False

    def load_help_text(room_token: str, family_hub_room: str | None = None) -> str:
        return "help unavailable"

try:
    from chore_talk_match import is_chore_command, is_meal_plan_command
except ImportError:  # pragma: no cover
    def is_chore_command(text: str, agent_name: str = "alfred") -> bool:
        return False

    def is_meal_plan_command(text: str, agent_name: str = "alfred") -> bool:
        return False

try:
    from forge_talk_match import is_forge_command
except ImportError:  # pragma: no cover
    def is_forge_command(text: str, agent_name: str = "alfred") -> bool:
        return False


def resolve_listen_host(env: dict[str, str] | None = None) -> str:
    """Loopback by default; LAN exposure is opt-in.

    Precedence: explicit ``TALK_SHIM_HOST`` wins, else ``TALK_SHIM_LAN=1`` binds
    all interfaces (``0.0.0.0``), else loopback (``127.0.0.1``).
    """
    env = env if env is not None else os.environ
    explicit = (env.get("TALK_SHIM_HOST") or "").strip()
    if explicit:
        return explicit
    if (env.get("TALK_SHIM_LAN") or "").strip() == "1":
        return "0.0.0.0"
    return "127.0.0.1"


LISTEN_HOST = resolve_listen_host()
LISTEN_PORT = int(os.environ.get("TALK_SHIM_PORT", "8788"))
UPSTREAM = os.environ.get(
    "TALK_SHIM_UPSTREAM", "http://127.0.0.1:8787/nextcloud-talk-webhook"
).rstrip("/")
if not UPSTREAM.endswith("/nextcloud-talk-webhook"):
    UPSTREAM = UPSTREAM.rstrip("/") + "/nextcloud-talk-webhook"

AGENT_MENTION = (os.environ.get("OPENCLAW_AGENT_MENTION", "@openclaw").strip() or "@openclaw")
AGENT_NAME = (AGENT_MENTION.lstrip("@").lower() or "openclaw")
FAMILY_HUB_ROOM = os.environ.get("SKYLIGHT_FAMILY_TALK_ROOM", "9x4f25n3")
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:18789")
PLUGIN_FALLBACK = os.environ.get("TALK_SHIM_PLUGIN_FALLBACK", "0").strip() == "1"
_default_aliases = f"{AGENT_MENTION},{AGENT_MENTION.title()},{AGENT_NAME},openclaw"
OPENCLAW_ACTOR_IDS = tuple(
    a.strip().lower()
    for a in os.environ.get("OPENCLAW_ACTOR_IDS", _default_aliases).split(",")
    if a.strip()
)
BOT_ACTOR_IDS = tuple(
    a.strip().lower()
    for a in os.environ.get("TALK_BOT_ACTOR_IDS", "bots/openclaw,openclaw").split(",")
    if a.strip()
)

# Include meal-plan-* (ISO week) as well as enrich/ask proposals.
_HOUSEHOLD_PROPOSAL_RE = re.compile(
    rf"(?i)@?{re.escape(AGENT_NAME)}\s+(YES|NO|EDIT)\s+"
    r"(enrich-calendar-|enrich-chore-|ask-|meal-plan-)[0-9]"
)


def _is_household_proposal(text: str) -> bool:
    return bool(_HOUSEHOLD_PROPOSAL_RE.search(normalize_talk_text(text)))


def _parse_create_message(body: dict) -> tuple[str, str, str, str] | None:
    if body.get("type") != "Create":
        return None
    actor = body.get("actor") or {}
    obj = body.get("object") or {}
    target = body.get("target") or {}
    actor_id = (actor.get("id") or "").strip()
    text = (obj.get("content") or obj.get("name") or "").strip()
    room_token = extract_room_token((target.get("id") or "").strip())
    actor_name = (actor.get("name") or actor_id or "unknown").strip()
    if not (actor_id and room_token):
        return None
    return room_token, text, actor_id, actor_name


def _run_fast_path(
    script: str, text: str, room_token: str, *, include_room_token: bool = True
) -> bool:
    clean = extract_user_message(text)
    cmd = ["bash", script, clean]
    if include_room_token:
        cmd.append(room_token)
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
        )
        print(
            f"[shim] {os.path.basename(script)} room={room_token} text={clean[:80]!r} "
            f"rc={result.returncode} out={(result.stdout or '')[:160]!r} "
            f"err={(result.stderr or '')[:120]!r}",
            file=sys.stderr,
        )
        return result.returncode == 0
    except Exception as exc:
        print(f"[shim] fast-path EXCEPTION script={script}: {exc}", file=sys.stderr)
        return False


def _post_talk(room_token: str, message: str) -> None:
    talk_post = os.path.expanduser("~/.openclaw/scripts/talk-post.sh")
    if not os.path.isfile(talk_post):
        return
    subprocess.run(
        ["bash", talk_post, message, room_token],
        capture_output=True,
        text=True,
        timeout=30,
    )


def _is_openclaw_actor(actor_id: str, actor_name: str) -> bool:
    actor_lc = (actor_id or "").lower()
    actor_name_lc = (actor_name or "").lower()
    if actor_lc in OPENCLAW_ACTOR_IDS or actor_lc == AGENT_NAME:
        return True
    if actor_lc.endswith(f"/{AGENT_NAME}") or actor_lc == f"users/{AGENT_NAME}":
        return True
    if actor_name_lc in {AGENT_NAME, "openclaw"}:
        return True
    return False


def _forward(raw: bytes, headers: dict[str, str]) -> tuple[int, bytes]:
    req = urllib.request.Request(UPSTREAM, data=raw, method="POST")
    skip = {"host", "content-length", "transfer-encoding", "connection"}
    for key, value in headers.items():
        if key.lower() in skip:
            continue
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        print(f"[shim] upstream unreachable {UPSTREAM}: {exc.reason}", file=sys.stderr)
        body = json.dumps({"error": "upstream unreachable", "upstream": UPSTREAM}).encode()
        return 502, body


def _script(name: str) -> str:
    return os.path.expanduser(f"~/.openclaw/scripts/{name}")


class ShimHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > 1_000_000:
            self.send_response(413)
            self.end_headers()
            return
        raw = self.rfile.read(length)
        path = self.path.split("?", 1)[0]
        if path not in ("/nextcloud-talk-webhook", "/"):
            self.send_response(404)
            self.end_headers()
            return

        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            status, out = _forward(raw, dict(self.headers))
            self.send_response(status)
            self.end_headers()
            if out:
                self.wfile.write(out)
            return

        event_type = body.get("type") or ""
        if event_type != "Create":
            print(f"[shim] drop non-Create type={event_type!r}", file=sys.stderr)
            self.send_response(200)
            self.end_headers()
            return

        parsed = _parse_create_message(body)
        if parsed:
            room_token, text, actor_id, actor_name = parsed
            actor_lc = actor_id.lower()
            actor_name_lc = actor_name.lower()

            if is_talk_message_envelope(text):
                text = extract_user_message(text)
                print(
                    f"[shim] unwrap talk envelope room={room_token} actor={actor_id} "
                    f"text={text[:80]!r}",
                    file=sys.stderr,
                )

            if is_noise_echo(text):
                print(
                    f"[shim] drop noise echo room={room_token} actor={actor_id} "
                    f"tool_json={is_tool_json_payload(text)}",
                    file=sys.stderr,
                )
                self.send_response(200)
                self.end_headers()
                return

            if _is_openclaw_actor(actor_id, actor_name):
                print(
                    f"[shim] drop self-echo room={room_token} actor={actor_id}",
                    file=sys.stderr,
                )
                self.send_response(200)
                self.end_headers()
                return

            if actor_lc in BOT_ACTOR_IDS or actor_name_lc == "openclaw":
                if is_overflow_echo(text):
                    print(
                        f"[shim] drop bot overflow echo room={room_token} actor={actor_id}",
                        file=sys.stderr,
                    )
                    self.send_response(200)
                    self.end_headers()
                    return

            household_dispatch = _script("skylight-family-hub-dispatch.sh")
            if _is_household_proposal(text) and os.path.isfile(household_dispatch):
                if _run_fast_path(
                    household_dispatch, text, room_token, include_room_token=False
                ):
                    self.send_response(200)
                    self.end_headers()
                    return

            if is_help_command(normalize_talk_text(extract_user_message(text))):
                _post_talk(room_token, load_help_text(room_token, FAMILY_HUB_ROOM))
                print(f"[shim] help fast-path room={room_token}", file=sys.stderr)
                self.send_response(200)
                self.end_headers()
                return

            if is_recipe_command(text, AGENT_NAME):
                recipe_fp = _script("skylight-recipe-talk-fast-path.sh")
                if os.path.isfile(recipe_fp) and _run_fast_path(recipe_fp, text, room_token):
                    self.send_response(200)
                    self.end_headers()
                    return
                _post_talk(
                    room_token,
                    f"Recipe: command failed. Try: {AGENT_MENTION} recipe banana",
                )
                self.send_response(200)
                self.end_headers()
                return

            if is_meal_plan_command(text, AGENT_NAME):
                meal_fp = _script("skylight-meal-plan-talk-fast-path.sh")
                if os.path.isfile(meal_fp) and _run_fast_path(meal_fp, text, room_token):
                    self.send_response(200)
                    self.end_headers()
                    return
                _post_talk(
                    room_token,
                    f"Meal plan failed. Try: {AGENT_MENTION} meal plan",
                )
                self.send_response(200)
                self.end_headers()
                return

            if is_chore_command(text, AGENT_NAME):
                chore_fp = _script("skylight-chore-talk-fast-path.sh")
                if os.path.isfile(chore_fp) and _run_fast_path(chore_fp, text, room_token):
                    self.send_response(200)
                    self.end_headers()
                    return
                _post_talk(
                    room_token,
                    f"Chores failed. Try: {AGENT_MENTION} chores | {AGENT_MENTION} done dishes",
                )
                self.send_response(200)
                self.end_headers()
                return

            if is_subaru_command(text, AGENT_NAME):
                fast_path = _script("subaru-talk-fast-path.sh")
                ok = os.path.isfile(fast_path) and _run_fast_path(fast_path, text, room_token)
                if not ok:
                    _post_talk(
                        room_token,
                        f"Subaru: command failed. Try: {AGENT_MENTION} subaru status",
                    )
                self.send_response(200)
                self.end_headers()
                return

            if is_forge_command(text, AGENT_NAME):
                forge_fp = _script("forge-talk-fast-path.sh")
                ok = os.path.isfile(forge_fp) and _run_fast_path(forge_fp, text, room_token)
                if not ok:
                    _post_talk(
                        room_token,
                        f"Forge: command failed. Try: {AGENT_MENTION} print status",
                    )
                self.send_response(200)
                self.end_headers()
                return

            if room_token == FAMILY_HUB_ROOM:
                clean = normalize_talk_text(extract_user_message(text))
                if clean and dispatch_talk_to_gateway(
                    room_token=room_token,
                    message=clean,
                    actor_id=actor_id,
                    origin="talk-webhook-shim/family-hub",
                    family_hub_room=FAMILY_HUB_ROOM,
                    gateway_url=GATEWAY_URL,
                    log_prefix="[shim]",
                ):
                    self.send_response(200)
                    self.end_headers()
                    return
                print(
                    f"[shim] family hooks dispatch failed room={room_token}",
                    file=sys.stderr,
                )
                if not PLUGIN_FALLBACK:
                    _post_talk(
                        room_token,
                        "Alfred couldn't reach the family agent just now. "
                        "Try again shortly, or @alfred help for commands.",
                    )
                    self.send_response(200)
                    self.end_headers()
                    return

        status, out = _forward(raw, dict(self.headers))
        self.send_response(status)
        self.end_headers()
        if out:
            self.wfile.write(out)

    def do_GET(self):
        if self.path.split("?", 1)[0] in ("/", "/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "service": "talk-webhook-shim",
                        "upstream": UPSTREAM,
                        "agent_name": AGENT_NAME,
                        "fast_paths": [
                            "household",
                            "help",
                            "recipe",
                            "meal-plan",
                            "chores",
                            "subaru",
                            "forge",
                        ],
                    }
                ).encode()
            )
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        print(f"[shim] {self.address_string()} {fmt % args}", file=sys.stderr)


def main() -> None:
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), ShimHandler)
    print(
        f"[shim] Talk webhook shim on {LISTEN_HOST}:{LISTEN_PORT} → {UPSTREAM}",
        file=sys.stderr,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
